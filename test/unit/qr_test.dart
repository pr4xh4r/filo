import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:filo/core/crypto/qr_encoder.dart';

Map<String, dynamic> parsePairingToken(String rawToken) {
  var token = rawToken.trim();
  // Strip quotes if user pasted with quotes
  if ((token.startsWith('"') && token.endsWith('"')) ||
      (token.startsWith("'") && token.endsWith("'"))) {
    token = token.substring(1, token.length - 1).trim();
  }

  // Handle URL schemes (case-insensitive check for filo://vault?bundle= or filo://space?bundle=)
  final uriLower = token.toLowerCase();
  String? rawB64;
  if (uriLower.startsWith('filo://vault?bundle=')) {
    rawB64 = token.substring('filo://vault?bundle='.length).trim();
  } else if (uriLower.startsWith('filo://space?bundle=')) {
    rawB64 = token.substring('filo://space?bundle='.length).trim();
  }

  if (rawB64 != null) {
    String cleanB64 = rawB64;
    // Decode percent-encoding if present
    if (cleanB64.contains('%')) {
      try {
        cleanB64 = Uri.decodeComponent(cleanB64);
      } catch (_) {}
    }
    // Normalize base64 padding
    final normalized = base64.normalize(
      cleanB64.replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', ''),
    );
    Uint8List decodedBytes;
    try {
      decodedBytes = Uint8List.fromList(base64Url.decode(normalized));
    } catch (_) {
      decodedBytes = Uint8List.fromList(base64.decode(normalized));
    }

    String jsonStr;
    try {
      jsonStr = utf8.decode(zlib.decode(decodedBytes));
    } catch (_) {
      jsonStr = utf8.decode(decodedBytes);
    }
    final data = json.decode(jsonStr) as Map<String, dynamic>;
    if (data['wrappedBundle'] == null && data['vaultBundle'] == null) {
      throw const FormatException('Token has no space key bundle configured.');
    }
    return data;
  }

  // Direct JSON fallback
  final data = json.decode(token) as Map<String, dynamic>;
  if (data['wrappedBundle'] == null && data['vaultBundle'] == null) {
    throw const FormatException('Token has no space key bundle configured.');
  }
  return data;
}

void main() {
  test('QrEncoder and bundle round-trip test', () {
    final mockBundle = {
      'wrappedBundle': {
        'cipherText': base64Encode(List.filled(32, 1)),
        'nonce': base64Encode(List.filled(12, 2)),
        'tag': base64Encode(List.filled(16, 3)),
        'salt': base64Encode(List.filled(16, 4)),
      },
      'recoveryBundle': {
        'cipherText': base64Encode(List.filled(32, 5)),
        'nonce': base64Encode(List.filled(12, 6)),
        'tag': base64Encode(List.filled(16, 7)),
        'salt': base64Encode(List.filled(16, 8)),
      },
      'recoveryKeyHash': 'a' * 64,
    };

    final jsonStr = json.encode(mockBundle);
    final compressedBytes = zlib.encode(utf8.encode(jsonStr));
    final b64 = base64Url.encode(compressedBytes);
    final pairingPayload = 'filo://vault?bundle=$b64';

    final matrix = QrEncoder.encode(pairingPayload);
    expect(matrix, isNotEmpty);
    expect(matrix.length, greaterThanOrEqualTo(21));

    // Test parse standard payload
    final parsed = parsePairingToken(pairingPayload);
    expect(parsed['wrappedBundle'], isNotNull);

    // Test parse uppercase URI scheme
    final upperPayload = 'FILO://VAULT?BUNDLE=$b64';
    final parsedUpper = parsePairingToken(upperPayload);
    expect(parsedUpper['wrappedBundle'], isNotNull);

    // Test parse direct JSON
    final parsedJson = parsePairingToken(jsonStr);
    expect(parsedJson['wrappedBundle'], isNotNull);

    // Test empty bundle throws clear error
    expect(
      () => parsePairingToken('{"wrappedBundle": null}'),
      throwsA(isA<FormatException>()),
    );
  });
}
