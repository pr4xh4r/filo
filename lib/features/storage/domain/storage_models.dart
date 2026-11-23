import 'dart:typed_data';

/// Authentication state for the storage backend.
enum StorageAuthStep {
  unauthenticated,
  waitingForPhoneNumber,
  waitingForCode,
  waitingForPassword, // 2FA
  authenticated,
}

class StorageAuthState {
  final StorageAuthStep step;
  final String? phoneNumber;
  final String? error;
  final String? userId;
  final String? userName;

  const StorageAuthState({
    required this.step,
    this.phoneNumber,
    this.error,
    this.userId,
    this.userName,
  });

  bool get isAuthenticated => step == StorageAuthStep.authenticated;
}

/// Metadata describing the private Telegram vault channel container.
class VaultChannelInfo {
  final String channelId;
  final String title;
  final int totalMessages;
  final String? pinnedMessageId;

  const VaultChannelInfo({
    required this.channelId,
    required this.title,
    this.totalMessages = 0,
    this.pinnedMessageId,
  });
}

/// Information returned after uploading an encrypted file chunk.
class RemoteUploadedChunk {
  final String messageId;
  final String remoteFileId;
  final int sizeBytes;
  final String partFileName;

  const RemoteUploadedChunk({
    required this.messageId,
    required this.remoteFileId,
    required this.sizeBytes,
    required this.partFileName,
  });
}

/// Generic remote message representation (used for pinned index snapshots).
class RemoteMessage {
  final String messageId;
  final String? remoteFileId;
  final Uint8List? documentData;
  final String? caption;
  final DateTime date;

  const RemoteMessage({
    required this.messageId,
    this.remoteFileId,
    this.documentData,
    this.caption,
    required this.date,
  });
}

/// Progress callback signature.
typedef ProgressCallback = void Function(int bytesTransferred, int totalBytes);
