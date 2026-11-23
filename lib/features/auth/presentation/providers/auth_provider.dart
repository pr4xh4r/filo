import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/database/filo_database.dart';
import '../../../storage/data/tdlib_storage_backend.dart';
import '../../../storage/domain/storage_backend.dart';
import '../../../storage/domain/storage_models.dart';
import '../../data/auth_repository.dart';
import '../../domain/auth_state.dart';

/// Global dependency providers
final storageBackendProvider = Provider<StorageBackend>((ref) {
  return TdlibStorageBackend(
    apiId: AppConfig.tgApiId,
    apiHash: AppConfig.tgApiHash,
  );
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final storage = ref.watch(storageBackendProvider);
  return AuthRepository(storageBackend: storage);
});

final databaseProvider = Provider<FiloDatabase>((ref) {
  // Uses in-memory for testing or defaults
  return FiloDatabase.openInMemory();
});

/// Riverpod StateNotifier managing the authentication and vault state.
class AuthNotifier extends StateNotifier<FiloAuthState> {
  final AuthRepository _repository;
  final LocalAuthentication _localAuth;

  AuthNotifier({
    required AuthRepository repository,
    LocalAuthentication? localAuth,
  })  : _repository = repository,
        _localAuth = localAuth ?? LocalAuthentication(),
        super(const FiloAuthState(isLoading: true)) {
    initialize();
  }

  Future<void> initialize() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _repository.storageBackend.initialize();
      final authState = await _repository.storageBackend.checkAuth();
      final hasVault = await _repository.hasConfiguredVault();
      final isBio = await _repository.isBiometricEnabled();
      final timeout = await _repository.getAutoLockTimeoutMinutes();

      VaultSetupStatus vaultStatus;
      if (!hasVault) {
        vaultStatus = VaultSetupStatus.unconfigured;
      } else {
        vaultStatus = VaultSetupStatus.passphraseNeeded;
      }

      state = state.copyWith(
        isTelegramAuthenticated: authState.isAuthenticated,
        telegramUserId: authState.userId,
        telegramUserName: authState.userName,
        vaultStatus: vaultStatus,
        lockStatus: hasVault ? AppLockStatus.locked : AppLockStatus.unlocked,
        isBiometricEnabled: isBio,
        autoLockTimeoutMinutes: timeout,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<StorageAuthState> sendTelegramCode(String phoneNumber) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _repository.storageBackend.sendCode(phoneNumber);
      state = state.copyWith(isLoading: false);
      return res;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<StorageAuthState> submitTelegramCode(String code) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _repository.storageBackend.signInWithCode(code);
      if (res.isAuthenticated) {
        final hasVault = await _repository.hasConfiguredVault();
        state = state.copyWith(
          isTelegramAuthenticated: true,
          telegramUserId: res.userId,
          telegramUserName: res.userName,
          vaultStatus: hasVault ? VaultSetupStatus.passphraseNeeded : VaultSetupStatus.unconfigured,
          isLoading: false,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: res.error,
        );
      }
      return res;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<StorageAuthState> submitTelegramPassword(String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final res = await _repository.storageBackend.checkPassword(password);
      if (res.isAuthenticated) {
        final hasVault = await _repository.hasConfiguredVault();
        state = state.copyWith(
          isTelegramAuthenticated: true,
          telegramUserId: res.userId,
          telegramUserName: res.userName,
          vaultStatus: hasVault ? VaultSetupStatus.passphraseNeeded : VaultSetupStatus.unconfigured,
          isLoading: false,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: res.error,
        );
      }
      return res;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<String> setupNewVault(String passphrase) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final recoveryKey = await _repository.setupNewVault(passphrase: passphrase);
      final masterKey = await _repository.unlockWithPassphrase(passphrase);

      // Create storage channel in Telegram
      await _repository.storageBackend.getOrCreateVaultChannel(AppConfig.vaultChannelTitle);

      if (state.isBiometricEnabled) {
        await _repository.storeBiometricMasterKey(masterKey);
      }

      state = state.copyWith(
        vaultStatus: VaultSetupStatus.ready,
        lockStatus: AppLockStatus.unlocked,
        masterKey: masterKey,
        isLoading: false,
      );

      return recoveryKey;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  Future<void> unlockWithPassphrase(String passphrase) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final masterKey = await _repository.unlockWithPassphrase(passphrase);
      if (state.isBiometricEnabled) {
        await _repository.storeBiometricMasterKey(masterKey);
      }
      state = state.copyWith(
        vaultStatus: VaultSetupStatus.ready,
        lockStatus: AppLockStatus.unlocked,
        masterKey: masterKey,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Invalid passphrase. Please verify and try again.',
      );
      rethrow;
    }
  }

  Future<bool> unlockWithBiometrics() async {
    if (!state.isBiometricEnabled) return false;
    try {
      final hasKey = await _repository.hasBiometricMasterKey();
      if (!hasKey) {
        state = state.copyWith(
          errorMessage: 'Biometric key not enrolled. Please unlock with passphrase.',
        );
        return false;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Scan fingerprint or face to unlock Filo vault',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );

      if (authenticated) {
        final masterKey = await _repository.getBiometricMasterKey();
        if (masterKey != null) {
          state = state.copyWith(
            vaultStatus: VaultSetupStatus.ready,
            lockStatus: AppLockStatus.unlocked,
            masterKey: masterKey,
            errorMessage: null,
          );
          return true;
        } else {
          state = state.copyWith(
            errorMessage: 'Biometric credential expired. Please enter master passphrase.',
          );
          return false;
        }
      }
      return false;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Biometric authentication error: $e');
      return false;
    }
  }

  void lockVault() {
    // Zero out master key in memory for security
    state = state.copyWith(
      lockStatus: AppLockStatus.locked,
      masterKey: null,
    );
  }

  Future<bool> setBiometrics(bool enabled) async {
    state = state.copyWith(errorMessage: null);
    if (enabled) {
      try {
        final canCheck = await _localAuth.canCheckBiometrics;
        final isSupported = await _localAuth.isDeviceSupported();
        if (!canCheck && !isSupported) {
          state = state.copyWith(
            errorMessage: 'Biometric authentication is not supported or enrolled on this device.',
          );
          return false;
        }

        final authenticated = await _localAuth.authenticate(
          localizedReason: 'Authenticate to enable biometric unlock for Filo',
          options: const AuthenticationOptions(
            biometricOnly: false,
            stickyAuth: true,
            useErrorDialogs: true,
          ),
        );

        if (!authenticated) {
          return false;
        }

        if (state.masterKey != null) {
          await _repository.storeBiometricMasterKey(state.masterKey!);
        }
        await _repository.setBiometricEnabled(true);
        state = state.copyWith(isBiometricEnabled: true);
        return true;
      } catch (e) {
        state = state.copyWith(errorMessage: 'Could not enable biometrics: $e');
        return false;
      }
    } else {
      await _repository.deleteBiometricMasterKey();
      await _repository.setBiometricEnabled(false);
      state = state.copyWith(isBiometricEnabled: false);
      return true;
    }
  }

  Future<void> setAutoLockTimeout(int minutes) async {
    await _repository.setAutoLockTimeoutMinutes(minutes);
    state = state.copyWith(autoLockTimeoutMinutes: minutes);
  }

  Future<void> logoutAndWipe(FiloDatabase database) async {
    state = state.copyWith(isLoading: true);
    try {
      await _repository.wipeLocalSecurity();
      await database.wipeAllLocalData();
      state = const FiloAuthState(
        isTelegramAuthenticated: false,
        vaultStatus: VaultSetupStatus.unconfigured,
        lockStatus: AppLockStatus.unlocked,
        masterKey: null,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }
}

final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, FiloAuthState>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return AuthNotifier(repository: repo);
});
