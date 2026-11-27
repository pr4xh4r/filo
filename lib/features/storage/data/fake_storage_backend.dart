import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../domain/storage_backend.dart';
import '../domain/storage_models.dart';

/// In-memory mock storage backend for hermetic unit and integration testing.
///
/// Features:
/// - Simulates Telegram auth state machine (Phone -> Code -> 2FA -> Authenticated).
/// - Simulates private channel creation, document uploads, downloads, and message pinning.
/// - Allows injecting errors: simulated flood-wait, network drops, or auth failures.
class FakeStorageBackend implements StorageBackend {
  final _uuid = const Uuid();

  StorageAuthStep _currentStep = StorageAuthStep.unauthenticated;
  String? _phoneNumber;
  String? _expectedCode = '12345';
  String? _expectedPassword = 'correct_password';
  bool require2FA = false;

  // Fault injection controls
  Duration? simulatedLatency;
  int? simulatedFloodWaitSeconds;
  bool shouldFailUpload = false;
  bool shouldFailDownload = false;

  // Stored state: channelId -> list of messages
  final Map<String, List<RemoteMessage>> _channelMessages = {};
  final Map<String, String?> _pinnedMessages = {};
  // remoteFileId -> file bytes
  final Map<String, Uint8List> _fileStore = {};

  final StreamController<StorageAuthState> _authStateController =
      StreamController<StorageAuthState>.broadcast();

  String? profilePhotoPath;
  String? displayName = 'Test User';
  String? testUsername = 'testuser';

  @override
  Stream<StorageAuthState>? get authStateStream => _authStateController.stream;

  @override
  Future<void> initialize() async {
    await _applyLatency();
  }

  @override
  Future<StorageAuthState> checkAuth() async {
    await _applyLatency();
    return StorageAuthState(
      step: _currentStep,
      phoneNumber: _phoneNumber,
      userId: _currentStep == StorageAuthStep.authenticated ? '123456789' : null,
      userName: _currentStep == StorageAuthStep.authenticated ? (testUsername ?? 'testuser') : null,
      displayName: _currentStep == StorageAuthStep.authenticated ? displayName : null,
      profilePhotoPath: _currentStep == StorageAuthStep.authenticated ? profilePhotoPath : null,
    );
  }

  @override
  Future<StorageAuthState> sendCode(String phoneNumber) async {
    await _applyLatency();
    _checkFloodWait();
    _phoneNumber = phoneNumber;
    _currentStep = StorageAuthStep.waitingForCode;
    return StorageAuthState(
      step: _currentStep,
      phoneNumber: _phoneNumber,
    );
  }

  @override
  Future<StorageAuthState> signInWithCode(String code) async {
    await _applyLatency();
    _checkFloodWait();

    if (code != _expectedCode && code != '123456') {
      return StorageAuthState(
        step: _currentStep,
        phoneNumber: _phoneNumber,
        error: 'Invalid verification code',
      );
    }

    if (require2FA) {
      _currentStep = StorageAuthStep.waitingForPassword;
    } else {
      _currentStep = StorageAuthStep.authenticated;
    }

    final result = StorageAuthState(
      step: _currentStep,
      phoneNumber: _phoneNumber,
      userId: _currentStep == StorageAuthStep.authenticated ? '123456789' : null,
      userName: _currentStep == StorageAuthStep.authenticated ? (testUsername ?? 'testuser') : null,
      displayName: _currentStep == StorageAuthStep.authenticated ? displayName : null,
      profilePhotoPath: _currentStep == StorageAuthStep.authenticated ? profilePhotoPath : null,
    );
    _authStateController.add(result);
    return result;
  }

  @override
  Future<StorageAuthState> checkPassword(String password) async {
    await _applyLatency();
    _checkFloodWait();

    if (password != _expectedPassword) {
      return StorageAuthState(
        step: _currentStep,
        phoneNumber: _phoneNumber,
        error: 'Incorrect two-factor authentication password',
      );
    }

    _currentStep = StorageAuthStep.authenticated;
    final result = StorageAuthState(
      step: _currentStep,
      phoneNumber: _phoneNumber,
      userId: '123456789',
      userName: testUsername ?? 'testuser',
      displayName: displayName,
      profilePhotoPath: profilePhotoPath,
    );
    _authStateController.add(result);
    return result;
  }

  @override
  Future<void> signOut() async {
    await _applyLatency();
    _currentStep = StorageAuthStep.unauthenticated;
    _phoneNumber = null;
    _authStateController.add(const StorageAuthState(step: StorageAuthStep.unauthenticated));
  }

  @override
  Stream<String>? get qrLinkStream => null;

  @override
  Future<String?> requestQrCode() async => 'tg://login?token=FAKE_STORAGE_QR_TOKEN';

  @override
  Future<VaultChannelInfo> getOrCreateVaultChannel(String channelTitle) async {
    await _applyLatency();
    _checkFloodWait();

    // Map channel title to distinct deterministic channel IDs (e.g. 'filo enc' vs 'filo view')
    final channelId = channelTitle.contains('view')
        ? '-1009876543211'
        : '-1009876543210';
    _channelMessages.putIfAbsent(channelId, () => []);

    return VaultChannelInfo(
      channelId: channelId,
      title: channelTitle,
      totalMessages: _channelMessages[channelId]!.length,
      pinnedMessageId: _pinnedMessages[channelId],
    );
  }

  @override
  Future<RemoteUploadedChunk> uploadChunk({
    required String channelId,
    required Uint8List chunkData,
    required String partFileName,
    File? sourceFile,
    ProgressCallback? onProgress,
  }) async {
    await _applyLatency();
    _checkFloodWait();

    if (shouldFailUpload) {
      throw Exception('Simulated network interruption during chunk upload');
    }

    final effectiveData = (chunkData.isEmpty && sourceFile != null && await sourceFile.exists())
        ? await sourceFile.readAsBytes()
        : chunkData;

    // Simulate progressive streaming progress
    if (onProgress != null) {
      final total = effectiveData.length;
      final step = (total ~/ 4).clamp(1, total);
      for (int i = step; i < total; i += step) {
        onProgress(i, total);
      }
      onProgress(total, total);
    }

    final messageId = _uuid.v4();
    final remoteFileId = 'file_${_uuid.v4()}';

    _fileStore[remoteFileId] = effectiveData;

    final message = RemoteMessage(
      messageId: messageId,
      remoteFileId: remoteFileId,
      documentData: effectiveData,
      caption: partFileName,
      date: DateTime.now(),
    );

    _channelMessages.putIfAbsent(channelId, () => []).add(message);

    return RemoteUploadedChunk(
      messageId: messageId,
      remoteFileId: remoteFileId,
      sizeBytes: effectiveData.length,
      partFileName: partFileName,
    );
  }

  @override
  Future<Uint8List> downloadChunk({
    required String channelId,
    required String remoteFileId,
    ProgressCallback? onProgress,
  }) async {
    await _applyLatency();
    _checkFloodWait();

    if (shouldFailDownload) {
      throw Exception('Simulated network interruption during chunk download');
    }

    final data = _fileStore[remoteFileId];
    if (data == null) {
      throw Exception('Remote chunk not found: fileId=$remoteFileId');
    }

    if (onProgress != null) {
      final total = data.length;
      final step = (total ~/ 4).clamp(1, total);
      for (int i = step; i < total; i += step) {
        onProgress(i, total);
      }
      onProgress(total, total);
    }

    return Uint8List.fromList(data);
  }

  @override
  Future<void> downloadChunkToFile({
    required String channelId,
    required String remoteFileId,
    required File destinationFile,
    ProgressCallback? onProgress,
    bool deleteRemoteCache = false,
  }) async {
    await _applyLatency();
    _checkFloodWait();

    if (shouldFailDownload) {
      throw Exception('Simulated network interruption during chunk download');
    }

    final data = _fileStore[remoteFileId];
    if (data == null) {
      throw Exception('Remote chunk not found: fileId=$remoteFileId');
    }

    if (!destinationFile.parent.existsSync()) {
      destinationFile.parent.createSync(recursive: true);
    }

    final total = data.length;
    const sliceSize = 64 * 1024;
    final sink = destinationFile.openWrite();
    var sinkClosed = false;
    try {
      if (total == 0) {
        onProgress?.call(0, 0);
      } else {
        int offset = 0;
        while (offset < total) {
          final end = (offset + sliceSize < total) ? offset + sliceSize : total;
          sink.add(Uint8List.sublistView(data, offset, end));
          offset = end;
          onProgress?.call(offset, total);
        }
      }
      await sink.flush();
      await sink.close();
      sinkClosed = true;
    } catch (_) {
      if (!sinkClosed) {
        try {
          await sink.close();
        } catch (_) {}
      }
      if (destinationFile.existsSync()) {
        try {
          destinationFile.deleteSync();
        } catch (_) {}
      }
      rethrow;
    }
  }

  @override
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) async {
    await _applyLatency();
    final messages = _channelMessages[channelId];
    if (messages != null) {
      final removed = messages.firstWhere((m) => m.messageId == messageId, orElse: () => messages.first);
      if (removed.remoteFileId != null) {
        _fileStore.remove(removed.remoteFileId);
      }
      messages.removeWhere((m) => m.messageId == messageId);
    }
  }

  @override
  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  }) async {
    await _applyLatency();
    _pinnedMessages[channelId] = messageId;
  }

  @override
  Future<RemoteMessage?> getPinnedMessage({
    required String channelId,
  }) async {
    await _applyLatency();
    final pinnedId = _pinnedMessages[channelId];
    if (pinnedId == null) return null;

    final messages = _channelMessages[channelId];
    if (messages == null) return null;

    try {
      return messages.firstWhere((m) => m.messageId == pinnedId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> wipeChannel({
    required String channelId,
  }) async {
    await _applyLatency();
    final count = _channelMessages[channelId]?.length ?? 0;
    _channelMessages[channelId]?.clear();
    _pinnedMessages.remove(channelId);
    return count;
  }

  @override
  Future<StorageQuotaInfo> getStorageQuota() async {
    return const StorageQuotaInfo(
      totalBytes: -1,
      usedBytes: 1048576 * 45,
      planName: 'Unlimited',
      providerName: 'Telegram',
    );
  }

  @override
  Future<void> dispose() async {
    if (!_authStateController.isClosed) {
      await _authStateController.close();
    }
  }

  Future<void> _applyLatency() async {
    if (simulatedLatency != null) {
      await Future<void>.delayed(simulatedLatency!);
    }
  }

  void _checkFloodWait() {
    if (simulatedFloodWaitSeconds != null && simulatedFloodWaitSeconds! > 0) {
      final wait = simulatedFloodWaitSeconds!;
      simulatedFloodWaitSeconds = null; // Clear after trigger
      throw Exception('FLOOD_WAIT_$wait: Too Many Requests. Retry after $wait seconds');
    }
  }

  // Testing helpers
  void setExpectedCode(String code) => _expectedCode = code;
  void setExpectedPassword(String password) => _expectedPassword = password;
  void setAuthenticated() => _currentStep = StorageAuthStep.authenticated;
}
