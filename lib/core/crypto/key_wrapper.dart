import 'dart:typed_data';
import 'crypto_engine.dart';
import 'hash_utils.dart';

/// Wrapped Master Key container storing the ciphertext, wrap IV, and salt.
class WrappedKeyBundle {
  final Uint8List wrappedMasterKey;
  final Uint8List wrapIv;
  final Uint8List salt;

  const WrappedKeyBundle({
    required this.wrappedMasterKey,
    required this.wrapIv,
    required this.salt,
  });

  Map<String, String> toJson() {
    return {
      'wrappedMasterKey': HashUtils.bytesToHex(wrappedMasterKey),
      'wrapIv': HashUtils.bytesToHex(wrapIv),
      'salt': HashUtils.bytesToHex(salt),
    };
  }

  factory WrappedKeyBundle.fromJson(Map<String, dynamic> json) {
    return WrappedKeyBundle(
      wrappedMasterKey: HashUtils.hexToBytes(json['wrappedMasterKey'] as String),
      wrapIv: HashUtils.hexToBytes(json['wrapIv'] as String),
      salt: HashUtils.hexToBytes(json['salt'] as String),
    );
  }
}

/// Handles Master Key wrapping and re-wrapping under KEKs.
///
/// Zero-Knowledge principle:
/// Changing the user's passphrase only requires deriving a new KEK and re-wrapping
/// the 256-bit Master Key. The Master Key itself stays identical, so all files
/// stored in Telegram remain valid and DO NOT require re-encryption.
class KeyWrapper {
  KeyWrapper._();

  /// Wraps a Master Key with a Key Encryption Key (KEK).
  static Future<WrappedKeyBundle> wrapKey({
    required Uint8List masterKey,
    required Uint8List kek,
    required Uint8List salt,
  }) async {
    final wrapIv = CryptoEngine.generateIv();
    final encrypted = await CryptoEngine.encrypt(
      plaintext: masterKey,
      key: kek,
      customIv: wrapIv,
    );

    return WrappedKeyBundle(
      wrappedMasterKey: encrypted.toCombinedBytes(),
      wrapIv: wrapIv,
      salt: salt,
    );
  }

  /// Unwraps the Master Key using the Key Encryption Key (KEK).
  static Future<Uint8List> unwrapKey({
    required WrappedKeyBundle bundle,
    required Uint8List kek,
  }) async {
    return CryptoEngine.decryptBytes(
      combinedBytes: bundle.wrappedMasterKey,
      key: kek,
    );
  }

  /// Re-wraps an existing Master Key under a new KEK (for passphrase change).
  static Future<WrappedKeyBundle> rewrapKey({
    required WrappedKeyBundle oldBundle,
    required Uint8List oldKek,
    required Uint8List newKek,
    required Uint8List newSalt,
  }) async {
    // 1. Unwrap Master Key with old KEK
    final masterKey = await unwrapKey(
      bundle: oldBundle,
      kek: oldKek,
    );

    // 2. Wrap Master Key with new KEK and new salt
    return wrapKey(
      masterKey: masterKey,
      kek: newKek,
      salt: newSalt,
    );
  }
}
