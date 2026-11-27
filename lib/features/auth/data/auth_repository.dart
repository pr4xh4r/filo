import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/crypto/argon2_kdf.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/crypto/hash_utils.dart';
import '../../../core/crypto/key_wrapper.dart';
import '../../../core/crypto/recovery_key.dart';
import '../../storage/domain/storage_backend.dart';

/// Manages secure key storage, passphrase verification, and hardware keystore interaction.
class AuthRepository {
  final FlutterSecureStorage _secureStorage;
  final StorageBackend _storageBackend;
  final MethodChannel _securityChannel;
  final bool? _useHardwareKeystoreOverride;

  static const _keyWrappedBundle = 'filo_wrapped_master_key';
  static const _keyBiometricEnabled = 'filo_biometric_enabled';
  static const _keyBiometricMasterKey = 'filo_biometric_master_key';
  static const _keyAutoLockTimeout = 'filo_auto_lock_timeout';
  static const _keyRecoveryKeyHash = 'filo_recovery_key_hash';
  // BUG 5 FIX: Store a separate bundle wrapped with the recovery key as KEK
  static const _keyRecoveryWrappedBundle = 'filo_recovery_wrapped_bundle';
  static const _keyActiveCloudProvider = 'filo_active_cloud_provider';
  static const _hwBiometricPrefix = 'v2_hw:';

  AuthRepository({
    required StorageBackend storageBackend,
    FlutterSecureStorage? secureStorage,
    MethodChannel? securityChannel,
    @visibleForTesting bool? useHardwareKeystoreOverride,
  })  : _storageBackend = storageBackend,
        _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
            ),
        _securityChannel =
            securityChannel ?? const MethodChannel('com.filo.vault.filo/security'),
        _useHardwareKeystoreOverride = useHardwareKeystoreOverride;

  bool get _useHardwareKeystore =>
      _useHardwareKeystoreOverride ?? (!kIsWeb && Platform.isAndroid);

  bool get _isFlutterTest =>
      const bool.fromEnvironment('FLUTTER_TEST') ||
      (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST'));

  StorageBackend get storageBackend => _storageBackend;
  Stream<String>? get qrLinkStream => _storageBackend.qrLinkStream;
  Future<String?> requestQrCode() => _storageBackend.requestQrCode();

  /// Checks if a vault has already been configured on this device.
  Future<bool> hasConfiguredVault() async {
    final bundleJson = await _secureStorage.read(key: _keyWrappedBundle);
    return bundleJson != null && bundleJson.isNotEmpty;
  }

  /// Sets up a new vault by generating a Master Key, wrapping it with the passphrase,
  /// and storing the bundle in device secure storage.
  /// Returns the formatted emergency recovery key.
  Future<String> setupNewVault({
    required String passphrase,
  }) async {
    final masterKey = CryptoEngine.generateMasterKey();
    final salt = Argon2Kdf.generateSalt();
    Uint8List? kek;
    Uint8List? recoveryKeyBytes;
    try {
      kek = await Argon2Kdf.deriveKey(
        passphrase: passphrase,
        salt: salt,
      );

      final bundle = await KeyWrapper.wrapKey(
        masterKey: masterKey,
        kek: kek,
        salt: salt,
      );

      // BUG 5 FIX: Generate recovery key and wrap the SAME master key under it
      final recoveryKey = RecoveryKey.generate();
      recoveryKeyBytes = RecoveryKey.parseToBytes(recoveryKey);
      final recoveryHash = HashUtils.sha256Hex(recoveryKeyBytes);

      final recoverySalt = Argon2Kdf.generateSalt();
      final recoveryBundle = await KeyWrapper.wrapKey(
        masterKey: masterKey,
        kek: recoveryKeyBytes,
        salt: recoverySalt,
      );

      await _secureStorage.write(
        key: _keyWrappedBundle,
        value: json.encode(bundle.toJson()),
      );
      await _secureStorage.write(
        key: _keyRecoveryKeyHash,
        value: recoveryHash,
      );
      await _secureStorage.write(
        key: _keyRecoveryWrappedBundle,
        value: json.encode(recoveryBundle.toJson()),
      );

      return recoveryKey;
    } finally {
      masterKey.fillRange(0, masterKey.length, 0);
      kek?.fillRange(0, kek.length, 0);
      recoveryKeyBytes?.fillRange(0, recoveryKeyBytes.length, 0);
    }
  }

  /// Unlocks the vault using the user's passphrase.
  /// Returns the unwrapped 256-bit Master Key.
  Future<Uint8List> unlockWithPassphrase(String passphrase) async {
    final bundleJson = await _secureStorage.read(key: _keyWrappedBundle);
    if (bundleJson == null) {
      throw Exception('Vault not initialized on this device');
    }

    final bundleMap = json.decode(bundleJson) as Map<String, dynamic>;
    final bundle = WrappedKeyBundle.fromJson(bundleMap);

    final kek = await Argon2Kdf.deriveKey(
      passphrase: passphrase,
      salt: bundle.salt,
    );
    try {
      return await KeyWrapper.unwrapKey(bundle: bundle, kek: kek);
    } finally {
      kek.fillRange(0, kek.length, 0);
    }
  }

  /// BUG 5 FIX: Unlocks the vault using the emergency recovery key.
  /// This is the disaster recovery path when the passphrase is forgotten.
  Future<Uint8List> unlockWithRecoveryKey(String formattedRecoveryKey) async {
    final recoveryBundleJson =
        await _secureStorage.read(key: _keyRecoveryWrappedBundle);
    if (recoveryBundleJson == null) {
      throw Exception(
        'No recovery bundle found. This vault was created before recovery key support was added. '
        'Please use your passphrase to unlock.',
      );
    }

    final storedHash = await _secureStorage.read(key: _keyRecoveryKeyHash);
    final recoveryKeyBytes = RecoveryKey.parseToBytes(formattedRecoveryKey);
    try {
      final providedHash = HashUtils.sha256Hex(recoveryKeyBytes);

      if (storedHash != null &&
          !HashUtils.constantTimeCompare(
            providedHash.codeUnits,
            storedHash.codeUnits,
          )) {
        throw Exception('Invalid recovery key.');
      }

      final bundle = WrappedKeyBundle.fromJson(
        json.decode(recoveryBundleJson) as Map<String, dynamic>,
      );

      return await KeyWrapper.unwrapKey(bundle: bundle, kek: recoveryKeyBytes);
    } finally {
      recoveryKeyBytes.fillRange(0, recoveryKeyBytes.length, 0);
    }
  }

  /// Re-wraps the Master Key when the user changes their passphrase.
  /// Existing encrypted files in Telegram do not require re-encryption!
  Future<void> changePassphrase({
    required String currentPassphrase,
    required String newPassphrase,
  }) async {
    final bundleJson = await _secureStorage.read(key: _keyWrappedBundle);
    if (bundleJson == null) {
      throw Exception('Vault not initialized');
    }

    final oldBundle = WrappedKeyBundle.fromJson(
      json.decode(bundleJson) as Map<String, dynamic>,
    );

    Uint8List? oldKek;
    Uint8List? masterKey;
    Uint8List? newKek;
    try {
      oldKek = await Argon2Kdf.deriveKey(
        passphrase: currentPassphrase.trim(),
        salt: oldBundle.salt,
      );
      masterKey = await KeyWrapper.unwrapKey(bundle: oldBundle, kek: oldKek);

      final newSalt = Argon2Kdf.generateSalt();
      newKek = await Argon2Kdf.deriveKey(
        passphrase: newPassphrase.trim(),
        salt: newSalt,
      );

      final newBundle = await KeyWrapper.wrapKey(
        masterKey: masterKey,
        kek: newKek,
        salt: newSalt,
      );

      await _secureStorage.write(
        key: _keyWrappedBundle,
        value: json.encode(newBundle.toJson()),
      );
    } finally {
      oldKek?.fillRange(0, oldKek.length, 0);
      masterKey?.fillRange(0, masterKey.length, 0);
      newKek?.fillRange(0, newKek.length, 0);
    }
  }

  /// Disaster recovery path: resets passphrase using the emergency recovery key.
  Future<void> resetPassphraseWithRecoveryKey({
    required String recoveryKey,
    required String newPassphrase,
  }) async {
    Uint8List? masterKey;
    Uint8List? newKek;
    try {
      masterKey = await unlockWithRecoveryKey(recoveryKey.trim());

      final newSalt = Argon2Kdf.generateSalt();
      newKek = await Argon2Kdf.deriveKey(
        passphrase: newPassphrase.trim(),
        salt: newSalt,
      );

      final newBundle = await KeyWrapper.wrapKey(
        masterKey: masterKey,
        kek: newKek,
        salt: newSalt,
      );

      await _secureStorage.write(
        key: _keyWrappedBundle,
        value: json.encode(newBundle.toJson()),
      );
    } finally {
      masterKey?.fillRange(0, masterKey.length, 0);
      newKek?.fillRange(0, newKek.length, 0);
    }
  }

  /// Biometric preference helpers
  Future<bool> isBiometricEnabled() async {
    final val = await _secureStorage.read(key: _keyBiometricEnabled);
    return val == 'true';
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _secureStorage.write(
      key: _keyBiometricEnabled,
      value: enabled.toString(),
    );
  }

  Future<bool> canUseHardwareBiometric() async {
    if (!_useHardwareKeystore) return false;
    try {
      final available =
          await _securityChannel.invokeMethod<bool>('canUseHardwareBiometric');
      return available ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Wraps and persists the Master Key inside an Android Hardware Keystore-backed
  /// AES-256-GCM cipher authenticated by `BiometricPrompt.CryptoObject`.
  Future<bool> enrollHardwareBiometricKey(
    Uint8List masterKey, {
    String reason = 'Authenticate to enable biometric unlock for Filo',
  }) async {
    if (!_useHardwareKeystore) {
      await storeBiometricMasterKey(masterKey);
      return true;
    }

    try {
      final wrappedBlob = await _securityChannel.invokeMethod<String>(
        'enrollBiometricKey',
        {
          'masterKeyBase64': base64Encode(masterKey),
          'reason': reason,
        },
      );
      if (wrappedBlob == null || !wrappedBlob.startsWith(_hwBiometricPrefix)) {
        return false;
      }
      await _secureStorage.write(
        key: _keyBiometricMasterKey,
        value: wrappedBlob,
      );
      return true;
    } on MissingPluginException {
      // Only fall back in unit tests where native platform channel is absent;
      // never bypass Android Keystore on real devices.
      if (_isFlutterTest) {
        await storeBiometricMasterKey(masterKey);
        return true;
      }
      rethrow;
    } on PlatformException catch (e) {
      if (e.code == 'BIOMETRIC_CANCELED') {
        return false;
      }
      rethrow;
    }
  }

  /// Unseals the hardware-wrapped Master Key using Android Keystore `BiometricPrompt.CryptoObject`.
  /// Rejects legacy unencrypted entries (`!startsWith('v2_hw:')`) and triggers re-enrollment.
  Future<Uint8List?> unlockWithHardwareBiometricKey({
    String reason = 'Scan fingerprint to unlock Filo vault',
  }) async {
    final stored = await _secureStorage.read(key: _keyBiometricMasterKey);
    if (stored == null || stored.isEmpty) return null;

    if (_useHardwareKeystore) {
      if (!stored.startsWith(_hwBiometricPrefix)) {
        await deleteBiometricMasterKey();
        throw StateError('BIOMETRIC_REENROLL_REQUIRED');
      }

      try {
        final unsealedBase64 = await _securityChannel.invokeMethod<String>(
          'unsealBiometricKey',
          {
            'wrappedBlob': stored,
            'reason': reason,
          },
        );
        if (unsealedBase64 == null || unsealedBase64.isEmpty) {
          return null;
        }
        return Uint8List.fromList(base64Decode(unsealedBase64));
      } on PlatformException catch (e) {
        if (e.code == 'BIOMETRIC_REENROLL_REQUIRED') {
          await deleteBiometricMasterKey();
          throw StateError('BIOMETRIC_REENROLL_REQUIRED');
        }
        if (e.code == 'BIOMETRIC_CANCELED') {
          return null;
        }
        rethrow;
      } on MissingPluginException {
        if (_isFlutterTest) {
          return null;
        }
        rethrow;
      }
    }

    if (stored.startsWith(_hwBiometricPrefix)) {
      return null;
    }
    return Uint8List.fromList(base64Decode(stored));
  }

  /// Checks whether any legacy plaintext biometric credential exists on Android
  /// without hardware Keystore binding; clears it and disables biometric unlock.
  /// Returns `true` if a legacy/missing credential was cleared.
  Future<bool> clearLegacyBiometricKeyIfUnbound() async {
    if (!_useHardwareKeystore) return false;
    final stored = await _secureStorage.read(key: _keyBiometricMasterKey);
    if (stored == null ||
        stored.isEmpty ||
        !stored.startsWith(_hwBiometricPrefix)) {
      await deleteBiometricMasterKey();
      await setBiometricEnabled(false);
      return true;
    }
    return false;
  }

  /// Securely stores the derived Master Key in non-Android secure storage (e.g. iOS Keychain)
  /// or test mocks for quick biometric unlock.
  Future<void> storeBiometricMasterKey(Uint8List masterKey) async {
    await _secureStorage.write(
      key: _keyBiometricMasterKey,
      value: base64Encode(masterKey),
    );
  }

  /// Retrieves the Master Key stored for biometric unlock (non-Android / test fallback).
  Future<Uint8List?> getBiometricMasterKey() async {
    final b64 = await _secureStorage.read(key: _keyBiometricMasterKey);
    if (b64 == null || b64.isEmpty) return null;
    if (_useHardwareKeystore) {
      if (!b64.startsWith(_hwBiometricPrefix)) {
        await deleteBiometricMasterKey();
      }
      return null;
    }
    if (b64.startsWith(_hwBiometricPrefix)) return null;
    return Uint8List.fromList(base64Decode(b64));
  }

  /// Deletes the biometric Master Key and hardware Keystore alias upon logout,
  /// wipe, invalidation, or biometric toggle off.
  Future<void> deleteBiometricMasterKey() async {
    await _secureStorage.delete(key: _keyBiometricMasterKey);
    await _deleteHardwareKeystoreAlias();
  }

  Future<void> _deleteHardwareKeystoreAlias() async {
    try {
      await _securityChannel.invokeMethod<bool>('deleteBiometricKey');
    } on MissingPluginException {
      // Non-fatal in unit tests or non-Android platforms
    } catch (_) {}
  }

  /// Checks if a biometric Master Key is currently enrolled in secure storage.
  Future<bool> hasBiometricMasterKey() async {
    final b64 = await _secureStorage.read(key: _keyBiometricMasterKey);
    return b64 != null && b64.isNotEmpty;
  }

  /// Exports the encrypted vault key bundle to embed into the cloud index snapshot.
  /// Zero-knowledge safe: all keys are AES-256-GCM encrypted under the user's passphrase/recovery key.
  Future<Map<String, dynamic>> exportVaultKeyBundle() async {
    final wrappedBundle = await _secureStorage.read(key: _keyWrappedBundle);
    final recoveryBundle = await _secureStorage.read(key: _keyRecoveryWrappedBundle);
    final recoveryHash = await _secureStorage.read(key: _keyRecoveryKeyHash);

    return {
      'wrappedBundle': wrappedBundle != null ? json.decode(wrappedBundle) : null,
      'recoveryBundle': recoveryBundle != null ? json.decode(recoveryBundle) : null,
      'recoveryKeyHash': recoveryHash,
    };
  }

  /// Imports an encrypted vault key bundle recovered from the cloud snapshot into local secure storage.
  /// Restores access on a reinstalled app or new device.
  Future<void> importVaultKeyBundle(Map<String, dynamic> data) async {
    if (data['vaultBundle'] != null) {
      await _secureStorage.write(
        key: _keyWrappedBundle,
        value: json.encode(data['vaultBundle']),
      );
    } else if (data['wrappedBundle'] != null) {
      await _secureStorage.write(
        key: _keyWrappedBundle,
        value: json.encode(data['wrappedBundle']),
      );
    }
    if (data['recoveryBundle'] != null) {
      await _secureStorage.write(
        key: _keyRecoveryWrappedBundle,
        value: json.encode(data['recoveryBundle']),
      );
    }
    if (data['recoveryKeyHash'] != null) {
      await _secureStorage.write(
        key: _keyRecoveryKeyHash,
        value: data['recoveryKeyHash'] as String,
      );
    }
  }

  /// Auto-lock timeout helpers
  Future<int> getAutoLockTimeoutMinutes() async {
    final val = await _secureStorage.read(key: _keyAutoLockTimeout);
    return val != null ? int.tryParse(val) ?? 5 : 5;
  }

  Future<void> setAutoLockTimeoutMinutes(int minutes) async {
    await _secureStorage.write(
      key: _keyAutoLockTimeout,
      value: minutes.toString(),
    );
  }

  /// Cloud Provider helpers
  Future<String?> getActiveCloudProvider() => _secureStorage.read(key: _keyActiveCloudProvider);
  Future<void> setActiveCloudProvider(String provider) => _secureStorage.write(key: _keyActiveCloudProvider, value: provider);

  /// Completely wipes local security storage, hardware Keystore biometric alias,
  /// and signs out of Telegram.
  Future<void> wipeLocalSecurity() async {
    await _secureStorage.deleteAll();
    await _deleteHardwareKeystoreAlias();
    await _storageBackend.signOut();
  }
}
