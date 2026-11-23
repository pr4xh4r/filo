import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import '../config/app_config.dart';

/// Encapsulates an authenticated encrypted ciphertext payload.
class EncryptedPayload {
  final Uint8List iv; // 12 bytes
  final Uint8List ciphertext;
  final Uint8List tag; // 16 bytes

  const EncryptedPayload({
    required this.iv,
    required this.ciphertext,
    required this.tag,
  });

  /// Serializes to a combined byte buffer: [IV (12B)] + [Ciphertext] + [Tag (16B)].
  Uint8List toCombinedBytes() {
    final builder = BytesBuilder(copy: false);
    builder.add(iv);
    builder.add(ciphertext);
    builder.add(tag);
    return builder.toBytes();
  }

  /// Deserializes from a combined byte buffer.
  factory EncryptedPayload.fromCombinedBytes(List<int> bytes) {
    if (bytes.length < AppConfig.aesGcmIvBytes + AppConfig.aesGcmTagBytes) {
      throw ArgumentError(
        'Payload is too short to contain valid IV and GCM authentication tag: length=${bytes.length}',
      );
    }
    final iv = Uint8List.fromList(bytes.sublist(0, AppConfig.aesGcmIvBytes));
    final tagStart = bytes.length - AppConfig.aesGcmTagBytes;
    final ciphertext = Uint8List.fromList(bytes.sublist(AppConfig.aesGcmIvBytes, tagStart));
    final tag = Uint8List.fromList(bytes.sublist(tagStart));

    return EncryptedPayload(
      iv: iv,
      ciphertext: ciphertext,
      tag: tag,
    );
  }
}

/// Core cryptographic engine for Filo implementing AES-256-GCM.
///
/// Principles:
/// - Authenticated Encryption with Associated Data (AEAD).
/// - 256-bit symmetric keys.
/// - Unique 96-bit (12-byte) IV for every chunk generated via CSPRNG.
/// - Verifiable integrity checks.
class CryptoEngine {
  CryptoEngine._();

  static final AesGcm _aesGcm = AesGcm.with256bits();

  /// Generates a new 256-bit (32-byte) Master Key using CSPRNG.
  static Uint8List generateMasterKey() {
    final secureRandom = Random.secure();
    final key = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      key[i] = secureRandom.nextInt(256);
    }
    return key;
  }

  /// Generates a 96-bit (12-byte) initialization vector.
  static Uint8List generateIv() {
    final secureRandom = Random.secure();
    final iv = Uint8List(AppConfig.aesGcmIvBytes);
    for (int i = 0; i < AppConfig.aesGcmIvBytes; i++) {
      iv[i] = secureRandom.nextInt(256);
    }
    return iv;
  }

  /// Encrypts plaintext bytes using AES-256-GCM.
  static Future<EncryptedPayload> encrypt({
    required List<int> plaintext,
    required List<int> key,
    List<int>? customIv,
    List<int>? associatedData,
  }) async {
    final iv = customIv != null
        ? Uint8List.fromList(customIv)
        : generateIv();

    final secretKey = SecretKey(key);
    final secretBox = await _aesGcm.encrypt(
      plaintext,
      secretKey: secretKey,
      nonce: iv,
      aad: associatedData ?? const <int>[],
    );

    return EncryptedPayload(
      iv: iv,
      ciphertext: Uint8List.fromList(secretBox.cipherText),
      tag: Uint8List.fromList(secretBox.mac.bytes),
    );
  }

  /// Decrypts an encrypted payload using AES-256-GCM.
  /// Throws [SecretBoxAuthenticationError] if tag verification fails.
  static Future<Uint8List> decrypt({
    required EncryptedPayload payload,
    required List<int> key,
    List<int>? associatedData,
  }) async {
    final secretKey = SecretKey(key);
    final secretBox = SecretBox(
      payload.ciphertext,
      nonce: payload.iv,
      mac: Mac(payload.tag),
    );

    final decrypted = await _aesGcm.decrypt(
      secretBox,
      secretKey: secretKey,
      aad: associatedData ?? const <int>[],
    );

    return Uint8List.fromList(decrypted);
  }

  /// Convenience method: Encrypts plaintext directly to combined byte buffer.
  static Future<Uint8List> encryptBytes({
    required List<int> plaintext,
    required List<int> key,
    List<int>? associatedData,
  }) async {
    final payload = await encrypt(
      plaintext: plaintext,
      key: key,
      associatedData: associatedData,
    );
    return payload.toCombinedBytes();
  }

  /// Convenience method: Decrypts combined byte buffer directly to plaintext.
  static Future<Uint8List> decryptBytes({
    required List<int> combinedBytes,
    required List<int> key,
    List<int>? associatedData,
  }) async {
    final payload = EncryptedPayload.fromCombinedBytes(combinedBytes);
    return decrypt(
      payload: payload,
      key: key,
      associatedData: associatedData,
    );
  }
}
