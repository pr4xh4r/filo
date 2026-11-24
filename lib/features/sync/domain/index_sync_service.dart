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

/// Sync lifecycle states for background automatic cloud backup.
enum AutoSyncPhase { idle, syncing, synced, error }

class AutoSyncStatus {
  final AutoSyncPhase phase;
  final DateTime? lastSyncedAt;
  final String? lastError;

  const AutoSyncStatus({
    this.phase = AutoSyncPhase.idle,
    this.lastSyncedAt,
    this.lastError,
  });
}

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

/// Reactive status stream for UI display (e.g. Settings status badge).
final autoSyncStatusProvider = StreamProvider<AutoSyncStatus>((ref) async* {
  final service = ref.watch(indexSyncServiceProvider);
  yield service.currentStatus;
  yield* service.statusStream;
});

/// Manages cross-device zero-knowledge index synchronization and re-install restoration.
///
/// Features:
/// - Serializes the entire local directory structure, workspaces, and chunk catalog into an encrypted snapshot.
/// - Packages the user's encrypted key bundle into an outer snapshot envelope so that on app
///   re-installation or login to a new device, the vault key configuration can be automatically
///   retrieved from the private Telegram channel 'filo'.
/// - Debounced automatic background backup after file/folder/space actions with pending-change queuing and auto-retry.
/// - Automatic cloud snapshot restoration on fresh device login or remote updates.
class IndexSyncService {
  final FiloDatabase _database;
  final StorageBackend _storageBackend;
  final AuthRepository? _authRepository;
  Timer? _debounceTimer;
  Timer? _retryTimer;
  bool _isSyncing = false;
  bool _pendingResync = false;
  bool _hasPendingChanges = false;
  int _retryAttempt = 0;
  Uint8List? _lastMasterKey;
  DateTime? _lastRemoteCheckAt;

  AutoSyncStatus _currentStatus = const AutoSyncStatus();
  final StreamController<AutoSyncStatus> _statusController =
      StreamController<AutoSyncStatus>.broadcast();

  IndexSyncService({
    required FiloDatabase database,
    required StorageBackend storageBackend,
    AuthRepository? authRepository,
  })  : _database = database,
        _storageBackend = storageBackend,
        _authRepository = authRepository;

  bool get isSyncing => _isSyncing;
  AutoSyncStatus get currentStatus => _currentStatus;
  Stream<AutoSyncStatus> get statusStream => _statusController.stream;

  void _emitStatus(AutoSyncStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  /// Schedules a debounced background backup of the local index to the cloud.
  /// Prevents API flooding when multiple files or folders are modified in quick succession,
  /// and guarantees no concurrent edits are dropped.
  void triggerAutoSync({
    required Uint8List masterKey,
    Duration delay = const Duration(seconds: 3),
  }) {
    _lastMasterKey = Uint8List.fromList(masterKey);
    _hasPendingChanges = true;
    unawaited(_database.markSyncDirty());
    _debounceTimer?.cancel();
    _retryTimer?.cancel();

    if (_isSyncing) {
      _pendingResync = true;
      return;
    }

    _debounceTimer = Timer(delay, () {
      unawaited(_executeSync(_lastMasterKey!));
    });
  }

  /// Immediately flushes any pending debounced backup (e.g., when the app moves to background).
  Future<void> flushPendingSync() async {
    final keySnapshot = _lastMasterKey != null ? Uint8List.fromList(_lastMasterKey!) : null;
    if (keySnapshot == null) return;
    final dirty = await _database.getSyncMeta('sync_dirty');
    if (!_hasPendingChanges && dirty != '1') return;
    if (_isSyncing) {
      _pendingResync = true;
      return;
    }
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    await _executeSync(keySnapshot);
  }

  /// Zeroes cached key material from memory when vault is locked or user signs out.
  void clearSessionKey() {
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _pendingResync = false;
    if (_lastMasterKey != null) {
      _lastMasterKey!.fillRange(0, _lastMasterKey!.length, 0);
      _lastMasterKey = null;
    }
  }

  Future<void> _executeSync(Uint8List masterKey) async {
    if (_isSyncing) {
      _pendingResync = true;
      return;
    }

    _isSyncing = true;
    _emitStatus(AutoSyncStatus(
      phase: AutoSyncPhase.syncing,
      lastSyncedAt: _currentStatus.lastSyncedAt,
    ));

    try {
      await backupIndexToCloud(masterKey: masterKey);
      _hasPendingChanges = false;
      _retryAttempt = 0;
      _emitStatus(AutoSyncStatus(
        phase: AutoSyncPhase.synced,
        lastSyncedAt: DateTime.now(),
      ));
    } catch (e) {
      _hasPendingChanges = true;
      _emitStatus(AutoSyncStatus(
        phase: AutoSyncPhase.error,
        lastSyncedAt: _currentStatus.lastSyncedAt,
        lastError: e.toString(),
      ));
      // Exponential backoff auto-retry so temporary network loss recovers automatically
      if (_retryAttempt < 5 && !_statusController.isClosed) {
        final backoffSeconds = (10 * (1 << _retryAttempt)).clamp(10, 60);
        _retryAttempt++;
        _retryTimer?.cancel();
        _retryTimer = Timer(Duration(seconds: backoffSeconds), () {
          if (_lastMasterKey != null && _hasPendingChanges && !_isSyncing) {
            unawaited(_executeSync(_lastMasterKey!));
          }
        });
      }
    } finally {
      _isSyncing = false;
      if (_pendingResync && _lastMasterKey != null && !_statusController.isClosed) {
        _pendingResync = false;
        unawaited(_executeSync(_lastMasterKey!));
      }
    }
  }

  /// Cancels any scheduled debounced/retry timers and closes streams.
  void dispose() {
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    if (!_statusController.isClosed) {
      _statusController.close();
    }
  }

  /// Checks if the local database is empty (or behind another synced device)
  /// and automatically restores the latest pinned cloud backup, or flushes dirty local edits.
  /// Returns true if cloud data was restored locally.
  Future<bool> checkAndAutoRestore({
    required Uint8List masterKey,
  }) async {
    _lastMasterKey = Uint8List.fromList(masterKey);
    final count = await _database.getNodeCount();
    if (count == 0) {
      return restoreIndexFromCloud(masterKey: masterKey);
    }

    final dirty = await _database.getSyncMeta('sync_dirty');
    if (dirty == '1') {
      // Local device has un-uploaded edits; push them automatically
      triggerAutoSync(masterKey: masterKey, delay: const Duration(milliseconds: 300));
      return false;
    }

    final lastRemoteMsgId = await _database.getSyncMeta('last_remote_message_id');
    if (lastRemoteMsgId == null) {
      return false;
    }

    final channel = await _storageBackend.getOrCreateVaultChannel(AppConfig.vaultChannelTitle);
    final pinned = await _storageBackend.getPinnedMessage(channelId: channel.channelId);
    if (pinned != null && pinned.messageId != lastRemoteMsgId) {
      return restoreIndexFromCloud(masterKey: masterKey);
    }
    return false;
  }

  /// Non-blocking remote update check on app resume (throttled to prevent excessive Telegram API calls).
  Future<bool> checkRemoteUpdates({
    required Uint8List masterKey,
  }) async {
    final now = DateTime.now();
    if (_lastRemoteCheckAt != null &&
        now.difference(_lastRemoteCheckAt!) < const Duration(seconds: 45)) {
      return false;
    }
    _lastRemoteCheckAt = now;
    try {
      return await checkAndAutoRestore(masterKey: masterKey);
    } catch (_) {
      return false;
    }
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

    await _database.setSyncMeta('last_remote_message_id', remoteChunk.messageId);
    await _database.setSyncMeta('last_synced_at', (envelope['timestamp'] as int).toString());
    await _database.setSyncMeta('sync_dirty', '0');

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
    await _database.setSyncMeta('last_remote_message_id', pinned.messageId);

    return true;
  }
}
