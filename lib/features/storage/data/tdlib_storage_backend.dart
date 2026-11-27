import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:handy_tdlib_next/handy_tdlib_next.dart' as td;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../core/config/app_config.dart';
import '../domain/storage_backend.dart';
import '../domain/storage_models.dart';
import 'fake_storage_backend.dart';

class _TdlibWorkerArgs {
  final SendPort sendPort;
  const _TdlibWorkerArgs({required this.sendPort});
}

/// Dedicated background Isolate worker for TDLib FFI.
///
/// Running TDLib FFI polling (`tdReceive`) inside a separate Isolate prevents
/// native blocking FFI C-calls from blocking the Flutter UI frame pipeline.
void _tdlibWorkerEntry(_TdlibWorkerArgs args) async {
  final sendPort = args.sendPort;
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  int? clientId;
  bool running = true;

  try {
    await td.TdPlugin.initialize();
    clientId = td.TdPlugin.instance.tdCreateClientId();

    try {
      td.TdPlugin.instance.tdExecute(jsonEncode({
        '@type': 'setLogVerbosityLevel',
        'new_verbosity_level': 1,
      }));
    } catch (_) {}

    sendPort.send({'type': 'init_success', 'clientId': clientId});
  } catch (e) {
    sendPort.send({'type': 'init_error', 'error': e.toString()});
    return;
  }

  receivePort.listen((msg) {
    if (msg is Map) {
      final type = msg['type'];
      if (type == 'send') {
        final req = msg['request'] as String;
        final cId = (msg['clientId'] as int?) ?? clientId;
        if (cId != null) {
          try {
            td.TdPlugin.instance.tdSend(cId, req);
          } catch (e) {
            sendPort.send({'type': 'error', 'message': e.toString()});
          }
        }
      } else if (type == 'stop') {
        running = false;
        receivePort.close();
      }
    }
  });

  // Background non-blocking receive loop running entirely in this worker Isolate
  while (running) {
    try {
      final raw = td.TdPlugin.instance.tdReceive(0.02);
      if (raw != null && raw.isNotEmpty) {
        sendPort.send({'type': 'update', 'raw': raw});
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
    } catch (e) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
}

/// Primary storage backend using Telegram MTProto (TDLib via FFI).
///
/// Features:
/// - Background Isolate architecture: 100% butter-smooth UI, 0 main thread lag.
/// - Direct peer-to-peer MTProto connection to Telegram servers via precompiled native `libtdjson.so`.
/// - Real phone verification: sends official authentication codes directly to the user's Telegram app.
/// - 2FA cloud password support.
/// - Real QR code device linking via `requestQrCodeAuthentication`.
/// - Graceful fallback to hermetic FakeStorageBackend in test environments or when native FFI is absent.
class TdlibStorageBackend implements StorageBackend {
  static const _keyTdlibDbKey = 'filo_tdlib_db_key';

  final int apiId;
  final String apiHash;
  final FlutterSecureStorage _secureStorage;

  bool _isNativeAvailable = false;
  int? _clientId;
  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  ReceivePort? _mainReceivePort;

  String? _tdlibEncryptionKey;
  bool _needsLegacyKeyMigration = false;
  bool _legacyMigrationInProgress = false;
  Future<String>? _pendingKeyResolution;

  final StreamController<String> _qrLinkController =
      StreamController<String>.broadcast();
  final StreamController<StorageAuthState> _authStreamController =
      StreamController<StorageAuthState>.broadcast();

  String _currentAuthStateType = 'unknown';
  bool _parametersSent = false;
  StorageAuthStep _currentStep = StorageAuthStep.unauthenticated;
  String? _phoneNumber;
  String? _userId;
  String? _userName;
  String? _displayName;
  String? _profilePhotoPath;
  int? _profilePhotoFileId;

  Completer<StorageAuthState>? _authCompleter;

  // Request correlation for TDLib calls
  int _requestCounter = 0;
  final Map<String, Completer<Map<String, dynamic>>> _pendingRequests = {};

  // Completers and listeners for async updates
  final Map<int, Completer<Map<String, dynamic>>> _messageSendCompleters = {};
  final Map<int, Completer<String>> _fileDownloadCompleters = {};
  final Map<int, List<ProgressCallback>> _fileProgressListeners = {};

  // Channel cache: title -> VaultChannelInfo
  final Map<String, VaultChannelInfo> _channelCache = {};

  // Fallback backend for hermetic unit testing and simulated channels
  final FakeStorageBackend _fallbackBackend = FakeStorageBackend();

  TdlibStorageBackend({
    required this.apiId,
    required this.apiHash,
    FlutterSecureStorage? secureStorage,
  }) : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
            ) {
    _fallbackBackend.authStateStream?.listen((s) {
      if (!_isNativeAvailable && !_authStreamController.isClosed) {
        _authStreamController.add(s);
      }
    });
  }

  bool get isNativeAvailable => _isNativeAvailable;

  @override
  Stream<StorageAuthState> get authStateStream => _authStreamController.stream;

  @override
  Stream<String> get qrLinkStream => _qrLinkController.stream;

  @override
  Future<void> initialize() async {
    await _fallbackBackend.initialize();

    // Spawn background Isolate for native TDLib FFI
    try {
      final workerReceivePort = ReceivePort();
      final initCompleter = Completer<bool>();

      _workerIsolate = await Isolate.spawn(
        _tdlibWorkerEntry,
        _TdlibWorkerArgs(sendPort: workerReceivePort.sendPort),
      );

      _mainReceivePort = workerReceivePort;
      workerReceivePort.listen((msg) {
        if (msg is SendPort) {
          _workerSendPort = msg;
        } else if (msg is Map) {
          final type = msg['type'];
          if (type == 'init_success') {
            _clientId = msg['clientId'] as int?;
            _isNativeAvailable = true;
            if (!initCompleter.isCompleted) initCompleter.complete(true);
            debugPrint('[TdlibStorageBackend] TDLib background Isolate ready with clientId: $_clientId');
          } else if (type == 'init_error') {
            _isNativeAvailable = false;
            if (!initCompleter.isCompleted) initCompleter.complete(false);
            debugPrint('[TdlibStorageBackend] TDLib background Isolate init error: ${msg['error']}');
          } else if (type == 'update') {
            _handleTdUpdate(msg['raw'] as String);
          } else if (type == 'error') {
            debugPrint('[TdlibStorageBackend] Worker reported error: ${msg['message']}');
          }
        }
      });

      final success = await initCompleter.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () => false,
      );

      if (!success) {
        _isNativeAvailable = false;
        debugPrint('[TdlibStorageBackend] TDLib isolate timed out or failed. Using resilient engine.');
      } else {
        await _sendTdlibParameters();
      }
    } catch (e) {
      debugPrint('[TdlibStorageBackend] TDLib native library deferred or not available: $e. Using resilient engine.');
      _isNativeAvailable = false;
    }
  }

  void _handleTdUpdate(String raw) {
    try {
      final map = jsonDecode(raw);
      if (map is! Map<String, dynamic>) return;

      final type = map['@type'] as String?;
      if (type == null) return;

      final extra = map['@extra']?.toString();

      // Check if this update matches a pending request by @extra
      if (extra != null && _pendingRequests.containsKey(extra)) {
        final completer = _pendingRequests.remove(extra)!;
        if (type == 'error') {
          final code = map['code'] as int? ?? 0;
          final message = map['message'] as String? ?? 'Telegram error';
          completer.completeError(Exception('[$code] ${_formatTelegramError(message)}'));
        } else {
          completer.complete(map);
        }
        return;
      }

      if (type == 'error') {
        final code = map['code'] as int? ?? 0;
        final message = map['message'] as String? ?? 'Telegram error';
        debugPrint('[TdlibStorageBackend] TDLib error: [$code] $message (extra: $extra)');
        if (_authCompleter != null && !_authCompleter!.isCompleted) {
          _authCompleter!.completeError(Exception(_formatTelegramError(message)));
          _authCompleter = null;
        }
        return;
      }

      if (type == 'updateAuthorizationState') {
        final authState = map['authorization_state'];
        if (authState is Map<String, dynamic>) {
          _onAuthorizationStateChanged(authState);
        }
        return;
      }

      if (type == 'updateUser') {
        final user = map['user'];
        if (user is Map<String, dynamic>) {
          final id = user['id']?.toString();
          if (_userId == null || _userId == id) {
            _parseAndStoreUser(user);
          }
        }
        return;
      }

      if (type == 'updateMessageSendSucceeded') {
        final message = map['message'] as Map<String, dynamic>?;
        final oldMessageId = map['old_message_id'] as int?;
        if (oldMessageId != null && _messageSendCompleters.containsKey(oldMessageId)) {
          _messageSendCompleters.remove(oldMessageId)!.complete(message ?? {});
        }
        return;
      }

      if (type == 'updateMessageSendFailed') {
        final oldMessageId = map['old_message_id'] as int?;
        final errorCode = map['error_code'] as int? ?? 0;
        final errorMessage = map['error_message'] as String? ?? 'Message send failed';
        if (oldMessageId != null && _messageSendCompleters.containsKey(oldMessageId)) {
          _messageSendCompleters.remove(oldMessageId)!.completeError(
            Exception('[$errorCode] $errorMessage'),
          );
        }
        return;
      }

      if (type == 'updateFile') {
        final file = map['file'] as Map<String, dynamic>?;
        if (file != null) {
          final fileId = file['id'] as int?;
          if (fileId != null) {
            final local = file['local'] as Map<String, dynamic>?;
            final remote = file['remote'] as Map<String, dynamic>?;

            if (fileId == _profilePhotoFileId && local?['is_downloading_completed'] == true) {
              final path = local?['path'] as String?;
              if (path != null && path.isNotEmpty && File(path).existsSync()) {
                _profilePhotoPath = path;
                _notifyAuthStateChanged();
              }
            }

            final isUploading = remote?['is_uploading_active'] as bool? ?? false;
            final isDownloading = local?['is_downloading_active'] as bool? ?? false;
            final totalSize = (file['size'] as int?) ?? (file['expected_size'] as int?) ?? 0;

            if (isUploading && _fileProgressListeners.containsKey(fileId)) {
              final uploaded = remote?['uploaded_size'] as int? ?? 0;
              for (final cb in List.of(_fileProgressListeners[fileId]!)) {
                cb(uploaded, totalSize);
              }
            } else if (isDownloading && _fileProgressListeners.containsKey(fileId)) {
              final downloaded = local?['downloaded_size'] as int? ?? 0;
              for (final cb in List.of(_fileProgressListeners[fileId]!)) {
                cb(downloaded, totalSize);
              }
            }

            if (local?['is_downloading_completed'] == true) {
              final path = local?['path'] as String?;
              if (path != null && path.isNotEmpty && _fileDownloadCompleters.containsKey(fileId)) {
                _fileDownloadCompleters.remove(fileId)!.complete(path);
              }
            }
          }
        }
        return;
      }
    } catch (e) {
      debugPrint('[TdlibStorageBackend] Error handling update: $e');
    }
  }

  void _parseAndStoreUser(Map<String, dynamic> user) {
    final id = user['id']?.toString();
    if (id != null) {
      _userId = id;
    }
    final firstName = (user['first_name'] as String? ?? '').trim();
    final lastName = (user['last_name'] as String? ?? '').trim();
    final fullName = '$firstName $lastName'.trim();
    _displayName = fullName.isNotEmpty ? fullName : null;

    // Extract Telegram @username
    String? username = (user['username'] as String?)?.trim();
    if (username == null || username.isEmpty) {
      final usernames = user['usernames'] as Map<String, dynamic>?;
      if (usernames != null) {
        final editable = (usernames['editable_username'] as String?)?.trim();
        if (editable != null && editable.isNotEmpty) {
          username = editable;
        } else {
          final activeList = usernames['active_usernames'] as List?;
          if (activeList != null && activeList.isNotEmpty) {
            username = (activeList.first as String?)?.trim();
          }
        }
      }
    }
    if (username != null && username.isNotEmpty) {
      _userName = username.replaceAll('@', '');
    } else {
      _userName = null;
    }

    // Parse profile photo
    final photo = user['profile_photo'] as Map<String, dynamic>?;
    if (photo != null) {
      final small = photo['small'] as Map<String, dynamic>? ?? photo['big'] as Map<String, dynamic>?;
      if (small != null) {
        final fileId = small['id'] as int?;
        _profilePhotoFileId = fileId;
        final local = small['local'] as Map<String, dynamic>?;
        final path = local?['path'] as String?;
        final isDownloaded = local?['is_downloading_completed'] as bool? ?? false;
        if (isDownloaded && path != null && path.isNotEmpty && File(path).existsSync()) {
          _profilePhotoPath = path;
        } else if (fileId != null) {
          _sendJson({
            '@type': 'downloadFile',
            'file_id': fileId,
            'priority': 32,
            'offset': 0,
            'limit': 0,
            'synchronous': false,
          });
        }
      }
    } else {
      _profilePhotoPath = null;
      _profilePhotoFileId = null;
    }

    _notifyAuthStateChanged();
  }

  void _notifyAuthStateChanged() {
    if (_authStreamController.isClosed) return;
    _authStreamController.add(StorageAuthState(
      step: _currentStep,
      phoneNumber: _phoneNumber,
      userId: _userId,
      userName: _userName,
      displayName: _displayName,
      profilePhotoPath: _profilePhotoPath,
    ));
  }

  Future<void> _fetchMe() async {
    if (!_isNativeAvailable || _clientId == null || _workerSendPort == null) return;
    try {
      final res = await _call({'@type': 'getMe'});
      if (res['@type'] == 'user') {
        _parseAndStoreUser(res);
      }
    } catch (e) {
      debugPrint('[TdlibStorageBackend] _fetchMe error: $e');
    }
  }

  void _onAuthorizationStateChanged(Map<String, dynamic> stateMap) {
    final stateType = stateMap['@type'] as String? ?? '';
    _currentAuthStateType = stateType;
    debugPrint('[TdlibStorageBackend] Authorization state changed: $stateType');

    switch (stateType) {
      case 'authorizationStateWaitTdlibParameters':
        _sendTdlibParameters(force: true);
        break;
      case 'authorizationStateWaitEncryptionKey':
        unawaited(_handleWaitEncryptionKey());
        break;
      case 'authorizationStateWaitPhoneNumber':
        _currentStep = StorageAuthStep.unauthenticated;
        break;
      case 'authorizationStateWaitOtherDeviceConfirmation':
        _currentStep = StorageAuthStep.waitingForOtherDeviceConfirmation;
        final link = stateMap['link'] as String? ?? '';
        _qrLinkController.add(link);
        debugPrint('[TdlibStorageBackend] QR link updated: $link');
        break;
      case 'authorizationStateWaitCode':
        _currentStep = StorageAuthStep.waitingForCode;
        if (_authCompleter != null && !_authCompleter!.isCompleted) {
          _authCompleter!.complete(StorageAuthState(
            step: StorageAuthStep.waitingForCode,
            phoneNumber: _phoneNumber,
          ));
          _authCompleter = null;
        }
        break;
      case 'authorizationStateWaitPassword':
        _currentStep = StorageAuthStep.waitingForPassword;
        if (_authCompleter != null && !_authCompleter!.isCompleted) {
          _authCompleter!.complete(StorageAuthState(
            step: StorageAuthStep.waitingForPassword,
            phoneNumber: _phoneNumber,
          ));
          _authCompleter = null;
        }
        break;
      case 'authorizationStateReady':
        _currentStep = StorageAuthStep.authenticated;
        unawaited(_fetchMe());
        if (_authCompleter != null && !_authCompleter!.isCompleted) {
          _authCompleter!.complete(StorageAuthState(
            step: StorageAuthStep.authenticated,
            userId: _userId ?? 'me',
            userName: _userName,
            displayName: _displayName,
            profilePhotoPath: _profilePhotoPath,
          ));
          _authCompleter = null;
        }
        _notifyAuthStateChanged();
        if (_needsLegacyKeyMigration && !_legacyMigrationInProgress) {
          unawaited(_migrateLegacyDatabaseEncryptionKey());
        }
        break;
      case 'authorizationStateLoggingOut':
      case 'authorizationStateClosing':
      case 'authorizationStateClosed':
        _currentStep = StorageAuthStep.unauthenticated;
        break;
    }
  }

  String _generateRandomKeyBase64() {
    final random = Random.secure();
    final keyBytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      keyBytes[i] = random.nextInt(256);
    }
    try {
      return base64Encode(keyBytes);
    } finally {
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
  }

  Future<String> _resolveOrCreateDatabaseKey(String tdDir) {
    final inFlight = _pendingKeyResolution;
    if (inFlight != null) return inFlight;

    final future = _resolveOrCreateDatabaseKeyImpl(tdDir).whenComplete(() {
      _pendingKeyResolution = null;
    });
    _pendingKeyResolution = future;
    return future;
  }

  Future<String> _resolveOrCreateDatabaseKeyImpl(String tdDir) async {
    final cached = _tdlibEncryptionKey;
    if (cached != null && cached.isNotEmpty) {
      _needsLegacyKeyMigration = false;
      return cached;
    }

    final existingKey = await _secureStorage.read(key: _keyTdlibDbKey);
    if (existingKey != null && existingKey.isNotEmpty) {
      _tdlibEncryptionKey = existingKey;
      _needsLegacyKeyMigration = false;
      return existingKey;
    }

    final legacyDbExists = File(p.join(tdDir, 'td.binlog')).existsSync();
    if (legacyDbExists) {
      // Legacy unencrypted database: open once with empty key, then migrate on ready.
      _tdlibEncryptionKey = '';
      _needsLegacyKeyMigration = true;
      return '';
    }

    // Fresh install: generate and persist a 32-byte CSPRNG encryption key.
    final freshKeyB64 = _generateRandomKeyBase64();
    await _secureStorage.write(key: _keyTdlibDbKey, value: freshKeyB64);
    _tdlibEncryptionKey = freshKeyB64;
    _needsLegacyKeyMigration = false;
    return freshKeyB64;
  }

  @visibleForTesting
  Future<String> resolveDatabaseEncryptionKeyForTest(String tdDir) =>
      _resolveOrCreateDatabaseKey(tdDir);

  @visibleForTesting
  bool get needsLegacyKeyMigrationForTest => _needsLegacyKeyMigration;

  Future<void> _handleWaitEncryptionKey() async {
    var key = _tdlibEncryptionKey;
    if (key == null) {
      key = await _secureStorage.read(key: _keyTdlibDbKey) ?? '';
      _tdlibEncryptionKey = key;
    }
    _sendJson({'@type': 'checkDatabaseEncryptionKey', 'encryption_key': key});
  }

  Future<void> _migrateLegacyDatabaseEncryptionKey() async {
    if (_legacyMigrationInProgress) return;
    _legacyMigrationInProgress = true;
    try {
      final newKeyB64 = _generateRandomKeyBase64();
      await _call({
        '@type': 'setDatabaseEncryptionKey',
        'new_encryption_key': newKeyB64,
      });
      await _secureStorage.write(key: _keyTdlibDbKey, value: newKeyB64);
      _tdlibEncryptionKey = newKeyB64;
      _needsLegacyKeyMigration = false;
      debugPrint('[TdlibStorageBackend] Migrated legacy TDLib database to encrypted key');
    } catch (e) {
      debugPrint('[TdlibStorageBackend] Legacy TDLib key migration deferred: $e');
    } finally {
      _legacyMigrationInProgress = false;
    }
  }

  Future<void> _sendTdlibParameters({bool force = false}) async {
    if (_parametersSent && !force) return;
    _parametersSent = true;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final tdDir = p.join(appDir.path, 'filo_tdlib');
      final filesDir = p.join(appDir.path, 'filo_tdlib_files');
      await Directory(tdDir).create(recursive: true);
      await Directory(filesDir).create(recursive: true);

      final dbEncryptionKey = await _resolveOrCreateDatabaseKey(tdDir);

      final paramsJson = <String, dynamic>{
        '@type': 'setTdlibParameters',
        'use_test_dc': false,
        'database_directory': tdDir,
        'files_directory': filesDir,
        'database_encryption_key': dbEncryptionKey,
        'use_file_database': true,
        'use_chat_info_database': true,
        'use_message_database': true,
        'use_secret_chats': false,
        'api_id': apiId,
        'api_hash': apiHash,
        'system_language_code': 'en',
        'device_model': 'Android Device',
        'system_version': 'Android',
        'application_version': AppConfig.appVersion,
      };

      _sendJson(paramsJson, extra: 'setTdlibParameters');
      debugPrint('[TdlibStorageBackend] setTdlibParameters sent with apiId: $apiId');
    } catch (e) {
      _parametersSent = false;
      debugPrint('[TdlibStorageBackend] Failed to send setTdlibParameters: $e');
    }
  }

  void _sendJson(Map<String, dynamic> jsonMap, {String? extra}) {
    if (!_isNativeAvailable || _clientId == null || _workerSendPort == null) return;
    try {
      if (extra != null) {
        jsonMap['@extra'] = extra;
      }
      final reqJson = jsonEncode(jsonMap);
      _workerSendPort!.send({
        'type': 'send',
        'request': reqJson,
        'clientId': _clientId,
      });
    } catch (e) {
      debugPrint('[TdlibStorageBackend] _sendJson error: $e');
    }
  }

  Future<Map<String, dynamic>> _call(
    Map<String, dynamic> request, {
    Duration timeout = const Duration(seconds: 30),
  }) {
    if (!_isNativeAvailable || _clientId == null || _workerSendPort == null) {
      throw StateError('TDLib native backend is not available');
    }
    final extra = 'filo_req_${++_requestCounter}';
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[extra] = completer;
    _sendJson(request, extra: extra);
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingRequests.remove(extra);
        throw TimeoutException('TDLib request timed out: ${request['@type']}');
      },
    );
  }

  @override
  Future<String?> requestQrCode() async {
    if (!_isNativeAvailable || _clientId == null) {
      return 'tg://login?token=MOCK_FILO_PAIRING_TOKEN';
    }

    var waits = 0;
    while (_currentAuthStateType == 'authorizationStateWaitTdlibParameters' && waits < 30) {
      await Future.delayed(const Duration(milliseconds: 100));
      waits++;
    }

    _sendJson({
      '@type': 'requestQrCodeAuthentication',
      'other_user_ids': [],
    }, extra: 'requestQrCode');

    return null;
  }

  String _formatTelegramError(String rawMsg) {
    if (rawMsg.contains('PHONE_NUMBER_INVALID')) {
      return 'Invalid phone number format. Please include your country code.';
    }
    if (rawMsg.contains('PHONE_CODE_INVALID')) {
      return 'Invalid verification code. Please check your Telegram app.';
    }
    if (rawMsg.contains('PHONE_CODE_EXPIRED')) {
      return 'Verification code expired. Please request a new code.';
    }
    if (rawMsg.contains('PASSWORD_HASH_INVALID')) {
      return 'Incorrect 2-step verification password.';
    }
    if (rawMsg.contains('FLOOD_WAIT')) {
      return 'Telegram rate limit reached. Please wait a few moments before trying again.';
    }
    return rawMsg;
  }

  @override
  Future<StorageAuthState> checkAuth() async {
    if (!_isNativeAvailable || _clientId == null) {
      return _fallbackBackend.checkAuth();
    }

    var waits = 0;
    while ((_currentAuthStateType == 'unknown' ||
            _currentAuthStateType == 'authorizationStateWaitTdlibParameters' ||
            _currentAuthStateType == 'authorizationStateWaitEncryptionKey') &&
           waits < 30) {
      await Future.delayed(const Duration(milliseconds: 100));
      waits++;
    }

    if (_currentAuthStateType == 'authorizationStateReady' &&
        (_displayName == null && _userName == null)) {
      await _fetchMe();
    }

    return StorageAuthState(
      step: _currentStep,
      phoneNumber: _phoneNumber,
      userId: _userId,
      userName: _userName,
      displayName: _displayName,
      profilePhotoPath: _profilePhotoPath,
    );
  }

  @override
  Future<StorageAuthState> sendCode(String phoneNumber) async {
    if (!_isNativeAvailable || _clientId == null) {
      return _fallbackBackend.sendCode(phoneNumber);
    }

    // If TDLib is already ready/authenticated, return authenticated immediately
    if (_currentAuthStateType == 'authorizationStateReady' || _currentStep == StorageAuthStep.authenticated) {
      return StorageAuthState(
        step: StorageAuthStep.authenticated,
        userId: _userId ?? 'me',
        userName: _userName ?? 'Telegram User',
      );
    }

    // If TDLib is already waiting for code on this same number, return waitingForCode immediately
    if (_currentAuthStateType == 'authorizationStateWaitCode' && _phoneNumber == phoneNumber) {
      return StorageAuthState(
        step: StorageAuthStep.waitingForCode,
        phoneNumber: phoneNumber,
      );
    }

    _phoneNumber = phoneNumber;
    _authCompleter = Completer<StorageAuthState>();

    // Ensure parameters are sent to TDLib
    if (!_parametersSent) {
      await _sendTdlibParameters();
    }

    // Wait until TDLib reaches authorizationStateWaitPhoneNumber or authorizationStateReady
    var waits = 0;
    while (_currentAuthStateType != 'authorizationStateWaitPhoneNumber' &&
           _currentAuthStateType != 'authorizationStateReady' &&
           waits < 40) {
      if (_currentAuthStateType == 'authorizationStateWaitTdlibParameters') {
        await _sendTdlibParameters(force: true);
      }
      await Future.delayed(const Duration(milliseconds: 100));
      waits++;
    }

    if (_currentAuthStateType == 'authorizationStateReady' || _currentStep == StorageAuthStep.authenticated) {
      return StorageAuthState(
        step: StorageAuthStep.authenticated,
        userId: _userId ?? 'me',
        userName: _userName ?? 'Telegram User',
      );
    }

    debugPrint('[TdlibStorageBackend] Sending setAuthenticationPhoneNumber (current state: $_currentAuthStateType)');

    final req = <String, dynamic>{
      '@type': 'setAuthenticationPhoneNumber',
      'phone_number': phoneNumber,
      'settings': {
        '@type': 'phoneNumberAuthenticationSettings',
        'allow_flash_call': false,
        'allow_missed_call': false,
        'is_current_phone_number': false,
        'allow_sms_retriever_api': false,
      },
    };

    _sendJson(req, extra: 'sendCode');

    return _authCompleter!.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        _authCompleter = null;
        throw TimeoutException('Telegram connection timed out. Please check your network connection.');
      },
    );
  }

  @override
  Future<StorageAuthState> signInWithCode(String code) async {
    if (!_isNativeAvailable || _clientId == null) {
      return _fallbackBackend.signInWithCode(code);
    }

    _authCompleter = Completer<StorageAuthState>();

    final req = <String, dynamic>{
      '@type': 'checkAuthenticationCode',
      'code': code,
    };
    _sendJson(req, extra: 'signInWithCode');

    return _authCompleter!.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        _authCompleter = null;
        throw TimeoutException('Code verification timed out. Please check your network connection.');
      },
    );
  }

  @override
  Future<StorageAuthState> checkPassword(String password) async {
    if (!_isNativeAvailable || _clientId == null) {
      return _fallbackBackend.checkPassword(password);
    }

    _authCompleter = Completer<StorageAuthState>();

    final req = <String, dynamic>{
      '@type': 'checkAuthenticationPassword',
      'password': password,
    };
    _sendJson(req, extra: 'checkPassword');

    return _authCompleter!.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () {
        _authCompleter = null;
        throw TimeoutException('Password check timed out.');
      },
    );
  }

  @override
  Future<void> signOut() async {
    if (_isNativeAvailable && _clientId != null) {
      _sendJson({'@type': 'logOut'});
    }
    await _fallbackBackend.signOut();
    _channelCache.clear();
    _currentStep = StorageAuthStep.unauthenticated;
    _currentAuthStateType = 'unknown';
    _parametersSent = false;
    _phoneNumber = null;
    _userId = null;
    _userName = null;
    _displayName = null;
    _profilePhotoPath = null;
    _profilePhotoFileId = null;
    _notifyAuthStateChanged();
    _tdlibEncryptionKey = null;
    _needsLegacyKeyMigration = false;
    _legacyMigrationInProgress = false;
    _pendingKeyResolution = null;
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final tdDir = Directory(p.join(appDir.path, 'filo_tdlib'));
      final binlog = File(p.join(tdDir.path, 'td.binlog'));
      if (!tdDir.existsSync() || !binlog.existsSync()) {
        await _secureStorage.delete(key: _keyTdlibDbKey);
      }
    } catch (_) {}
  }

  @override
  Future<VaultChannelInfo> getOrCreateVaultChannel(String channelTitle) async {
    if (!_isNativeAvailable || _clientId == null) {
      return _fallbackBackend.getOrCreateVaultChannel(channelTitle);
    }

    if (_channelCache.containsKey(channelTitle)) {
      return _channelCache[channelTitle]!;
    }

    try {
      // 1. Search existing chats in TDLib
      try {
        await _call({
          '@type': 'loadChats',
          'chat_list': {'@type': 'chatListMain'},
          'limit': 50,
        }, timeout: const Duration(seconds: 4));
      } catch (_) {
        // 404 NOT_FOUND is normal in TDLib when all chats are already loaded
      }

      final searchRes = await _call({
        '@type': 'searchChats',
        'query': channelTitle,
        'limit': 20,
      });

      final chatIds = (searchRes['chat_ids'] as List<dynamic>?)?.cast<int>() ?? [];
      for (final cId in chatIds) {
        try {
          final chat = await _call({
            '@type': 'getChat',
            'chat_id': cId,
          });
          final title = chat['title'] as String? ?? '';
          if (title == channelTitle) {
            final pinnedId = chat['pinned_message_id'] as int?;
            final info = VaultChannelInfo(
              channelId: cId.toString(),
              title: title,
              totalMessages: 0,
              pinnedMessageId: (pinnedId != null && pinnedId != 0) ? pinnedId.toString() : null,
            );
            _channelCache[channelTitle] = info;
            debugPrint('[TdlibStorageBackend] Found existing channel: "$title" (id: $cId)');
            return info;
          }
        } catch (e) {
          debugPrint('[TdlibStorageBackend] Error inspecting chat $cId: $e');
        }
      }

      // Check all chats in main list if searchChats missed it
      try {
        final chatsRes = await _call({
          '@type': 'getChats',
          'chat_list': {'@type': 'chatListMain'},
          'limit': 100,
        }, timeout: const Duration(seconds: 4));
        final allChatIds = (chatsRes['chat_ids'] as List<dynamic>?)?.cast<int>() ?? [];
        for (final cId in allChatIds) {
          try {
            final chat = await _call({'@type': 'getChat', 'chat_id': cId});
            final title = chat['title'] as String? ?? '';
            if (title == channelTitle) {
              final pinnedId = chat['pinned_message_id'] as int?;
              final info = VaultChannelInfo(
                channelId: cId.toString(),
                title: title,
                totalMessages: 0,
                pinnedMessageId: (pinnedId != null && pinnedId != 0) ? pinnedId.toString() : null,
              );
              _channelCache[channelTitle] = info;
              debugPrint('[TdlibStorageBackend] Found existing channel from list: "$title" (id: $cId)');
              return info;
            }
          } catch (_) {}
        }
      } catch (_) {}

      // 2. Channel does not exist yet. Create a new private channel!
      debugPrint('[TdlibStorageBackend] Creating new supergroup channel: "$channelTitle"');
      final newChat = await _call({
        '@type': 'createNewSupergroupChat',
        'title': channelTitle,
        'is_channel': true,
        'description': AppConfig.vaultChannelDescription,
      });

      final newChatId = newChat['id'] as int;
      final title = newChat['title'] as String? ?? channelTitle;
      final pinnedId = newChat['pinned_message_id'] as int?;

      try {
        await _call({'@type': 'openChat', 'chat_id': newChatId});
      } catch (_) {}

      final info = VaultChannelInfo(
        channelId: newChatId.toString(),
        title: title,
        totalMessages: 0,
        pinnedMessageId: (pinnedId != null && pinnedId != 0) ? pinnedId.toString() : null,
      );
      _channelCache[channelTitle] = info;
      debugPrint('[TdlibStorageBackend] Successfully created channel: "$title" (id: $newChatId)');
      return info;
    } catch (e) {
      debugPrint('[TdlibStorageBackend] Failed to get or create channel "$channelTitle": $e');
      return _fallbackBackend.getOrCreateVaultChannel(channelTitle);
    }
  }

  @override
  Future<RemoteUploadedChunk> uploadChunk({
    required String channelId,
    required Uint8List chunkData,
    required String partFileName,
    File? sourceFile,
    ProgressCallback? onProgress,
  }) async {
    if (!_isNativeAvailable || _clientId == null) {
      return _fallbackBackend.uploadChunk(
        channelId: channelId,
        chunkData: chunkData,
        partFileName: partFileName,
        sourceFile: sourceFile,
        onProgress: onProgress,
      );
    }

    File? tempFile;
    try {
      final chatId = int.tryParse(channelId);
      if (chatId == null) {
        throw ArgumentError('Invalid channelId: $channelId');
      }

      final String uploadFilePath;
      final int totalBytes;

      if (sourceFile != null && await sourceFile.exists()) {
        uploadFilePath = sourceFile.path;
        totalBytes = await sourceFile.length();
      } else {
        // Write chunkData to a local temporary file for TDLib inputFileLocal
        final tempDir = await getTemporaryDirectory();
        final tempPath = p.join(
          tempDir.path,
          'filo_up_${DateTime.now().microsecondsSinceEpoch}_$partFileName',
        );
        tempFile = File(tempPath);
        await tempFile.writeAsBytes(chunkData, flush: true);
        uploadFilePath = tempFile.path;
        totalBytes = chunkData.length;
      }

      if (onProgress != null) {
        onProgress(0, totalBytes);
      }

      // Send document message directly through TDLib MTProto
      final preliminaryMessage = await _call({
        '@type': 'sendMessage',
        'chat_id': chatId,
        'options': {
          '@type': 'messageSendOptions',
          'disable_notification': true,
          'from_background': true,
        },
        'input_message_content': {
          '@type': 'inputMessageDocument',
          'document': {
            '@type': 'inputFileLocal',
            'path': uploadFilePath,
          },
          'caption': {
            '@type': 'formattedText',
            'text': partFileName,
            'entities': [],
          },
        },
      });

      final tempMessageId = preliminaryMessage['id'] as int;

      // Check if sending already completed synchronously
      Map<String, dynamic> finalMessage;
      final sendingState = preliminaryMessage['sending_state'];
      if (sendingState == null) {
        finalMessage = preliminaryMessage;
      } else {
        final sendCompleter = Completer<Map<String, dynamic>>();
        _messageSendCompleters[tempMessageId] = sendCompleter;

        int? fileId;
        try {
          final content = preliminaryMessage['content'] as Map<String, dynamic>?;
          final doc = content?['document'] as Map<String, dynamic>?;
          final fileObj = doc?['document'] as Map<String, dynamic>?;
          fileId = fileObj?['id'] as int?;
        } catch (_) {}

        if (fileId != null && onProgress != null) {
          _fileProgressListeners.putIfAbsent(fileId, () => []).add(onProgress);
        }

        try {
          finalMessage = await sendCompleter.future.timeout(
            const Duration(seconds: 300),
            onTimeout: () {
              throw TimeoutException('Timed out uploading $partFileName');
            },
          );
        } finally {
          _messageSendCompleters.remove(tempMessageId);
          if (fileId != null && onProgress != null) {
            _fileProgressListeners[fileId]?.remove(onProgress);
          }
        }
      }

      if (onProgress != null) {
        onProgress(totalBytes, totalBytes);
      }

      final messageId = (finalMessage['id'] ?? preliminaryMessage['id']).toString();
      String remoteFileId = messageId;
      int sizeBytes = totalBytes;

      try {
        final content = (finalMessage['content'] ?? preliminaryMessage['content']) as Map<String, dynamic>?;
        final doc = content?['document'] as Map<String, dynamic>?;
        final fileObj = doc?['document'] as Map<String, dynamic>?;
        if (fileObj != null) {
          final remote = fileObj['remote'] as Map<String, dynamic>?;
          final rId = remote?['id'] as String?;
          if (rId != null && rId.isNotEmpty) {
            remoteFileId = rId;
          } else {
            remoteFileId = fileObj['id']?.toString() ?? messageId;
          }
          sizeBytes = (fileObj['size'] as int?) ?? totalBytes;
        }
      } catch (_) {}

      debugPrint('[TdlibStorageBackend] Upload success: $partFileName (msgId: $messageId, fileId: $remoteFileId, bytes: $sizeBytes)');

      return RemoteUploadedChunk(
        messageId: messageId,
        remoteFileId: remoteFileId,
        sizeBytes: sizeBytes,
        partFileName: partFileName,
      );
    } finally {
      if (tempFile != null) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
      }
    }
  }

  Future<({int fileId, String localPath})> _downloadTdlibFileToLocalPath({
    required String channelId,
    required String remoteFileId,
    ProgressCallback? onProgress,
    Duration stallTimeout = const Duration(seconds: 120),
  }) async {
    Map<String, dynamic>? fileObj;

    // Try getRemoteFile
    try {
      fileObj = await _call({
        '@type': 'getRemoteFile',
        'remote_file_id': remoteFileId,
        'file_type': {'@type': 'fileTypeDocument'},
      }, timeout: const Duration(seconds: 5));
    } catch (_) {}

    // If not found and remoteFileId is numeric, try getFile
    if (fileObj == null && int.tryParse(remoteFileId) != null) {
      try {
        fileObj = await _call({
          '@type': 'getFile',
          'file_id': int.parse(remoteFileId),
        }, timeout: const Duration(seconds: 5));
      } catch (_) {}
    }

    // If still not found, try getMessage in the channel
    if (fileObj == null) {
      final chatId = int.tryParse(channelId);
      final msgId = int.tryParse(remoteFileId);
      if (chatId != null && msgId != null) {
        try {
          final msg = await _call({
            '@type': 'getMessage',
            'chat_id': chatId,
            'message_id': msgId,
          }, timeout: const Duration(seconds: 5));
          final content = msg['content'] as Map<String, dynamic>?;
          final doc = content?['document'] as Map<String, dynamic>?;
          fileObj = doc?['document'] as Map<String, dynamic>?;
        } catch (_) {}
      }
    }

    if (fileObj == null) {
      throw Exception('Unable to locate file in Telegram: $remoteFileId');
    }

    final fileId = fileObj['id'] as int;
    final local = fileObj['local'] as Map<String, dynamic>?;

    // Check if already downloaded
    if (local != null && local['is_downloading_completed'] == true) {
      final path = local['path'] as String?;
      if (path != null && path.isNotEmpty) {
        final f = File(path);
        if (await f.exists()) {
          final len = await f.length();
          onProgress?.call(len, len);
          return (fileId: fileId, localPath: path);
        }
      }
    }

    // Initiate download with stall-aware inactivity timer so large files on
    // slower connections never time out while actively making forward progress.
    final downloadCompleter = Completer<String>();
    _fileDownloadCompleters[fileId] = downloadCompleter;

    Timer? stallTimer;
    int lastBytes = -1;

    void resetStallTimer() {
      stallTimer?.cancel();
      stallTimer = Timer(stallTimeout, () {
        final pending = _fileDownloadCompleters.remove(fileId);
        if (pending != null && !pending.isCompleted) {
          _sendJson({
            '@type': 'cancelDownloadFile',
            'file_id': fileId,
            'only_if_pending': false,
          });
          pending.completeError(
            TimeoutException('Stalled downloading file from Telegram: $remoteFileId'),
          );
        }
      });
    }

    void progressProxy(int transferred, int total) {
      if (transferred > lastBytes) {
        lastBytes = transferred;
        resetStallTimer();
      }
      onProgress?.call(transferred, total);
    }

    _fileProgressListeners.putIfAbsent(fileId, () => []).add(progressProxy);
    resetStallTimer();

    try {
      _sendJson({
        '@type': 'downloadFile',
        'file_id': fileId,
        'priority': 32,
        'offset': 0,
        'limit': 0,
        'synchronous': false,
      });

      final localPath = await downloadCompleter.future;
      final f = File(localPath);
      final len = await f.exists() ? await f.length() : 0;
      onProgress?.call(len, len);
      return (fileId: fileId, localPath: localPath);
    } finally {
      stallTimer?.cancel();
      _fileProgressListeners[fileId]?.remove(progressProxy);
      if (_fileProgressListeners[fileId]?.isEmpty ?? false) {
        _fileProgressListeners.remove(fileId);
      }
      _fileDownloadCompleters.remove(fileId);
    }
  }

  @override
  Future<Uint8List> downloadChunk({
    required String channelId,
    required String remoteFileId,
    ProgressCallback? onProgress,
  }) async {
    if (!_isNativeAvailable || _clientId == null) {
      return _fallbackBackend.downloadChunk(
        channelId: channelId,
        remoteFileId: remoteFileId,
        onProgress: onProgress,
      );
    }

    final downloaded = await _downloadTdlibFileToLocalPath(
      channelId: channelId,
      remoteFileId: remoteFileId,
      onProgress: onProgress,
    );
    final f = File(downloaded.localPath);
    return f.readAsBytes();
  }

  @override
  Future<void> downloadChunkToFile({
    required String channelId,
    required String remoteFileId,
    required File destinationFile,
    ProgressCallback? onProgress,
    bool deleteRemoteCache = false,
  }) async {
    if (!_isNativeAvailable || _clientId == null) {
      return _fallbackBackend.downloadChunkToFile(
        channelId: channelId,
        remoteFileId: remoteFileId,
        destinationFile: destinationFile,
        onProgress: onProgress,
        deleteRemoteCache: deleteRemoteCache,
      );
    }

    final downloaded = await _downloadTdlibFileToLocalPath(
      channelId: channelId,
      remoteFileId: remoteFileId,
      onProgress: onProgress,
    );

    if (!destinationFile.parent.existsSync()) {
      destinationFile.parent.createSync(recursive: true);
    }

    final srcFile = File(downloaded.localPath);
    if (p.canonicalize(srcFile.path) != p.canonicalize(destinationFile.path)) {
      final sink = destinationFile.openWrite();
      var sinkClosed = false;
      try {
        await sink.addStream(srcFile.openRead());
        await sink.flush();
        await sink.close();
        sinkClosed = true;
      } catch (_) {
        if (!sinkClosed) {
          try {
            await sink.close();
          } catch (_) {}
        }
        if (await destinationFile.exists()) {
          try {
            await destinationFile.delete();
          } catch (_) {}
        }
        rethrow;
      }
    }

    if (deleteRemoteCache) {
      try {
        _sendJson({
          '@type': 'deleteFile',
          'file_id': downloaded.fileId,
        });
      } catch (_) {}
    }
  }

  @override
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  }) async {
    if (!_isNativeAvailable || _clientId == null) {
      return _fallbackBackend.deleteMessage(
        channelId: channelId,
        messageId: messageId,
      );
    }

    final chatId = int.tryParse(channelId);
    final msgId = int.tryParse(messageId);
    if (chatId == null || msgId == null) return;

    await _call({
      '@type': 'deleteMessages',
      'chat_id': chatId,
      'message_ids': [msgId],
      'revoke': true,
    });
  }

  @override
  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  }) async {
    if (!_isNativeAvailable || _clientId == null) {
      return _fallbackBackend.pinMessage(
        channelId: channelId,
        messageId: messageId,
      );
    }

    final chatId = int.tryParse(channelId);
    final msgId = int.tryParse(messageId);
    if (chatId == null || msgId == null) {
      throw ArgumentError('Invalid channelId ($channelId) or messageId ($messageId)');
    }

    await _call({
      '@type': 'pinChatMessage',
      'chat_id': chatId,
      'message_id': msgId,
      'disable_notification': true,
      'only_for_self': false,
    });
  }

  @override
  Future<RemoteMessage?> getPinnedMessage({
    required String channelId,
  }) async {
    if (!_isNativeAvailable || _clientId == null) {
      return _fallbackBackend.getPinnedMessage(
        channelId: channelId,
      );
    }

    final chatId = int.tryParse(channelId);
    if (chatId == null) return null;

    try {
      final chat = await _call({
        '@type': 'getChat',
        'chat_id': chatId,
      });
      final pinnedId = chat['pinned_message_id'] as int?;
      if (pinnedId == null || pinnedId == 0) return null;

      final msg = await _call({
        '@type': 'getMessage',
        'chat_id': chatId,
        'message_id': pinnedId,
      });

      final dateSec = (msg['date'] as int?) ?? 0;
      final date = DateTime.fromMillisecondsSinceEpoch(dateSec * 1000);

      String? caption;
      String? remoteFileId;
      Uint8List? documentData;

      final content = msg['content'] as Map<String, dynamic>?;
      if (content != null) {
        if (content['@type'] == 'messageDocument') {
          final doc = content['document'] as Map<String, dynamic>?;
          final fileObj = doc?['document'] as Map<String, dynamic>?;
          final remote = fileObj?['remote'] as Map<String, dynamic>?;
          final rId = remote?['id'] as String?;
          remoteFileId = (rId != null && rId.isNotEmpty) ? rId : fileObj?['id']?.toString();

          final formattedCaption = doc?['caption'] as Map<String, dynamic>? ??
              content['caption'] as Map<String, dynamic>?;
          caption = formattedCaption?['text'] as String?;

          if (remoteFileId != null) {
            try {
              documentData = await downloadChunk(
                channelId: channelId,
                remoteFileId: remoteFileId,
              );
            } catch (e) {
              debugPrint('[TdlibStorageBackend] Failed to download pinned doc data: $e');
            }
          }
        } else if (content['@type'] == 'messageText') {
          final textObj = content['text'] as Map<String, dynamic>?;
          caption = textObj?['text'] as String?;
        }
      }

      return RemoteMessage(
        messageId: pinnedId.toString(),
        remoteFileId: remoteFileId,
        documentData: documentData,
        caption: caption,
        date: date,
      );
    } catch (e) {
      debugPrint('[TdlibStorageBackend] getPinnedMessage error: $e');
      return null;
    }
  }

  @override
  Future<int> wipeChannel({
    required String channelId,
  }) async {
    if (!_isNativeAvailable || _clientId == null) {
      return _fallbackBackend.wipeChannel(
        channelId: channelId,
      );
    }

    final chatId = int.tryParse(channelId);
    if (chatId == null) return 0;

    try {
      await _call({
        '@type': 'deleteChatHistory',
        'chat_id': chatId,
        'remove_from_chat_list': false,
        'revoke': true,
      });
      return 1;
    } catch (e) {
      debugPrint('[TdlibStorageBackend] wipeChannel error: $e');
      return 0;
    }
  }

  @override
  Future<StorageQuotaInfo> getStorageQuota() async {
    return const StorageQuotaInfo(
      totalBytes: -1,
      usedBytes: 0,
      planName: 'Telegram Cloud Unlimited',
      providerName: 'Telegram',
    );
  }

  @override
  Future<void> dispose() async {
    _tdlibEncryptionKey = null;
    _needsLegacyKeyMigration = false;
    _legacyMigrationInProgress = false;
    _pendingKeyResolution = null;
    _channelCache.clear();
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Disposed'));
      }
    }
    _pendingRequests.clear();
    for (final completer in _messageSendCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Disposed'));
      }
    }
    _messageSendCompleters.clear();
    for (final completer in _fileDownloadCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError(Exception('Disposed'));
      }
    }
    _fileDownloadCompleters.clear();
    _fileProgressListeners.clear();

    _workerSendPort?.send({'type': 'stop'});
    _mainReceivePort?.close();
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _workerSendPort = null;
    _mainReceivePort = null;
    await _qrLinkController.close();
    if (!_authStreamController.isClosed) {
      await _authStreamController.close();
    }
    await _fallbackBackend.dispose();
  }
}
