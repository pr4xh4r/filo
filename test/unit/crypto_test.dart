import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:filo/core/crypto/crypto_engine.dart';
import 'package:filo/core/crypto/argon2_kdf.dart';
import 'package:filo/core/crypto/key_wrapper.dart';
import 'package:filo/core/crypto/hash_utils.dart';
import 'package:filo/core/crypto/recovery_key.dart';

void main() {
  group('CryptoEngine (AES-256-GCM)', () {
    test('Encrypt and decrypt round-trip with arbitrary payload', () async {
      final key = CryptoEngine.generateMasterKey();
      final plaintext = utf8.encode('Hello, Filo Zero-Knowledge World!');

      final encrypted = await CryptoEngine.encrypt(
        plaintext: plaintext,
        key: key,
      );

      expect(encrypted.iv.length, 12);
      expect(encrypted.tag.length, 16);
      expect(encrypted.ciphertext.isNotEmpty, true);

      final decrypted = await CryptoEngine.decrypt(
        payload: encrypted,
        key: key,
      );

      expect(utf8.decode(decrypted), 'Hello, Filo Zero-Knowledge World!');
    });

    test('Combined bytes serialization and deserialization', () async {
      final key = CryptoEngine.generateMasterKey();
      final plaintext = utf8.encode('Streaming chunk payload verification');

      final combinedBytes = await CryptoEngine.encryptBytes(
        plaintext: plaintext,
        key: key,
      );

      final decrypted = await CryptoEngine.decryptBytes(
        combinedBytes: combinedBytes,
        key: key,
      );

      expect(utf8.decode(decrypted), 'Streaming chunk payload verification');
    });

    test('MAC validation fails if ciphertext is tampered', () async {
      final key = CryptoEngine.generateMasterKey();
      final plaintext = utf8.encode('Sensitive financial ledger');

      final encrypted = await CryptoEngine.encrypt(
        plaintext: plaintext,
        key: key,
      );

      // Tamper 1 byte of ciphertext
      final tamperedCiphertext = Uint8List.fromList(encrypted.ciphertext);
      tamperedCiphertext[0] ^= 0xFF;

      final tamperedPayload = EncryptedPayload(
        iv: encrypted.iv,
        ciphertext: tamperedCiphertext,
        tag: encrypted.tag,
      );

      expect(
        () async => await CryptoEngine.decrypt(
          payload: tamperedPayload,
          key: key,
        ),
        throwsA(anything),
      );
    });

    test('Decryption with wrong key fails MAC check', () async {
      final key1 = CryptoEngine.generateMasterKey();
      final key2 = CryptoEngine.generateMasterKey();
      final plaintext = utf8.encode('Top Secret Document');

      final combinedBytes = await CryptoEngine.encryptBytes(
        plaintext: plaintext,
        key: key1,
      );

      expect(
        () async => await CryptoEngine.decryptBytes(
          combinedBytes: combinedBytes,
          key: key2,
        ),
        throwsA(anything),
      );
    });
  });

  group('Argon2Kdf', () {
    test('Argon2id produces deterministic 32-byte key for identical inputs', () async {
      final salt = Argon2Kdf.generateSalt();
      const passphrase = 'SuperSecretUserPassphrase123!';

      // Use lighter parameters in unit tests for fast execution
      final key1 = await Argon2Kdf.deriveKey(
        passphrase: passphrase,
        salt: salt,
        memoryKiB: 1024,
        iterations: 2,
        parallelism: 2,
      );

      final key2 = await Argon2Kdf.deriveKey(
        passphrase: passphrase,
        salt: salt,
        memoryKiB: 1024,
        iterations: 2,
        parallelism: 2,
      );

      expect(key1.length, 32);
      expect(key2.length, 32);
      expect(HashUtils.bytesToHex(key1), HashUtils.bytesToHex(key2));
    });

    test('Different salts produce completely different derived keys', () async {
      final salt1 = Argon2Kdf.generateSalt();
      final salt2 = Argon2Kdf.generateSalt();
      const passphrase = 'ConsistentPassphrase';

      final key1 = await Argon2Kdf.deriveKey(
        passphrase: passphrase,
        salt: salt1,
        memoryKiB: 1024,
        iterations: 1,
      );

      final key2 = await Argon2Kdf.deriveKey(
        passphrase: passphrase,
        salt: salt2,
        memoryKiB: 1024,
        iterations: 1,
      );

      expect(HashUtils.bytesToHex(key1) != HashUtils.bytesToHex(key2), true);
    });
  });

  group('KeyWrapper & Passphrase Change', () {
    test('Wrap and unwrap Master Key with KEK', () async {
      final masterKey = CryptoEngine.generateMasterKey();
      final salt = Argon2Kdf.generateSalt();
      final kek = await Argon2Kdf.deriveKey(
        passphrase: 'InitialPassphrase',
        salt: salt,
        memoryKiB: 1024,
        iterations: 1,
      );

      final bundle = await KeyWrapper.wrapKey(
        masterKey: masterKey,
        kek: kek,
        salt: salt,
      );

      final recoveredMasterKey = await KeyWrapper.unwrapKey(
        bundle: bundle,
        kek: kek,
      );

      expect(HashUtils.bytesToHex(recoveredMasterKey), HashUtils.bytesToHex(masterKey));
    });

    test('Rewrap Master Key on Passphrase Change without changing Master Key', () async {
      final masterKey = CryptoEngine.generateMasterKey();
      final oldSalt = Argon2Kdf.generateSalt();
      final newSalt = Argon2Kdf.generateSalt();

      final oldKek = await Argon2Kdf.deriveKey(
        passphrase: 'OldPassphrase',
        salt: oldSalt,
        memoryKiB: 1024,
        iterations: 1,
      );

      final newKek = await Argon2Kdf.deriveKey(
        passphrase: 'NewStrongPassphrase2026!',
        salt: newSalt,
        memoryKiB: 1024,
        iterations: 1,
      );

      final initialBundle = await KeyWrapper.wrapKey(
        masterKey: masterKey,
        kek: oldKek,
        salt: oldSalt,
      );

      // User changes passphrase
      final rewrappedBundle = await KeyWrapper.rewrapKey(
        oldBundle: initialBundle,
        oldKek: oldKek,
        newKek: newKek,
        newSalt: newSalt,
      );

      // Verify old KEK fails to unwrap
      expect(
        () async => await KeyWrapper.unwrapKey(bundle: rewrappedBundle, kek: oldKek),
        throwsA(anything),
      );

      // Verify new KEK successfully unwraps the exact same Master Key!
      final recoveredMasterKey = await KeyWrapper.unwrapKey(
        bundle: rewrappedBundle,
        kek: newKek,
      );

      expect(HashUtils.bytesToHex(recoveredMasterKey), HashUtils.bytesToHex(masterKey));
    });
  });

  group('RecoveryKey & HashUtils', () {
    test('RecoveryKey format and parse round-trip', () {
      final formatted = RecoveryKey.generate();
      expect(formatted.contains('-'), true);
      expect(formatted.split('-').length, 8); // 8 groups

      final bytes = RecoveryKey.parseToBytes(formatted);
      expect(bytes.length, 32);

      final reFormatted = RecoveryKey.formatFromBytes(bytes);
      expect(reFormatted, formatted);
    });

    test('HashUtils sha256 and constant time compare', () {
      final data = utf8.encode('Data integrity test');
      final hash = HashUtils.sha256Hex(data);
      expect(hash.length, 64);

      final a = [1, 2, 3, 4];
      final b = [1, 2, 3, 4];
      final c = [1, 2, 3, 5];
      expect(HashUtils.constantTimeCompare(a, b), true);
      expect(HashUtils.constantTimeCompare(a, c), false);

      expect(HashUtils.formatBytes(500), '500 B');
      expect(HashUtils.formatBytes(1024 * 500), '500.0 KB');
      expect(HashUtils.formatBytes(1024 * 1024 * 15), '15.0 MB');
      expect(HashUtils.formatBytes(1024 * 1024 * 1024 * 2), '2.0 GB');
    });
  });
}
