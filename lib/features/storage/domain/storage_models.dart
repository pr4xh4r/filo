import 'dart:typed_data';

/// Authentication state for the storage backend.
enum StorageAuthStep {
  unauthenticated,
  waitingForPhoneNumber,
  waitingForCode,
  waitingForPassword, // 2FA
  waitingForOtherDeviceConfirmation, // QR login
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

/// Information about user storage quota and plan tier.
class StorageQuotaInfo {
  final int totalBytes; // -1 if unlimited
  final int usedBytes;
  final String planName; // e.g. "15 GB Free", "2 TB Plan", "5 TB Ultra", "Unlimited"
  final String? accountEmail;
  final String providerName; // "Telegram"

  const StorageQuotaInfo({
    required this.totalBytes,
    required this.usedBytes,
    required this.planName,
    this.accountEmail,
    required this.providerName,
  });

  bool get isUnlimited => totalBytes <= 0;
  double get usagePercent => isUnlimited ? 0.0 : (usedBytes / totalBytes).clamp(0.0, 1.0);
  int get freeBytes => isUnlimited ? -1 : (totalBytes - usedBytes).clamp(0, totalBytes);

  String get formattedTotal {
    if (isUnlimited) return 'Unlimited';
    final gb = totalBytes / (1024 * 1024 * 1024);
    if (gb >= 1000) {
      return '${(gb / 1024).toStringAsFixed(1).replaceAll('.0', '')} TB';
    }
    return '${gb.toStringAsFixed(0)} GB';
  }

  String get formattedUsed {
    final mb = usedBytes / (1024 * 1024);
    if (mb < 1) return '$usedBytes B';
    if (mb < 1000) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    if (gb >= 1000) {
      return '${(gb / 1024).toStringAsFixed(2)} TB';
    }
    return '${gb.toStringAsFixed(1)} GB';
  }

  String get formattedFree {
    if (isUnlimited) return 'Unlimited';
    final free = freeBytes;
    final gb = free / (1024 * 1024 * 1024);
    if (gb >= 1000) {
      return '${(gb / 1024).toStringAsFixed(1).replaceAll('.0', '')} TB free';
    }
    return '${gb.toStringAsFixed(1)} GB free';
  }
}
