import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;

/// Cryptographic hash utilities for integrity verification and duplicate file detection.
class HashUtils {
  HashUtils._();

  /// Calculates SHA-256 checksum of a byte buffer.
  static String sha256Hex(List<int> bytes) {
    return crypto.sha256.convert(bytes).toString();
  }

  /// Calculates SHA-256 bytes.
  static Uint8List sha256Bytes(List<int> bytes) {
    return Uint8List.fromList(crypto.sha256.convert(bytes).bytes);
  }

  /// Calculates SHA-256 hash of a stream without loading the entire stream into memory.
  static Future<String> sha256Stream(Stream<List<int>> stream) async {
    final digest = await crypto.sha256.bind(stream).first;
    return digest.toString();
  }

  /// Compares two byte lists in constant time to prevent timing attacks.
  static bool constantTimeCompare(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// Formats byte sizes into human-readable strings (e.g. 1.2 GB, 450 KB).
  static String formatBytes(int bytes, {int decimals = 1}) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = (bytes > 0) ? (bytes.toString().length - 1) ~/ 3 : 0;
    if (i >= suffixes.length) i = suffixes.length - 1;
    // Calculate index accurately based on log1024
    int index = 0;
    double size = bytes.toDouble();
    while (size >= 1024.0 && index < suffixes.length - 1) {
      size /= 1024.0;
      index++;
    }
    return '${size.toStringAsFixed(index == 0 ? 0 : decimals)} ${suffixes[index]}';
  }

  /// Converts a hex string to Uint8List.
  static Uint8List hexToBytes(String hex) {
    final cleanHex = hex.replaceAll(' ', '').replaceAll('-', '');
    final bytes = <int>[];
    for (int i = 0; i < cleanHex.length; i += 2) {
      bytes.add(int.parse(cleanHex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }

  /// Converts Uint8List to hex string.
  static String bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
