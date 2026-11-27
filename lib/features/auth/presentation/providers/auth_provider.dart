import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../../core/cache/session_cache_service.dart';
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
  final IndexSyncService? _syncService;
  final bool? _useNativeAndroidBiometricsOverride;
  StreamSubscription<StorageAuthState>? _storageAuthSubscription;

  AuthNotifier({
    required AuthRepository repository,
    required FiloDatabase database,
    LocalAuthentication? localAuth,
    IndexSyncService? syncService,
    @visibleForTesting bool? useNativeAndroidBiometricsOverride,
  })  : _repository = repository,
        _database = database,
        _localAuth = localAuth ?? LocalAuthentication(),
        _syncService = syncService,
        _useNativeAndroidBiometricsOverride = useNativeAndroidBiometricsOverride,
        super(const FiloAuthState(isLoading: true)) {
    _storageAuthSubscription = _repository.storageBackend.authStateStream?.listen((s) {
      if (s.isAuthenticated) {
        state = state.copyWith(
          isTelegramAuthenticated: true,
          telegramUserId: s.userId ?? state.telegramUserId,
          telegramUserName: s.userName ?? state.telegramUserName,
          telegramDisplayName: s.displayName ?? state.telegramDisplayName,
          telegramProfilePhotoPath: s.profilePhotoPath ?? state.telegramProfilePhotoPath,
        );
      }
    });
    initialize();
  }

  @override
  void dispose() {
    _storageAuthSubscription?.cancel();
    super.dispose();
  }

  bool get _isFlutterTest =>
      const bool.fromEnvironment('FLUTTER_TEST') ||
      (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST'));

  bool get _useNativeAndroidBiometrics =>
      _useNativeAndroidBiometricsOverride ??
      (!kIsWeb && Platform.isAndroid && !_isFlutterTest);

  IndexSyncService get _effectiveSyncService =>
      _syncService ??
      IndexSyncService(
        database: _database,
        storageBackend: _repository.storageBackend,
        authRepository: _repository,
      );

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
      final activeProvider = await _repository.getActiveCloudProvider();

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
        telegramDisplayName: authState.displayName,
        telegramProfilePhotoPath: authState.profilePhotoPath,
        activeCloudProvider: activeProvider ?? 'telegram',
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

  Stream<String>? get qrLinkStream => _repository.qrLinkStream;

  Future<String?> requestQrCode() async {
    return _repository.requestQrCode();
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
          telegramDisplayName: res.displayName,
          telegramProfilePhotoPath: res.profilePhotoPath,
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
          telegramDisplayName: res.displayName,
          telegramProfilePhotoPath: res.profilePhotoPath,
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

  Future<void> signOutTelegram() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _repository.storageBackend.signOut();
      state = state.copyWith(
        clearTelegramAuth: true,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  Future<String> setupNewVault(String passphrase) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    Uint8List? masterKey;
    try {
      final recoveryKey = await _repository.setupNewVault(passphrase: passphrase);
      masterKey = await _repository.unlockWithPassphrase(passphrase);

      _database.setEncryptionKey(Uint8List.fromList(masterKey));

      // Create storage channels in Telegram ('filo enc' and 'filo view')
      await _repository.storageBackend.getOrCreateVaultChannel(AppConfig.vaultEncryptedChannelTitle);
      await _repository.storageBackend.getOrCreateVaultChannel(AppConfig.vaultNativeChannelTitle);

      bool? updatedBioEnabled;
      if (state.isBiometricEnabled) {
        if (_useNativeAndroidBiometrics) {
          try {
            final enrolled = await _repository.enrollHardwareBiometricKey(masterKey);
            if (!enrolled) {
              await _repository.setBiometricEnabled(false);
              updatedBioEnabled = false;
            }
          } catch (_) {
            await _repository.setBiometricEnabled(false);
            updatedBioEnabled = false;
          }
        } else {
          await _repository.storeBiometricMasterKey(masterKey);
        }
      }

      // Check for existing backup BEFORE publishing initial empty snapshot
      final restored = await _maybeAutoRestore(masterKey);
      if (!restored) {
        try {
          final syncService = IndexSyncService(
            database: _database,
            storageBackend: _repository.storageBackend,
            authRepository: _repository,
          );
          await syncService.backupIndexToCloud(masterKey: masterKey);
        } catch (_) {}
      }

      final stateKey = Uint8List.fromList(masterKey);
      state = state.copyWith(
        vaultStatus: VaultSetupStatus.ready,
        lockStatus: AppLockStatus.unlocked,
        masterKey: stateKey,
        isBiometricEnabled: updatedBioEnabled,
        isLoading: false,
      );

      return recoveryKey;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    } finally {
      masterKey?.fillRange(0, masterKey.length, 0);
    }
  }

  void completeVaultSetup() {
    state = state.copyWith(
      vaultStatus: VaultSetupStatus.ready,
      lockStatus: AppLockStatus.unlocked,
    );
  }

  Future<void> changePassphrase({
    required String currentPassphrase,
    required String newPassphrase,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _repository.changePassphrase(
        currentPassphrase: currentPassphrase,
        newPassphrase: newPassphrase,
      );
      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    }
  }

  /// Shared unlock transition: configures DB encryption before auto-restore,
  /// checks legacy biometric entries on Android, and stores an isolated copy of
  /// [masterKey] in state.
  Future<void> _completeUnlockWithMasterKey(
    Uint8List masterKey, {
    bool checkBiometricBinding = false,
  }) async {
    _database.setEncryptionKey(Uint8List.fromList(masterKey));

    bool? updatedBioEnabled;
    if (checkBiometricBinding && state.isBiometricEnabled) {
      if (_useNativeAndroidBiometrics) {
        final clearedLegacy = await _repository.clearLegacyBiometricKeyIfUnbound();
        if (clearedLegacy) {
          updatedBioEnabled = false;
        }
      } else if (!await _repository.hasBiometricMasterKey()) {
        await _repository.storeBiometricMasterKey(masterKey);
      }
    }

    await _maybeAutoRestore(masterKey);
    _repository.storageBackend
        .getOrCreateVaultChannel(AppConfig.vaultEncryptedChannelTitle)
        .catchError((_) => const VaultChannelInfo(channelId: '', title: ''));
    _repository.storageBackend
        .getOrCreateVaultChannel(AppConfig.vaultNativeChannelTitle)
        .catchError((_) => const VaultChannelInfo(channelId: '', title: ''));

    final stateKey = Uint8List.fromList(masterKey);
    state = state.copyWith(
      vaultStatus: VaultSetupStatus.ready,
      lockStatus: AppLockStatus.unlocked,
      masterKey: stateKey,
      isBiometricEnabled: updatedBioEnabled,
      isLoading: false,
      errorMessage: null,
    );
  }

  Future<void> resetPassphraseWithRecoveryKey({
    required String recoveryKey,
    required String newPassphrase,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    Uint8List? masterKey;
    try {
      await _repository.resetPassphraseWithRecoveryKey(
        recoveryKey: recoveryKey,
        newPassphrase: newPassphrase,
      );
      masterKey = await _repository.unlockWithPassphrase(newPassphrase);
      await _completeUnlockWithMasterKey(masterKey, checkBiometricBinding: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      rethrow;
    } finally {
      masterKey?.fillRange(0, masterKey.length, 0);
    }
  }

  Future<void> unlockWithPassphrase(String passphrase) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    Uint8List? masterKey;
    try {
      masterKey = await _repository.unlockWithPassphrase(passphrase);
      await _completeUnlockWithMasterKey(masterKey, checkBiometricBinding: true);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Invalid passphrase. Please verify and try again.',
      );
      rethrow;
    } finally {
      masterKey?.fillRange(0, masterKey.length, 0);
    }
  }

  /// BUG 5 FIX: Emergency recovery path for when passphrase is lost
  Future<void> unlockWithRecoveryKey(String recoveryKey) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    Uint8List? masterKey;
    try {
      masterKey = await _repository.unlockWithRecoveryKey(recoveryKey);
      await _completeUnlockWithMasterKey(masterKey, checkBiometricBinding: true);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Invalid recovery key. Please check formatting and try again.',
      );
      rethrow;
    } finally {
      masterKey?.fillRange(0, masterKey.length, 0);
    }
  }

  Future<bool> unlockWithBiometrics() async {
    if (!state.isBiometricEnabled) return false;
    Uint8List? masterKey;
    try {
      final hasKey = await _repository.hasBiometricMasterKey();
      if (!hasKey) {
        state = state.copyWith(
          errorMessage: 'Biometric key not enrolled. Please unlock with passphrase.',
        );
        return false;
      }

      if (_useNativeAndroidBiometrics) {
        try {
          masterKey = await _repository.unlockWithHardwareBiometricKey(
            reason: 'Scan fingerprint to unlock Filo vault',
          );
        } on StateError catch (e) {
          if (e.message == 'BIOMETRIC_REENROLL_REQUIRED') {
            await _repository.setBiometricEnabled(false);
            state = state.copyWith(
              isBiometricEnabled: false,
              errorMessage:
                  'Biometric credential upgraded or invalidated. Please unlock with passphrase and re-enable biometric unlock.',
            );
            return false;
          }
          rethrow;
        }
        if (masterKey == null) {
          return false;
        }
        state = state.copyWith(isLoading: true, errorMessage: null);
        await _completeUnlockWithMasterKey(masterKey);
        return true;
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
        masterKey = await _repository.getBiometricMasterKey();
        if (masterKey != null) {
          state = state.copyWith(isLoading: true, errorMessage: null);
          await _completeUnlockWithMasterKey(masterKey);
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
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Biometric authentication error: $e',
      );
      return false;
    } finally {
      masterKey?.fillRange(0, masterKey.length, 0);
    }
  }

  /// Checks if local database is empty and automatically downloads & restores
  /// the encrypted backup pinned in the Telegram channel 'filo'.
  /// When local DB already has data, checks for updates asynchronously so unlock is instant.
  Future<bool> _maybeAutoRestore(Uint8List masterKey) async {
    try {
      final count = await _database.getNodeCount();
      if (count == 0) {
        return await _effectiveSyncService.checkAndAutoRestore(masterKey: masterKey);
      }
      // Non-blocking remote check & dirty push for existing local databases.
      // Copy key for async microtask and zero it upon completion.
      final microtaskKey = Uint8List.fromList(masterKey);
      Future<void>.microtask(() async {
        try {
          await _effectiveSyncService.checkRemoteUpdates(masterKey: microtaskKey);
        } finally {
          microtaskKey.fillRange(0, microtaskKey.length, 0);
        }
      });
      return false;
    } catch (_) {
      // Non-fatal if offline or no remote index exists yet
      return false;
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
    _syncService?.clearSessionKey();
    _database.clearEncryptionKey();
    final currentKey = state.masterKey;
    if (currentKey != null) {
      currentKey.fillRange(0, currentKey.length, 0);
    }
    // Zero-knowledge security rule: purge all decrypted session files immediately
    SessionCacheService.instance.purge();
    state = state.copyWith(
      lockStatus: AppLockStatus.locked,
      clearMasterKey: true,
    );
  }

  Future<bool> setBiometrics(bool enabled) async {
    state = state.copyWith(errorMessage: null);
    if (enabled) {
      try {
        if (_useNativeAndroidBiometrics) {
          final currentKey = state.masterKey;
          if (currentKey == null) {
            state = state.copyWith(
              errorMessage: 'Please unlock the vault before enabling biometric unlock.',
            );
            return false;
          }

          final hwAvailable = await _repository.canUseHardwareBiometric();
          if (!hwAvailable) {
            state = state.copyWith(
              errorMessage: 'Biometric authentication is not supported or enrolled on this device.',
            );
            return false;
          }

          final enrolled = await _repository.enrollHardwareBiometricKey(
            currentKey,
            reason: 'Authenticate to enable biometric unlock for Filo',
          );
          if (!enrolled) {
            return false;
          }

          await _repository.setBiometricEnabled(true);
          state = state.copyWith(isBiometricEnabled: true);
          return true;
        }

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
      _syncService?.clearSessionKey();
      _database.clearEncryptionKey();
      if (!identical(database, _database)) {
        database.clearEncryptionKey();
      }
      final currentKey = state.masterKey;
      if (currentKey != null) {
        currentKey.fillRange(0, currentKey.length, 0);
      }
      await SessionCacheService.instance.purge();
      try {
        final appDir = await getApplicationDocumentsDirectory();
        for (final dirName in const ['offline_vault', 'filo_tdlib', 'filo_tdlib_files', 'filo_exports']) {
          final dir = Directory(p.join(appDir.path, dirName));
          if (await dir.exists()) {
            await SessionCacheService.secureDeleteDirectory(dir);
          }
        }
      } on MissingPluginException {
        // Non-fatal in unit tests where path_provider isn't mocked
      } catch (_) {}
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
  final syncService = ref.watch(indexSyncServiceProvider);
  return AuthNotifier(repository: repo, database: db, syncService: syncService);
});
