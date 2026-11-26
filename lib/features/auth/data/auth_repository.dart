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
  // BUG 5 FIX: Store a separate bundle wrapped with the recovery key as KEK
  static const _keyRecoveryWrappedBundle = 'filo_recovery_wrapped_bundle';
  static const _keyActiveCloudProvider = 'filo_active_cloud_provider';

  AuthRepository({
    required StorageBackend storageBackend,
    FlutterSecureStorage? secureStorage,
  })  : _storageBackend = storageBackend,
        _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
            );

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
    // 1. Generate 256-bit Master Key
    final masterKey = CryptoEngine.generateMasterKey();

    // 2. Generate Salt & derive KEK via Argon2id
    final salt = Argon2Kdf.generateSalt();
    final kek = await Argon2Kdf.deriveKey(
      passphrase: passphrase,
      salt: salt,
    );

    // 3. Wrap Master Key under passphrase KEK
    final bundle = await KeyWrapper.wrapKey(
      masterKey: masterKey,
      kek: kek,
      salt: salt,
    );

    // 4. BUG 5 FIX: Generate recovery key and wrap the SAME master key under it
    //    so users can actually recover their vault using this key.
    final recoveryKey = RecoveryKey.generate();
    final recoveryKeyBytes = RecoveryKey.parseToBytes(recoveryKey);
    final recoveryHash = HashUtils.sha256Hex(recoveryKeyBytes);

    // Use recovery key bytes directly as the 32-byte KEK
    final recoverySalt = Argon2Kdf.generateSalt();
    final recoveryBundle = await KeyWrapper.wrapKey(
      masterKey: masterKey,
      kek: recoveryKeyBytes, // 32 bytes of CSPRNG = valid AES-256 key
      salt: recoverySalt,
    );

    // 5. Persist all bundles to hardware secure storage atomically
    await _secureStorage.write(
      key: _keyWrappedBundle,
      value: json.encode(bundle.toJson()),
    );
    await _secureStorage.write(
      key: _keyRecoveryKeyHash,
      value: recoveryHash,
    );
    // BUG 5 FIX: Persist the recovery-wrapped bundle so recovery is actually possible
    await _secureStorage.write(
      key: _keyRecoveryWrappedBundle,
      value: json.encode(recoveryBundle.toJson()),
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

    // Verify the recovery key hash first
    final storedHash = await _secureStorage.read(key: _keyRecoveryKeyHash);
    final recoveryKeyBytes = RecoveryKey.parseToBytes(formattedRecoveryKey);
    final providedHash = HashUtils.sha256Hex(recoveryKeyBytes);

    if (storedHash != null && !HashUtils.constantTimeCompare(
      providedHash.codeUnits,
      storedHash.codeUnits,
    )) {
      throw Exception('Invalid recovery key.');
    }

    final bundle = WrappedKeyBundle.fromJson(
      json.decode(recoveryBundleJson) as Map<String, dynamic>,
    );

    return KeyWrapper.unwrapKey(bundle: bundle, kek: recoveryKeyBytes);
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

    // Derive old KEK and unwrap the master key first
    final oldKek = await Argon2Kdf.deriveKey(
      passphrase: currentPassphrase.trim(),
      salt: oldBundle.salt,
    );
    final masterKey = await KeyWrapper.unwrapKey(bundle: oldBundle, kek: oldKek);

    // Derive new KEK with fresh salt
    final newSalt = Argon2Kdf.generateSalt();
    final newKek = await Argon2Kdf.deriveKey(
      passphrase: newPassphrase.trim(),
      salt: newSalt,
    );

    // Wrap master key under new KEK
    final newBundle = await KeyWrapper.wrapKey(
      masterKey: masterKey,
      kek: newKek,
      salt: newSalt,
    );

    // Save updated passphrase bundle
    await _secureStorage.write(
      key: _keyWrappedBundle,
      value: json.encode(newBundle.toJson()),
    );
    // BUG 6 FIX: Recovery bundle stays valid — master key hasn't changed,
    // so the recovery-wrapped bundle still correctly unlocks the same master key.
    // No update needed for _keyRecoveryWrappedBundle or _keyRecoveryKeyHash.
  }

  /// Disaster recovery path: resets passphrase using the emergency recovery key.
  Future<void> resetPassphraseWithRecoveryKey({
    required String recoveryKey,
    required String newPassphrase,
  }) async {
    final masterKey = await unlockWithRecoveryKey(recoveryKey.trim());

    final newSalt = Argon2Kdf.generateSalt();
    final newKek = await Argon2Kdf.deriveKey(
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

  /// Completely wipes local security storage and signs out of Telegram.
  Future<void> wipeLocalSecurity() async {
    await _secureStorage.deleteAll();
    await _storageBackend.signOut();
  }
}
