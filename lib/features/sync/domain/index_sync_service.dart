import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/crypto/hash_utils.dart';
import '../../../core/database/filo_database.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../storage/domain/storage_backend.dart';

/// Riverpod provider for IndexSyncService
final indexSyncServiceProvider = Provider<IndexSyncService>((ref) {
  final db = ref.watch(databaseProvider);
  final storage = ref.watch(storageBackendProvider);
  final authRepo = ref.watch(authRepositoryProvider);
  final service = IndexSyncService(
    database: db,
    storageBackend: storage,
    authRepository: authRepo,
  );
  ref.onDispose(service.dispose);
  return service;
});

/// Manages cross-device zero-knowledge index synchronization and re-install restoration.
///
/// Features:
/// - Serializes the entire local directory structure and chunk catalog into an encrypted snapshot.
/// - Packages the user's encrypted key bundle into an outer snapshot envelope so that on app
///   re-installation or login to a new device, the vault key configuration can be automatically
///   retrieved from the private Telegram channel 'filo'.
/// - Debounced automatic background backup after file actions (uploads, renames, deletions).
/// - Automatic cloud snapshot restoration on fresh device login.
class IndexSyncService {
  final FiloDatabase _database;
  final StorageBackend _storageBackend;
  final AuthRepository? _authRepository;
  Timer? _debounceTimer;
  bool _isSyncing = false;

  IndexSyncService({
    required FiloDatabase database,
    required StorageBackend storageBackend,
    AuthRepository? authRepository,
  })  : _database = database,
        _storageBackend = storageBackend,
        _authRepository = authRepository;

  bool get isSyncing => _isSyncing;

  /// Schedules a debounced background backup of the local index to the cloud.
  /// Prevents API flooding when multiple files or folders are modified in quick succession.
  void triggerAutoSync({
    required Uint8List masterKey,
    Duration delay = const Duration(seconds: 3),
  }) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () async {
      if (_isSyncing) return;
      try {
        _isSyncing = true;
        await backupIndexToCloud(masterKey: masterKey);
      } catch (_) {
        // Non-fatal background sync failure
      } finally {
        _isSyncing = false;
      }
    });
  }

  /// Cancels any scheduled debounced sync.
  void dispose() {
    _debounceTimer?.cancel();
  }

  /// Checks if the local database is empty and automatically restores the latest pinned snapshot.
  /// Returns true if a cloud backup was found and restored.
  Future<bool> checkAndAutoRestore({
    required Uint8List masterKey,
  }) async {
    final count = await _database.getNodeCount();
    if (count > 0) {
      return false; // Local database already has data
    }
    return restoreIndexFromCloud(masterKey: masterKey);
  }

  /// Fetches the cloud snapshot envelope without needing masterKey.
  /// Used during initial setup or new device login to detect existing vaults in channel 'filo'.
  Future<Map<String, dynamic>?> fetchCloudVaultKeyBundle() async {
    try {
      final channel = await _storageBackend.getOrCreateVaultChannel(AppConfig.vaultChannelTitle);
      final pinned = await _storageBackend.getPinnedMessage(channelId: channel.channelId);
      if (pinned == null || pinned.remoteFileId == null) {
        return null;
      }

      final downloadedBytes = await _storageBackend.downloadChunk(
        channelId: channel.channelId,
        remoteFileId: pinned.remoteFileId!,
      );

      final decodedStr = utf8.decode(downloadedBytes, allowMalformed: true);
      if (!decodedStr.trimLeft().startsWith('{')) {
        return null; // Not in JSON envelope format
      }

      final envelope = json.decode(decodedStr) as Map<String, dynamic>;
      if (envelope['vaultBundle'] != null || envelope['wrappedBundle'] != null) {
        return envelope;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Backs up the entire local index to the private Telegram channel as a pinned, encrypted document.
  Future<String> backupIndexToCloud({
    required Uint8List masterKey,
  }) async {
    // 1. Export local index JSON
    final jsonStr = await _database.exportSnapshotJson();
    final jsonBytes = utf8.encode(jsonStr);

    // 2. Encrypt catalog on-device with Master Key (AES-256-GCM)
    final encryptedCatalog = await CryptoEngine.encryptBytes(
      plaintext: jsonBytes,
      key: masterKey,
    );

    // 3. Export wrapped key bundle from auth repository (zero-knowledge envelope)
    final keyBundle = await _authRepository?.exportVaultKeyBundle();

    // 4. Construct zero-knowledge snapshot envelope
    final envelope = <String, dynamic>{
      'version': 1,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'vaultBundle': keyBundle?['wrappedBundle'],
      'recoveryBundle': keyBundle?['recoveryBundle'],
      'recoveryKeyHash': keyBundle?['recoveryKeyHash'],
      'catalogCiphertextHex': HashUtils.bytesToHex(encryptedCatalog),
    };
    final envelopeBytes = Uint8List.fromList(utf8.encode(json.encode(envelope)));

    // 5. Locate or create vault channel ('filo')
    final channel = await _storageBackend.getOrCreateVaultChannel(AppConfig.vaultChannelTitle);

    // 6. Upload encrypted snapshot document as index.filo
    final remoteChunk = await _storageBackend.uploadChunk(
      channelId: channel.channelId,
      chunkData: envelopeBytes,
      partFileName: 'index.filo',
    );

    // 7. Pin the snapshot message at the top of the channel
    await _storageBackend.pinMessage(
      channelId: channel.channelId,
      messageId: remoteChunk.messageId,
    );

    return remoteChunk.messageId;
  }

  /// Downloads the pinned encrypted index from the vault channel and reconstructs the local database.
  Future<bool> restoreIndexFromCloud({
    required Uint8List masterKey,
  }) async {
    // 1. Locate vault channel ('filo')
    final channel = await _storageBackend.getOrCreateVaultChannel(AppConfig.vaultChannelTitle);

    // 2. Fetch pinned message
    final pinned = await _storageBackend.getPinnedMessage(channelId: channel.channelId);
    if (pinned == null || pinned.remoteFileId == null) {
      return false; // No existing cloud backup found
    }

    // 3. Download snapshot bytes
    final downloadedBytes = await _storageBackend.downloadChunk(
      channelId: channel.channelId,
      remoteFileId: pinned.remoteFileId!,
    );

    Uint8List encryptedCatalogBytes;
    final decodedStr = utf8.decode(downloadedBytes, allowMalformed: true);

    if (decodedStr.trimLeft().startsWith('{')) {
      try {
        final envelope = json.decode(decodedStr) as Map<String, dynamic>;
        if (envelope.containsKey('catalogCiphertextHex')) {
          encryptedCatalogBytes = HashUtils.hexToBytes(envelope['catalogCiphertextHex'] as String);
          if (_authRepository != null) {
            await _authRepository.importVaultKeyBundle(envelope);
          }
        } else {
          encryptedCatalogBytes = downloadedBytes;
        }
      } catch (_) {
        encryptedCatalogBytes = downloadedBytes;
      }
    } else {
      // Legacy raw encrypted bytes fallback
      encryptedCatalogBytes = downloadedBytes;
    }

    // 4. Decrypt on-device with Master Key
    final decryptedBytes = await CryptoEngine.decryptBytes(
      combinedBytes: encryptedCatalogBytes,
      key: masterKey,
    );

    // 5. Rebuild local SQLite index
    final jsonStr = utf8.decode(decryptedBytes);
    await _database.restoreFromSnapshotJson(jsonStr);

    return true;
  }
}
