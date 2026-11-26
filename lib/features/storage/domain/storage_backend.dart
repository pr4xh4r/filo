import 'dart:io';
import 'dart:typed_data';
import 'storage_models.dart';

/// Abstract storage backend contract.
///
/// Principles:
/// - Pluggable backend architecture: MTProto (TDLib) is primary;
///   Bot API ("Bring Your Own Bot") is the fallback.
/// - In-memory FakeStorageBackend enables offline, hermetic unit & integration testing.
abstract class StorageBackend {
  /// Initializes the backend engine (FFI libraries, database directories, etc.).
  Future<void> initialize();

  /// Checks the current authentication status.
  Future<StorageAuthState> checkAuth();

  /// Initiates login by sending an SMS/Telegram code to the given phone number.
  Future<StorageAuthState> sendCode(String phoneNumber);

  /// Submits the received verification code.
  Future<StorageAuthState> signInWithCode(String code);

  /// Submits the 2FA cloud password if the user has two-factor authentication enabled.
  Future<StorageAuthState> checkPassword(String password);

  /// Signs out of the Telegram session.
  Future<void> signOut();

  /// Locates or creates the user's private storage channel (e.g. "[APP_NAME] Vault").
  Future<VaultChannelInfo> getOrCreateVaultChannel(String channelTitle);

  /// Stream of QR code login links emitted during QR authentication (e.g. tg://login?token=...).
  Stream<String>? get qrLinkStream => null;

  /// Requests QR code authentication. Returns initial link if immediately available.
  Future<String?> requestQrCode() async => null;

  /// Uploads an encrypted chunk blob or direct single-file payload to the vault channel.
  Future<RemoteUploadedChunk> uploadChunk({
    required String channelId,
    required Uint8List chunkData,
    required String partFileName,
    File? sourceFile,
    ProgressCallback? onProgress,
  });

  /// Downloads an encrypted chunk blob from the vault channel.
  Future<Uint8List> downloadChunk({
    required String channelId,
    required String remoteFileId,
    ProgressCallback? onProgress,
  });

  /// Deletes a specific message in the vault channel.
  Future<void> deleteMessage({
    required String channelId,
    required String messageId,
  });

  /// Pins a message in the vault channel (used for index snapshots).
  Future<void> pinMessage({
    required String channelId,
    required String messageId,
  });

  /// Fetches the currently pinned message in the vault channel, if any.
  Future<RemoteMessage?> getPinnedMessage({
    required String channelId,
  });

  /// Purges all messages in the vault channel (GDPR "Delete all data").
  Future<int> wipeChannel({
    required String channelId,
  });

  /// Fetches storage quota information (e.g. Unlimited Telegram cloud).
  Future<StorageQuotaInfo> getStorageQuota();

  /// Disposes of any open client sessions and resources.
  Future<void> dispose();
}
