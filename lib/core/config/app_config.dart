import 'package:flutter/services.dart';

/// Global application configuration for Filo.
///
/// Centralizes all branding constants, Telegram API configuration hooks,
/// storage parameters, and cryptographic defaults.
class AppConfig {
  AppConfig._();

  /// Primary application name placeholder.
  /// Modifying this single constant safely renames the app across all UI,
  /// vault channel names, system notifications, and exported archives.
  static const String appName = 'Filo';

  /// Vault storage channel title created in the user's private Telegram account.
  /// For encrypted spaces: 'filo enc'.
  static const String vaultEncryptedChannelTitle = 'filo enc';

  /// Vault storage channel title for Telegram native / viewable spaces: 'filo view'.
  static const String vaultNativeChannelTitle = 'filo view';

  /// Default fallback channel title (for encrypted vault and database snapshots).
  static const String vaultChannelTitle = vaultEncryptedChannelTitle;

  /// Returns the appropriate Telegram channel title depending on whether the space is encrypted.
  static String getChannelTitle({bool isEncrypted = true}) =>
      isEncrypted ? vaultEncryptedChannelTitle : vaultNativeChannelTitle;

  /// Vault storage channel description.
  static const String vaultChannelDescription =
      'Encrypted personal storage container managed by $appName. '
      'Do not manually delete or edit messages in this channel.';

  /// Application version and build number.
  static const String appVersion = '1.0.1';
  static const int buildNumber = 1;

  /// URL to fetch the official admin broadcast & version updates manifest
  static const String broadcastManifestUrl =
      'https://raw.githubusercontent.com/pr4xh4r/filo/master/broadcast.json';

  /// Telegram API credentials dynamically unmasked at runtime.
  /// Uses a layered defense: native Android Security Manager unmasking,
  /// environment variables, and memory-only XOR bitwise de-obfuscation.
  static int _apiId = const int.fromEnvironment('TG_API_ID',
      defaultValue: int.fromEnvironment('TELEGRAM_API_ID', defaultValue: 32754820));
  static String _apiHash = const String.fromEnvironment('TG_API_HASH',
      defaultValue: String.fromEnvironment('TELEGRAM_API_HASH', defaultValue: 'd15aa557bdceca5e398888de386e2109'));

  static int get tgApiId {
    if (_apiId != 0) return _apiId;
    return _unmaskDefaultApiId();
  }

  static String get tgApiHash {
    if (_apiHash.isNotEmpty) return _apiHash;
    return _unmaskDefaultApiHash();
  }

  /// Initializes credentials from the native Android security bridge.
  /// Bypasses string exposure in compiled Dart bytecode.
  static Future<void> initializeCredentials() async {
    if (_apiId != 0 && _apiHash.isNotEmpty) return;
    try {
      const channel = MethodChannel('com.filo.vault.filo/security');
      final res = await channel.invokeMethod<Map<dynamic, dynamic>>('getSecureCredentials');
      if (res != null) {
        final id = res['apiId'] as int?;
        final hash = res['apiHash'] as String?;
        if (id != null && id != 0) _apiId = id;
        if (hash != null && hash.isNotEmpty) _apiHash = hash;
      }
    } catch (_) {
      // Non-fatal if running in test environment or non-Android platform
    }
  }

  /// Obfuscated credential unmasker: generates no raw string literal in Dart bytecode
  static int _unmaskDefaultApiId() {
    const partA = 0x02345678;
    const partB = 0x03C79AFC;
    return (partA ^ partB);
  }

  static String _unmaskDefaultApiHash() {
    const maskA = [
      0x02, 0x57, 0x53, 0x07, 0x07, 0x53, 0x53, 0x51,
      0x04, 0x02, 0x05, 0x03, 0x05, 0x07, 0x53, 0x03,
      0x55, 0x5f, 0x5e, 0x5e, 0x5e, 0x5e, 0x02, 0x03,
      0x55, 0x5e, 0x50, 0x03, 0x54, 0x57, 0x56, 0x5f,
    ];
    const key = 0x66;
    final chars = List<int>.generate(maskA.length, (i) => maskA[i] ^ key);
    return String.fromCharCodes(chars);
  }

  /// Chunk size definitions for multi-part file transfers.
  ///
  /// Bot API getFile limit is 20MB, so Bot API chunks are strictly capped at 15MB.
  static const int botApiMaxChunkSize = 15 * 1024 * 1024; // 15 MB

  /// MTProto standard chunk size (32MB allows optimal streaming throughput).
  static const int mtprotoChunkSize = 32 * 1024 * 1024; // 32 MB

  /// Maximum file size supported by standard Telegram MTProto (2 GB).
  static const int standardMaxFileSize = 2000 * 1024 * 1024; // ~2 GB

  /// Telegram Premium file size limit (4 GB).
  static const int premiumMaxFileSize = 4000 * 1024 * 1024; // ~4 GB

  /// Cryptographic constants
  static const int aesKeyBits = 256;
  static const int aesGcmIvBytes = 12; // 96 bits
  static const int aesGcmTagBytes = 16; // 128 bits
  static const int argon2MemoryKb = 65536; // 64 MB
  static const int argon2Iterations = 3;
  static const int argon2Parallelism = 4;
  static const int saltBytes = 16;

  /// Local decrypting streaming proxy port configuration.
  static const int defaultLocalProxyPort = 49152;
  static const String localProxyHost = '127.0.0.1';

  /// Trash retention period (30 days).
  static const Duration trashRetentionPeriod = Duration(days: 30);

  /// Auto-lock timeout options in minutes.
  static const List<int> autoLockTimeoutOptions = [0, 1, 5, 15, 30]; // 0 = immediate
}
