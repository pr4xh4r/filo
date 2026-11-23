import 'dart:math';
import 'dart:typed_data';
import 'hash_utils.dart';

/// Formatted emergency recovery key utilities for zero-knowledge disaster recovery.
class RecoveryKey {
  RecoveryKey._();

  /// Generates a human-friendly recovery key string (64 hex characters formatted in 8 groups of 8).
  /// E.g. "A1B2-C3D4-E5F6-7890-..."
  static String formatFromBytes(Uint8List bytes) {
    final hex = HashUtils.bytesToHex(bytes).toUpperCase();
    final chunks = <String>[];
    for (int i = 0; i < hex.length; i += 8) {
      final end = (i + 8 <= hex.length) ? i + 8 : hex.length;
      chunks.add(hex.substring(i, end));
    }
    return chunks.join('-');
  }

  /// Parses a formatted recovery key back into raw bytes.
  static Uint8List parseToBytes(String formattedKey) {
    final clean = formattedKey.replaceAll('-', '').replaceAll(' ', '').trim();
    return HashUtils.hexToBytes(clean);
  }

  /// Generates a fresh 256-bit recovery key.
  static String generate() {
    final random = Random.secure();
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = random.nextInt(256);
    }
    return formatFromBytes(bytes);
  }
}
