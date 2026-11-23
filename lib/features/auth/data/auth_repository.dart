import 'dart:convert';
import 'dart:typed_data';
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

  static const _keyWrappedBundle = 'filo_wrapped_master_key';
  static const _keyBiometricEnabled = 'filo_biometric_enabled';
  static const _keyBiometricMasterKey = 'filo_biometric_master_key';
  static const _keyAutoLockTimeout = 'filo_auto_lock_timeout';
  static const _keyRecoveryKeyHash = 'filo_recovery_key_hash';

  AuthRepository({
    required StorageBackend storageBackend,
    FlutterSecureStorage? secureStorage,
  })  : _storageBackend = storageBackend,
        _secureStorage = secureStorage ?? const FlutterSecureStorage();

  StorageBackend get storageBackend => _storageBackend;

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
    // 1. Generate 256-bit Master Key
    final masterKey = CryptoEngine.generateMasterKey();

    // 2. Generate Salt & derive KEK via Argon2id
    final salt = Argon2Kdf.generateSalt();
    final kek = await Argon2Kdf.deriveKey(
      passphrase: passphrase,
      salt: salt,
    );

    // 3. Wrap Master Key
    final bundle = await KeyWrapper.wrapKey(
      masterKey: masterKey,
      kek: kek,
      salt: salt,
    );

    // 4. Generate Emergency Recovery Key and record its hash for recovery verification
    final recoveryKey = RecoveryKey.generate();
    final recoveryHash = HashUtils.sha256Hex(RecoveryKey.parseToBytes(recoveryKey));

    // 5. Persist to hardware secure storage
    await _secureStorage.write(
      key: _keyWrappedBundle,
      value: json.encode(bundle.toJson()),
    );
    await _secureStorage.write(
      key: _keyRecoveryKeyHash,
      value: recoveryHash,
    );

    return recoveryKey;
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

    // Derive KEK with stored salt
    final kek = await Argon2Kdf.deriveKey(
      passphrase: passphrase,
      salt: bundle.salt,
    );

    // Unwrap Master Key
    return KeyWrapper.unwrapKey(bundle: bundle, kek: kek);
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

    // Derive old KEK
    final oldKek = await Argon2Kdf.deriveKey(
      passphrase: currentPassphrase,
      salt: oldBundle.salt,
    );

    // Derive new KEK with fresh salt
    final newSalt = Argon2Kdf.generateSalt();
    final newKek = await Argon2Kdf.deriveKey(
      passphrase: newPassphrase,
      salt: newSalt,
    );

    // Rewrap Master Key
    final newBundle = await KeyWrapper.rewrapKey(
      oldBundle: oldBundle,
      oldKek: oldKek,
      newKek: newKek,
      newSalt: newSalt,
    );

    // Save updated bundle
    await _secureStorage.write(
      key: _keyWrappedBundle,
      value: json.encode(newBundle.toJson()),
    );
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

  /// Securely stores the derived Master Key in hardware-backed keystore
  /// for quick biometric unlock.
  Future<void> storeBiometricMasterKey(Uint8List masterKey) async {
    await _secureStorage.write(
      key: _keyBiometricMasterKey,
      value: base64Encode(masterKey),
    );
  }

  /// Retrieves the Master Key stored for biometric unlock.
  Future<Uint8List?> getBiometricMasterKey() async {
    final b64 = await _secureStorage.read(key: _keyBiometricMasterKey);
    if (b64 == null || b64.isEmpty) return null;
    return Uint8List.fromList(base64Decode(b64));
  }

  /// Deletes the biometric Master Key upon logout, wipe, or biometric toggle off.
  Future<void> deleteBiometricMasterKey() async {
    await _secureStorage.delete(key: _keyBiometricMasterKey);
  }

  /// Checks if a biometric Master Key is currently enrolled in secure storage.
  Future<bool> hasBiometricMasterKey() async {
    final b64 = await _secureStorage.read(key: _keyBiometricMasterKey);
    return b64 != null && b64.isNotEmpty;
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

  /// Completely wipes local security storage and signs out of Telegram.
  Future<void> wipeLocalSecurity() async {
    await _secureStorage.deleteAll();
    await _storageBackend.signOut();
  }
}
