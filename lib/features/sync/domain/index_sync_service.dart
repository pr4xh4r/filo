import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_config.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/database/filo_database.dart';
import '../../auth/presentation/providers/auth_provider.dart';
import '../../storage/domain/storage_backend.dart';

/// Riverpod provider for IndexSyncService
final indexSyncServiceProvider = Provider<IndexSyncService>((ref) {
  final db = ref.watch(databaseProvider);
  final storage = ref.watch(storageBackendProvider);
  final service = IndexSyncService(database: db, storageBackend: storage);
  ref.onDispose(service.dispose);
  return service;
});

/// Manages cross-device zero-knowledge index synchronization.
///
/// Features:
/// - Serializes the entire local directory structure and chunk catalog into an encrypted snapshot.
/// - Debounced automatic background backup after file actions (uploads, renames, deletions).
/// - Automatic cloud snapshot restoration on fresh device login.
class IndexSyncService {
  final FiloDatabase _database;
  final StorageBackend _storageBackend;
  Timer? _debounceTimer;
  bool _isSyncing = false;

  IndexSyncService({
    required FiloDatabase database,
    required StorageBackend storageBackend,
  })  : _database = database,
        _storageBackend = storageBackend;

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

  /// Backs up the entire local index to the private Telegram channel as a pinned, encrypted document.
  Future<String> backupIndexToCloud({
    required Uint8List masterKey,
  }) async {
    // 1. Export local index JSON
    final jsonStr = await _database.exportSnapshotJson();
    final jsonBytes = utf8.encode(jsonStr);

    // 2. Encrypt on-device with Master Key (AES-256-GCM)
    final encrypted = await CryptoEngine.encryptBytes(
      plaintext: jsonBytes,
      key: masterKey,
    );

    // 3. Locate or create vault channel
    final channel = await _storageBackend.getOrCreateVaultChannel(AppConfig.vaultChannelTitle);

    // 4. Upload encrypted snapshot document
    final remoteChunk = await _storageBackend.uploadChunk(
      channelId: channel.channelId,
      chunkData: encrypted,
      partFileName: 'index.filo',
    );

    // 5. Pin the snapshot message at the top of the channel
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
    // 1. Locate vault channel
    final channel = await _storageBackend.getOrCreateVaultChannel(AppConfig.vaultChannelTitle);

    // 2. Fetch pinned message
    final pinned = await _storageBackend.getPinnedMessage(channelId: channel.channelId);
    if (pinned == null || pinned.remoteFileId == null) {
      return false; // No existing cloud backup found
    }

    // 3. Download encrypted snapshot
    final encryptedData = await _storageBackend.downloadChunk(
      channelId: channel.channelId,
      remoteFileId: pinned.remoteFileId!,
    );

    // 4. Decrypt on-device with Master Key
    final decryptedBytes = await CryptoEngine.decryptBytes(
      combinedBytes: encryptedData,
      key: masterKey,
    );

    // 5. Rebuild local SQLite index
    final jsonStr = utf8.decode(decryptedBytes);
    await _database.restoreFromSnapshotJson(jsonStr);

    return true;
  }
}
