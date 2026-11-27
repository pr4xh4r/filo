import 'dart:convert';
import 'dart:io';
import 'package:filo/core/cache/session_cache_service.dart';
import 'package:filo/core/crypto/crypto_engine.dart';
import 'package:filo/core/crypto/hash_utils.dart';
import 'package:filo/core/database/filo_database.dart';
import 'package:filo/features/auth/data/auth_repository.dart';
import 'package:filo/features/auth/domain/auth_state.dart';
import 'package:filo/features/auth/presentation/providers/auth_provider.dart';
import 'package:filo/features/storage/data/fake_storage_backend.dart';
import 'package:filo/features/storage/data/tdlib_storage_backend.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const securityChannel = MethodChannel('com.filo.vault.filo/security');

  late Directory sessionTempDir;
  late Directory tdTempDir;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    sessionTempDir = Directory.systemTemp.createTempSync('filo_auth_sec_sess_');
    tdTempDir = Directory.systemTemp.createTempSync('filo_auth_sec_td_');
    SessionCacheService.instance.setOverrideDirectory(sessionTempDir);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(securityChannel, null);
  });

  tearDown(() {
    SessionCacheService.instance.setOverrideDirectory(null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(securityChannel, null);
    for (final dir in [sessionTempDir, tdTempDir]) {
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('VULN-03: FiloAuthState.copyWith & In-Memory Key Hygiene', () {
    test('copyWith(clearMasterKey: true) clears masterKey to null', () {
      final key = CryptoEngine.generateMasterKey();
      final unlocked = FiloAuthState(
        isTelegramAuthenticated: true,
        vaultStatus: VaultSetupStatus.ready,
        lockStatus: AppLockStatus.unlocked,
        masterKey: key,
      );

      expect(unlocked.isReady, isTrue);
      expect(unlocked.masterKey, isNotNull);

      // Without clearMasterKey, omitting masterKey preserves existing key
      final stillHasKey = unlocked.copyWith(lockStatus: AppLockStatus.locked);
      expect(stillHasKey.masterKey, isNotNull);

      // With clearMasterKey: true, masterKey is explicitly cleared to null
      final locked = unlocked.copyWith(
        lockStatus: AppLockStatus.locked,
        clearMasterKey: true,
      );
      expect(locked.lockStatus, AppLockStatus.locked);
      expect(locked.masterKey, isNull);
      expect(locked.isReady, isFalse);
    });

    test('AuthNotifier.lockVault() zeroes key buffer, clears state.masterKey, and clears DB encryption key', () async {
      final storageBackend = FakeStorageBackend();
      await storageBackend.initialize();
      storageBackend.setAuthenticated();
      final db = FiloDatabase.openInMemory();
      final repo = AuthRepository(storageBackend: storageBackend);
      final notifier = AuthNotifier(repository: repo, database: db);

      // Ensure async constructor initialize() settles
      await notifier.initialize();

      const passphrase = 'CorrectHorseBatteryStaple2026!';
      await notifier.setupNewVault(passphrase);

      expect(notifier.state.lockStatus, AppLockStatus.unlocked);
      expect(notifier.state.vaultStatus, VaultSetupStatus.ready);
      expect(notifier.state.masterKey, isNotNull);
      expect(db.hasEncryptionKey, isTrue);

      // Hold reference to the live state key buffer to verify in-place zeroing
      final liveKeyBuffer = notifier.state.masterKey!;
      final expectedKeyCopy = Uint8List.fromList(liveKeyBuffer);
      expect(liveKeyBuffer.any((b) => b != 0), isTrue);

      // Put a decrypted session artifact on disk to verify purge() also runs
      final cachedFile = await SessionCacheService.instance.getSessionFile('n1', 'txt');
      await cachedFile.writeAsString('secret');
      expect(cachedFile.existsSync(), isTrue);

      // Lock vault (synchronously zeroes key & clears DB key, triggers async session purge)
      notifier.lockVault();

      expect(notifier.state.lockStatus, AppLockStatus.locked);
      expect(notifier.state.masterKey, isNull);
      expect(notifier.state.isReady, isFalse);
      expect(liveKeyBuffer.every((b) => b == 0), isTrue);
      expect(db.hasEncryptionKey, isFalse);

      // Allow unawaited async SessionCacheService.purge() disk scrub to complete
      for (var i = 0; i < 20 && cachedFile.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
      expect(cachedFile.existsSync(), isFalse);

      // Re-unlock with passphrase restores identical master key & DB encryption key
      await notifier.unlockWithPassphrase(passphrase);
      expect(notifier.state.lockStatus, AppLockStatus.unlocked);
      expect(notifier.state.masterKey, isNotNull);
      expect(
        HashUtils.constantTimeCompare(notifier.state.masterKey!, expectedKeyCopy),
        isTrue,
      );
      expect(db.hasEncryptionKey, isTrue);

      // Logout and wipe zeroes state key, clears DB encryption key, and resets state
      final keyBeforeWipe = notifier.state.masterKey!;
      await notifier.logoutAndWipe(db);
      expect(keyBeforeWipe.every((b) => b == 0), isTrue);
      expect(notifier.state.masterKey, isNull);
      expect(notifier.state.vaultStatus, VaultSetupStatus.unconfigured);
      expect(db.hasEncryptionKey, isFalse);
      expect(await repo.hasConfiguredVault(), isFalse);

      notifier.dispose();
      db.close();
    });
  });

  group('VULN-04: Hardware Biometric Keystore Binding & Legacy Rejection', () {
    test('Rejects and deletes legacy plaintext biometric key without v2_hw: prefix', () async {
      final legacyKey = CryptoEngine.generateMasterKey();
      FlutterSecureStorage.setMockInitialValues({
        'filo_biometric_enabled': 'true',
        'filo_biometric_master_key': base64Encode(legacyKey),
      });

      final storageBackend = FakeStorageBackend();
      await storageBackend.initialize();
      final repo = AuthRepository(
        storageBackend: storageBackend,
        useHardwareKeystoreOverride: true,
      );

      expect(await repo.hasBiometricMasterKey(), isTrue);

      await expectLater(
        repo.unlockWithHardwareBiometricKey(),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'BIOMETRIC_REENROLL_REQUIRED',
          ),
        ),
      );

      // Legacy plaintext entry must be deleted rather than trusted
      expect(await repo.hasBiometricMasterKey(), isFalse);
      expect(await repo.getBiometricMasterKey(), isNull);
    });

    test('AuthNotifier.unlockWithBiometrics clears legacy unbound entry and disables biometrics', () async {
      final legacyKey = CryptoEngine.generateMasterKey();
      FlutterSecureStorage.setMockInitialValues({
        'filo_biometric_enabled': 'true',
        'filo_biometric_master_key': base64Encode(legacyKey),
      });

      final storageBackend = FakeStorageBackend();
      await storageBackend.initialize();
      final db = FiloDatabase.openInMemory();
      final repo = AuthRepository(
        storageBackend: storageBackend,
        useHardwareKeystoreOverride: true,
      );
      final notifier = AuthNotifier(
        repository: repo,
        database: db,
        useNativeAndroidBiometricsOverride: true,
      );
      await notifier.initialize();

      expect(notifier.state.isBiometricEnabled, isTrue);

      final unlocked = await notifier.unlockWithBiometrics();
      expect(unlocked, isFalse);
      expect(notifier.state.masterKey, isNull);
      expect(notifier.state.isBiometricEnabled, isFalse);
      expect(notifier.state.errorMessage, isNotNull);
      expect(await repo.hasBiometricMasterKey(), isFalse);
      expect(await repo.isBiometricEnabled(), isFalse);
      expect(db.hasEncryptionKey, isFalse);

      notifier.dispose();
      db.close();
    });

    test('Hardware biometric enroll & unseal via security MethodChannel works and clears on invalidation', () async {
      final masterKey = CryptoEngine.generateMasterKey();
      String? sealedByHost;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(securityChannel, (MethodCall call) async {
        switch (call.method) {
          case 'canUseHardwareBiometric':
            return true;
          case 'enrollBiometricKey':
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final b64 = args['masterKeyBase64'] as String;
            sealedByHost = 'v2_hw:$b64';
            return sealedByHost;
          case 'unsealBiometricKey':
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final blob = args['wrappedBlob'] as String;
            if (!blob.startsWith('v2_hw:')) {
              throw PlatformException(code: 'BIOMETRIC_REENROLL_REQUIRED');
            }
            return blob.substring('v2_hw:'.length);
          case 'deleteBiometricKey':
            sealedByHost = null;
            return true;
          default:
            return null;
        }
      });

      final storageBackend = FakeStorageBackend();
      await storageBackend.initialize();
      final repo = AuthRepository(
        storageBackend: storageBackend,
        useHardwareKeystoreOverride: true,
      );

      final enrolled = await repo.enrollHardwareBiometricKey(masterKey);
      expect(enrolled, isTrue);
      expect(await repo.hasBiometricMasterKey(), isTrue);

      final unsealed = await repo.unlockWithHardwareBiometricKey();
      expect(unsealed, isNotNull);
      expect(HashUtils.constantTimeCompare(unsealed!, masterKey), isTrue);

      // Simulate KeyPermanentlyInvalidatedException from Android Keystore
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(securityChannel, (MethodCall call) async {
        if (call.method == 'unsealBiometricKey') {
          throw PlatformException(
            code: 'BIOMETRIC_REENROLL_REQUIRED',
            message: 'Biometrics changed',
          );
        }
        if (call.method == 'deleteBiometricKey') return true;
        return null;
      });

      await expectLater(
        repo.unlockWithHardwareBiometricKey(),
        throwsA(isA<StateError>()),
      );
      expect(await repo.hasBiometricMasterKey(), isFalse);
    });
  });

  group('VULN-05: TDLib Database Encryption Key Management', () {
    test('Generates & persists 32-byte key on fresh install and reuses it on restart', () async {
      const secureStorage = FlutterSecureStorage();
      final backend = TdlibStorageBackend(
        apiId: 12345,
        apiHash: 'test_hash',
        secureStorage: secureStorage,
      );

      // Case 2: Fresh install (no td.binlog, no stored key)
      final key1 = await backend.resolveDatabaseEncryptionKeyForTest(tdTempDir.path);
      expect(key1.isNotEmpty, isTrue);
      expect(base64Decode(key1).length, 32);
      expect(backend.needsLegacyKeyMigrationForTest, isFalse);

      final stored = await secureStorage.read(key: 'filo_tdlib_db_key');
      expect(stored, key1);

      // Case 1: Subsequent launch reads persisted key
      final backend2 = TdlibStorageBackend(
        apiId: 12345,
        apiHash: 'test_hash',
        secureStorage: secureStorage,
      );
      final key2 = await backend2.resolveDatabaseEncryptionKeyForTest(tdTempDir.path);
      expect(key2, key1);
      expect(backend2.needsLegacyKeyMigrationForTest, isFalse);

      await backend.dispose();
      await backend2.dispose();
    });

    test('Detects legacy unencrypted td.binlog and flags migration without locking out', () async {
      const secureStorage = FlutterSecureStorage();
      final binlog = File(p.join(tdTempDir.path, 'td.binlog'));
      await binlog.writeAsBytes([1, 2, 3, 4]);

      final backend = TdlibStorageBackend(
        apiId: 12345,
        apiHash: 'test_hash',
        secureStorage: secureStorage,
      );

      final initialKey = await backend.resolveDatabaseEncryptionKeyForTest(tdTempDir.path);
      expect(initialKey, '');
      expect(backend.needsLegacyKeyMigrationForTest, isTrue);

      await backend.dispose();
    });
  });
}
