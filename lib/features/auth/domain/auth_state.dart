import 'dart:typed_data';

enum AppLockStatus { unlocked, locked }
enum VaultSetupStatus { unconfigured, passphraseNeeded, ready }

/// Represents the overall application authentication & security state.
class FiloAuthState {
  final bool isTelegramAuthenticated;
  final String? telegramUserId;
  final String? telegramUserName;
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
    this.vaultStatus = VaultSetupStatus.unconfigured,
    this.lockStatus = AppLockStatus.unlocked,
    this.masterKey,
    this.isBiometricEnabled = false,
    this.autoLockTimeoutMinutes = 5,
    this.errorMessage,
    this.isLoading = false,
  });

  bool get isReady =>
      isTelegramAuthenticated &&
      vaultStatus == VaultSetupStatus.ready &&
      lockStatus == AppLockStatus.unlocked &&
      masterKey != null;

  FiloAuthState copyWith({
    bool? isTelegramAuthenticated,
    String? telegramUserId,
    String? telegramUserName,
    VaultSetupStatus? vaultStatus,
    AppLockStatus? lockStatus,
    Uint8List? masterKey,
    bool? isBiometricEnabled,
    int? autoLockTimeoutMinutes,
    String? errorMessage,
    bool? isLoading,
  }) {
    return FiloAuthState(
      isTelegramAuthenticated:
          isTelegramAuthenticated ?? this.isTelegramAuthenticated,
      telegramUserId: telegramUserId ?? this.telegramUserId,
      telegramUserName: telegramUserName ?? this.telegramUserName,
      vaultStatus: vaultStatus ?? this.vaultStatus,
      lockStatus: lockStatus ?? this.lockStatus,
      masterKey: masterKey ?? this.masterKey,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      autoLockTimeoutMinutes:
          autoLockTimeoutMinutes ?? this.autoLockTimeoutMinutes,
      errorMessage: errorMessage,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}
