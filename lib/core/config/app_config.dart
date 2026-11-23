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
  static const String vaultChannelTitle = '$appName Vault';

  /// Vault storage channel description.
  static const String vaultChannelDescription =
      'Encrypted personal storage container managed by $appName. '
      'Do not manually delete or edit messages in this channel.';

  /// Application version and build number.
  static const String appVersion = '1.0.0';
  static const int buildNumber = 1;

  /// Telegram API credentials.
  /// In production, inject via `--dart-define-from-file=config.json`
  /// or `--dart-define=TG_API_ID=xxx --dart-define=TG_API_HASH=yyy`
  static const int tgApiId = int.fromEnvironment('TG_API_ID',
      defaultValue: int.fromEnvironment('TELEGRAM_API_ID', defaultValue: 0));
  static const String tgApiHash = String.fromEnvironment('TG_API_HASH',
      defaultValue: String.fromEnvironment('TELEGRAM_API_HASH', defaultValue: ''));

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
