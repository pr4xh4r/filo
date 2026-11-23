import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/key_derivators/api.dart';
import 'package:pointycastle/key_derivators/argon2.dart';
import '../config/app_config.dart';

/// Password-based Key Derivation using Argon2id (RFC 9106 / PHC winner).
///
/// Features:
/// - Memory-hard, side-channel resistant derivation.
/// - Produces a 256-bit (32-byte) Key Encryption Key (KEK).
/// - Default configuration: 64 MB memory, 3 iterations, 4 parallelism lanes.
class Argon2Kdf {
  Argon2Kdf._();

  /// Derives a 32-byte key from a secret passphrase and salt.
  static Future<Uint8List> deriveKey({
    required String passphrase,
    required Uint8List salt,
    int memoryKiB = AppConfig.argon2MemoryKb,
    int iterations = AppConfig.argon2Iterations,
    int parallelism = AppConfig.argon2Parallelism,
    int keyLength = 32,
  }) async {
    final passwordBytes = Uint8List.fromList(utf8.encode(passphrase));

    final parameters = Argon2Parameters(
      Argon2Parameters.ARGON2_id,
      salt,
      desiredKeyLength: keyLength,
      iterations: iterations,
      memory: memoryKiB,
      lanes: parallelism,
      version: Argon2Parameters.ARGON2_VERSION_13,
    );

    final generator = Argon2BytesGenerator();
    generator.init(parameters);

    return generator.process(passwordBytes);
  }

  /// Generates a cryptographically secure random salt (default 16 bytes).
  static Uint8List generateSalt([int length = AppConfig.saltBytes]) {
    final secureRandom = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = secureRandom.nextInt(256);
    }
    return bytes;
  }
}
