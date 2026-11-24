import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/database/filo_database.dart';
import '../../../storage/data/tdlib_storage_backend.dart';
import '../../../storage/domain/storage_backend.dart';
import '../../../storage/domain/storage_models.dart';
import '../../../sync/domain/index_sync_service.dart';
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

// BUG 2 FIX: databaseProvider is overridden in main() with a file-backed DB.
// Throws clearly if someone forgets to override it.
final databaseProvider = Provider<FiloDatabase>((ref) {
  throw StateError(
    'databaseProvider must be overridden in ProviderScope with a file-backed '
    'FiloDatabase. Call FiloDatabase.openFile() in main() and pass it via '
    'databaseProvider.overrideWithValue(database).',
  );
});

/// Riverpod StateNotifier managing the authentication and vault state.
class AuthNotifier extends StateNotifier<FiloAuthState> {
  final AuthRepository _repository;
  final FiloDatabase _database;
  final LocalAuthentication _localAuth;

  AuthNotifier({
    required AuthRepository repository,
    required FiloDatabase database,
    LocalAuthentication? localAuth,
  })  : _repository = repository,
        _database = database,
        _localAuth = localAuth ?? LocalAuthentication(),
        super(const FiloAuthState(isLoading: true)) {
    initialize();
  }

  Future<void> initialize() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _repository.storageBackend.initialize();
      final authState = await _repository.storageBackend.checkAuth();
      var hasVault = await _repository.hasConfiguredVault();

      if (authState.isAuthenticated && !hasVault) {
        try {
          final syncService = IndexSyncService(
            database: _database,
            storageBackend: _repository.storageBackend,
            authRepository: _repository,
          );
          final cloudBundle = await syncService.fetchCloudVaultKeyBundle();
          if (cloudBundle != null) {
            await _repository.importVaultKeyBundle(cloudBundle);
            hasVault = true;
          }
        } catch (_) {}
      }

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
        var hasVault = await _repository.hasConfiguredVault();
        if (!hasVault) {
          try {
            final syncService = IndexSyncService(
              database: _database,
              storageBackend: _repository.storageBackend,
              authRepository: _repository,
            );
            final cloudBundle = await syncService.fetchCloudVaultKeyBundle();
            if (cloudBundle != null) {
              await _repository.importVaultKeyBundle(cloudBundle);
              hasVault = true;
            }
          } catch (_) {}
        }
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
        var hasVault = await _repository.hasConfiguredVault();
        if (!hasVault) {
          try {
            final syncService = IndexSyncService(
              database: _database,
              storageBackend: _repository.storageBackend,
              authRepository: _repository,
            );
            final cloudBundle = await syncService.fetchCloudVaultKeyBundle();
            if (cloudBundle != null) {
              await _repository.importVaultKeyBundle(cloudBundle);
              hasVault = true;
            }
          } catch (_) {}
        }
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

      // Create storage channel in Telegram ('filo')
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

      // Immediately back up initial vault envelope to Telegram channel 'filo'
      try {
        final syncService = IndexSyncService(
          database: _database,
          storageBackend: _repository.storageBackend,
          authRepository: _repository,
        );
        await syncService.backupIndexToCloud(masterKey: masterKey);
      } catch (_) {}

      // Auto-restore check in case user is re-setting up existing account on new device
      await _maybeAutoRestore(masterKey);

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
      await _maybeAutoRestore(masterKey);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Invalid passphrase. Please verify and try again.',
      );
      rethrow;
    }
  }

  /// BUG 5 FIX: Emergency recovery path for when passphrase is lost
  Future<void> unlockWithRecoveryKey(String recoveryKey) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final masterKey = await _repository.unlockWithRecoveryKey(recoveryKey);
      if (state.isBiometricEnabled) {
        await _repository.storeBiometricMasterKey(masterKey);
      }
      state = state.copyWith(
        vaultStatus: VaultSetupStatus.ready,
        lockStatus: AppLockStatus.unlocked,
        masterKey: masterKey,
        isLoading: false,
      );
      await _maybeAutoRestore(masterKey);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Invalid recovery key. Please check formatting and try again.',
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
          await _maybeAutoRestore(masterKey);
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

  /// Checks if local database is empty and automatically downloads & restores
  /// the encrypted index snapshot pinned in the Telegram channel 'filo'.
  Future<void> _maybeAutoRestore(Uint8List masterKey) async {
    try {
      final syncService = IndexSyncService(
        database: _database,
        storageBackend: _repository.storageBackend,
        authRepository: _repository,
      );
      await syncService.checkAndAutoRestore(masterKey: masterKey);
    } catch (_) {
      // Non-fatal if offline or no remote index exists yet
    }
  }

  /// Checks Telegram channel 'filo' for existing vault snapshot envelope.
  /// If found, imports the wrapped key bundle so user can unlock with their master passphrase.
  Future<bool> checkForCloudVault() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final syncService = IndexSyncService(
        database: _database,
        storageBackend: _repository.storageBackend,
        authRepository: _repository,
      );
      final cloudBundle = await syncService.fetchCloudVaultKeyBundle();
      if (cloudBundle != null) {
        await _repository.importVaultKeyBundle(cloudBundle);
        state = state.copyWith(
          vaultStatus: VaultSetupStatus.passphraseNeeded,
          lockStatus: AppLockStatus.locked,
          isLoading: false,
        );
        return true;
      }
      state = state.copyWith(isLoading: false);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
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
      // BUG 20 FIX: Use || (not &&) — block if EITHER check fails
        if (!canCheck || !isSupported) {
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
  final db = ref.watch(databaseProvider);
  return AuthNotifier(repository: repo, database: db);
});
