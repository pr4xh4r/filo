import 'dart:typed_data';

enum AppLockStatus { unlocked, locked }
enum VaultSetupStatus { unconfigured, passphraseNeeded, ready }

/// Represents the overall application authentication & security state.
class FiloAuthState {
  final bool isTelegramAuthenticated;
  final String? telegramUserId;
  final String? telegramUserName;
  final String? telegramDisplayName;
  final String? telegramProfilePhotoPath;
  final String activeCloudProvider; // 'telegram'
  final VaultSetupStatus vaultStatus;
  final AppLockStatus lockStatus;
  final Uint8List? masterKey; // In-memory while app is unlocked, cleared on lock/wipe
  final bool isBiometricEnabled;
  final int autoLockTimeoutMinutes;
  final String? errorMessage;
  final bool isLoading;

  const FiloAuthState({
    this.isTelegramAuthenticated = false,
    this.telegramUserId,
    this.telegramUserName,
    this.telegramDisplayName,
    this.telegramProfilePhotoPath,
    this.activeCloudProvider = 'telegram',
    this.vaultStatus = VaultSetupStatus.unconfigured,
    this.lockStatus = AppLockStatus.unlocked,
    this.masterKey,
    this.isBiometricEnabled = false,
    this.autoLockTimeoutMinutes = 5,
    this.errorMessage,
    this.isLoading = false,
  });

  bool get isCloudAuthenticated => isTelegramAuthenticated;

  bool get isReady =>
      isCloudAuthenticated &&
      vaultStatus == VaultSetupStatus.ready &&
      lockStatus == AppLockStatus.unlocked &&
      masterKey != null;

  FiloAuthState copyWith({
    bool? isTelegramAuthenticated,
    String? telegramUserId,
    String? telegramUserName,
    String? telegramDisplayName,
    String? telegramProfilePhotoPath,
    bool clearTelegramAuth = false,
    String? activeCloudProvider,
    VaultSetupStatus? vaultStatus,
    AppLockStatus? lockStatus,
    Uint8List? masterKey,
    bool clearMasterKey = false,
    bool? isBiometricEnabled,
    int? autoLockTimeoutMinutes,
    String? errorMessage,
    bool? isLoading,
  }) {
    return FiloAuthState(
      isTelegramAuthenticated: clearTelegramAuth
          ? false
          : (isTelegramAuthenticated ?? this.isTelegramAuthenticated),
      telegramUserId:
          clearTelegramAuth ? null : (telegramUserId ?? this.telegramUserId),
      telegramUserName:
          clearTelegramAuth ? null : (telegramUserName ?? this.telegramUserName),
      telegramDisplayName: clearTelegramAuth
          ? null
          : (telegramDisplayName ?? this.telegramDisplayName),
      telegramProfilePhotoPath: clearTelegramAuth
          ? null
          : (telegramProfilePhotoPath ?? this.telegramProfilePhotoPath),
      activeCloudProvider: activeCloudProvider ?? this.activeCloudProvider,
      vaultStatus: vaultStatus ?? this.vaultStatus,
      lockStatus: lockStatus ?? this.lockStatus,
      masterKey: clearMasterKey ? null : (masterKey ?? this.masterKey),
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      autoLockTimeoutMinutes:
          autoLockTimeoutMinutes ?? this.autoLockTimeoutMinutes,
      errorMessage: errorMessage,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

