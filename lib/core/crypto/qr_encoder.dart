import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Minimal, self-contained ISO/IEC 18004 compliant QR Code generator in pure Dart.
///
/// Features:
/// - Supports 8-bit Byte Mode.
/// - Reed-Solomon Error Correction via GF(256) Galois Field polynomial division.
/// - Dynamic version selection from Version 1 (21x21) up to Version 20 (97x97).
/// - Proper finder patterns, alignment patterns, timing tracks, and format information (Mask 0, EC Level L).
/// - Output directly usable by CustomPainter or rasterizers.
class QrEncoder {
  QrEncoder._();

  /// Formats an encrypted vault key bundle into a compact, QR-ready pairing payload string.
  static String formatPairingPayload(Map<String, dynamic> bundle) {
    if (bundle['wrappedBundle'] == null && bundle['vaultBundle'] == null) {
      throw const FormatException('Cannot export an unconfigured space.');
    }
    final jsonStr = json.encode(bundle);
    final compressedBytes = zlib.encode(utf8.encode(jsonStr));
    final b64 = base64Url.encode(compressedBytes);
    return 'filo://vault?bundle=$b64';
  }

  /// Parses a cross-device pairing token (filo://vault?bundle=..., filo://space?bundle=..., or raw JSON)
  /// with automatic base64 normalization, URI case tolerance, URL-decoding, and zlib decompression.
  static Map<String, dynamic> parsePairingToken(String rawToken) {
    var token = rawToken.trim();
    // Strip surrounding quotes if user pasted with quotes
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

  // Galois Field GF(256) tables for polynomial math
  static final List<int> _exp = List<int>.filled(512, 0);
  static final List<int> _log = List<int>.filled(256, 0);
  static bool _gfInitialized = false;

  static void _initGf() {
    if (_gfInitialized) return;
    int val = 1;
    for (int i = 0; i < 255; i++) {
      _exp[i] = val;
      _exp[i + 255] = val;
      _log[val] = i;
      val <<= 1;
      if (val >= 256) {
        val ^= 0x11D; // Primitive polynomial x^8 + x^4 + x^3 + x^2 + 1
      }
    }
    _gfInitialized = true;
  }

  static int _gfMul(int a, int b) {
    if (a == 0 || b == 0) return 0;
    return _exp[_log[a] + _log[b]];
  }

  static List<int> _calcEcPolynomial(int numEc) {
    List<int> poly = [1];
    for (int i = 0; i < numEc; i++) {
      final factor = [1, _exp[i]];
      final newPoly = List<int>.filled(poly.length + 1, 0);
      for (int j = 0; j < poly.length; j++) {
        newPoly[j] ^= _gfMul(poly[j], factor[0]);
        newPoly[j + 1] ^= _gfMul(poly[j], factor[1]);
      }
      poly = newPoly;
    }
    return poly;
  }

  static List<int> _calcReedSolomon(List<int> data, int numEc) {
    _initGf();
    final poly = _calcEcPolynomial(numEc);
    final remainder = List<int>.filled(numEc, 0);

    for (int i = 0; i < data.length; i++) {
      final factor = data[i] ^ remainder[0];
      for (int j = 0; j < numEc - 1; j++) {
        remainder[j] = remainder[j + 1];
      }
      remainder[numEc - 1] = 0;
      if (factor != 0) {
        for (int j = 0; j < numEc; j++) {
          remainder[j] ^= _gfMul(poly[j + 1], factor);
        }
      }
    }
    return remainder;
  }

  // Version table for EC Level L: [version, totalCodewords, dataCodewords, ecCodewordsPerBlock, numBlocksGroup1, dataCodewordsG1, numBlocksG2, dataCodewordsG2]
  static const List<List<int>> _versionTableL = [
    // [V, Total, Data, EC_per_block, G1_blocks, G1_data, G2_blocks, G2_data]
    [1, 26, 19, 7, 1, 19, 0, 0],
    [2, 44, 34, 10, 1, 34, 0, 0],
    [3, 70, 55, 15, 1, 55, 0, 0],
    [4, 100, 80, 20, 1, 80, 0, 0],
    [5, 134, 108, 26, 1, 108, 0, 0],
    [6, 172, 136, 18, 2, 68, 0, 0],
    [7, 196, 156, 20, 2, 78, 0, 0],
    [8, 242, 194, 24, 2, 97, 0, 0],
    [9, 292, 232, 30, 2, 116, 0, 0],
    [10, 346, 274, 18, 2, 68, 2, 69],
    [11, 404, 324, 20, 4, 81, 0, 0],
    [12, 466, 370, 24, 2, 92, 2, 93],
    [13, 532, 428, 26, 4, 107, 0, 0],
    [14, 581, 461, 30, 3, 115, 1, 116],
    [15, 655, 523, 22, 5, 87, 1, 88],
    [16, 733, 589, 24, 5, 98, 1, 99],
    [17, 815, 647, 28, 1, 107, 5, 108],
    [18, 901, 721, 30, 5, 120, 1, 121],
    [19, 991, 795, 28, 3, 113, 4, 114],
    [20, 1085, 861, 28, 3, 107, 5, 108],
  ];

  static const Map<int, List<int>> _alignmentCoords = {
    2: [6, 18],
    3: [6, 22],
    4: [6, 26],
    5: [6, 30],
    6: [6, 34],
    7: [6, 22, 38],
    8: [6, 24, 42],
    9: [6, 26, 46],
    10: [6, 28, 50],
    11: [6, 30, 54],
    12: [6, 32, 58],
    13: [6, 34, 62],
    14: [6, 26, 46, 66],
    15: [6, 26, 48, 70],
    16: [6, 26, 50, 74],
    17: [6, 30, 54, 78],
    18: [6, 30, 56, 82],
    19: [6, 30, 58, 86],
    20: [6, 34, 62, 90],
  };

  /// Generates a valid ISO 18004 boolean matrix for the given text.
  /// `true` = dark module, `false` = light module.
  static List<List<bool>> encode(String text) {
    final rawData = utf8.encode(text);
    final dataLen = rawData.length;

    // Pick smallest version that fits dataLen
    List<int>? versionRow;
    for (final row in _versionTableL) {
      final maxData = row[2];
      // 8-bit mode header: 4 bits mode + (version < 10 ? 8 : 16 bits count)
      final headerBits = (row[0] < 10) ? 12 : 20;
      final maxUsableBytes = maxData - ((headerBits + 7) ~/ 8);
      if (dataLen <= maxUsableBytes) {
        versionRow = row;
        break;
      }
    }

    versionRow ??= _versionTableL.last;

    final version = versionRow[0];
    final dataCodewords = versionRow[2];
    final ecPerBlock = versionRow[3];
    final g1Blocks = versionRow[4];
    final g1Data = versionRow[5];
    final g2Blocks = versionRow[6];
    final g2Data = versionRow[7];

    // 1. Bit buffer: mode + count + payload
    final bits = <bool>[];
    void addBits(int val, int count) {
      for (int i = count - 1; i >= 0; i--) {
        bits.add(((val >> i) & 1) == 1);
      }
    }

    // Byte mode indicator: 0100
    addBits(4, 4);
    // Character count indicator
    addBits(dataLen, version < 10 ? 8 : 16);
    // Payload bytes
    for (final b in rawData) {
      addBits(b, 8);
    }

    // Terminator (up to 4 zeroes)
    final capacityBits = dataCodewords * 8;
    final termLen = (capacityBits - bits.length).clamp(0, 4);
    for (int i = 0; i < termLen; i++) {
      bits.add(false);
    }

    // Pad to byte boundary
    while (bits.length % 8 != 0 && bits.length < capacityBits) {
      bits.add(false);
    }

    // Convert to bytes
    final dataBytes = <int>[];
    for (int i = 0; i < bits.length; i += 8) {
      int b = 0;
      for (int j = 0; j < 8; j++) {
        if (i + j < bits.length && bits[i + j]) {
          b |= (1 << (7 - j));
        }
      }
      dataBytes.add(b);
    }

    // Pad bytes alternating 0xEC, 0x11
    int padCount = 0;
    while (dataBytes.length < dataCodewords) {
      dataBytes.add((padCount % 2 == 0) ? 0xEC : 0x11);
      padCount++;
    }

    // 2. Divide into blocks and compute Reed-Solomon EC
    final blocks = <List<int>>[];
    final ecBlocks = <List<int>>[];
    int offset = 0;

    for (int i = 0; i < g1Blocks; i++) {
      final blk = dataBytes.sublist(offset, offset + g1Data);
      blocks.add(blk);
      ecBlocks.add(_calcReedSolomon(blk, ecPerBlock));
      offset += g1Data;
    }
    for (int i = 0; i < g2Blocks; i++) {
      final blk = dataBytes.sublist(offset, offset + g2Data);
      blocks.add(blk);
      ecBlocks.add(_calcReedSolomon(blk, ecPerBlock));
      offset += g2Data;
    }

    // 3. Interleave data codewords, then EC codewords
    final interleaved = <int>[];
    final maxDataBlockLen = g2Blocks > 0 ? g2Data : g1Data;
    for (int i = 0; i < maxDataBlockLen; i++) {
      for (final b in blocks) {
        if (i < b.length) interleaved.add(b[i]);
      }
    }
    for (int i = 0; i < ecPerBlock; i++) {
      for (final ec in ecBlocks) {
        if (i < ec.length) interleaved.add(ec[i]);
      }
    }

    // 4. Populate Matrix
    final dimension = 17 + 4 * version;
    final matrix = List.generate(dimension, (_) => List<bool>.filled(dimension, false));
    final reserved = List.generate(dimension, (_) => List<bool>.filled(dimension, false));

    // Place Finder Patterns
    _placeFinder(matrix, reserved, 0, 0, dimension);
    _placeFinder(matrix, reserved, dimension - 7, 0, dimension);
    _placeFinder(matrix, reserved, 0, dimension - 7, dimension);

    // Place Timing Tracks
    for (int i = 8; i < dimension - 8; i++) {
      final val = (i % 2 == 0);
      matrix[6][i] = val;
      reserved[6][i] = true;
      matrix[i][6] = val;
      reserved[i][6] = true;
    }

    // Place Alignment Patterns
    if (_alignmentCoords.containsKey(version)) {
      final coords = _alignmentCoords[version]!;
      for (final r in coords) {
        for (final c in coords) {
          if (!reserved[r][c]) {
            _placeAlignment(matrix, reserved, r, c);
          }
        }
      }
    }

    // Reserve Format Info Area
    for (int i = 0; i < 9; i++) {
      reserved[8][i] = true;
      reserved[i][8] = true;
      reserved[8][dimension - 1 - i] = true;
      reserved[dimension - 1 - i][8] = true;
    }
    // Dark module at (4*V + 9, 8)
    matrix[4 * version + 9][8] = true;
    reserved[4 * version + 9][8] = true;

    // 5. Place Data Bits in 2-column zig-zag from right to left
    final allBits = <bool>[];
    for (final b in interleaved) {
      for (int i = 7; i >= 0; i--) {
        allBits.add(((b >> i) & 1) == 1);
      }
    }

    int bitIdx = 0;
    int col = dimension - 1;
    bool upward = true;

    while (col > 0) {
      if (col == 6) col--; // Skip vertical timing column
      final rowStart = upward ? (dimension - 1) : 0;
      final rowEnd = upward ? -1 : dimension;
      final rowStep = upward ? -1 : 1;

      for (int r = rowStart; r != rowEnd; r += rowStep) {
        for (int c = 0; c < 2; c++) {
          final x = col - c;
          final y = r;
          if (!reserved[y][x]) {
            final bit = bitIdx < allBits.length ? allBits[bitIdx] : false;
            // Mask 0: (row + col) % 2 == 0
            final mask = (y + x) % 2 == 0;
            matrix[y][x] = bit ^ mask;
            bitIdx++;
          }
        }
      }
      upward = !upward;
      col -= 2;
    }

    // 6. Format Information (EC Level L = 01, Mask 0 = 000, 15 bits with mask 0x5412 = 0x77c4)
    const formatBits = 0x77c4;
    for (int i = 0; i < 15; i++) {
      final bit = ((formatBits >> i) & 1) == 1;
      // Top-left finder area
      if (i < 6) {
        matrix[8][i] = bit;
      } else if (i == 6) {
        matrix[8][7] = bit;
      } else if (i == 7) {
        matrix[8][8] = bit;
      } else if (i == 8) {
        matrix[7][8] = bit;
      } else {
        matrix[14 - i][8] = bit;
      }

      // Bottom-left / Top-right finder area
      if (i < 8) {
        matrix[dimension - 1 - i][8] = bit;
      } else {
        matrix[8][dimension - 15 + i] = bit;
      }
    }

    return matrix;
  }

  static void _placeFinder(List<List<bool>> matrix, List<List<bool>> reserved, int startX, int startY, int dim) {
    for (int y = -1; y <= 7; y++) {
      for (int x = -1; x <= 7; x++) {
        final px = startX + x;
        final py = startY + y;
        if (px >= 0 && px < dim && py >= 0 && py < dim) {
          reserved[py][px] = true;
          if (x >= 0 && x <= 6 && y >= 0 && y <= 6) {
            if (x == 0 || x == 6 || y == 0 || y == 6 || (x >= 2 && x <= 4 && y >= 2 && y <= 4)) {
              matrix[py][px] = true;
            } else {
              matrix[py][px] = false;
            }
          } else {
            matrix[py][px] = false; // 1-module white separator
          }
        }
      }
    }
  }

  static void _placeAlignment(List<List<bool>> matrix, List<List<bool>> reserved, int cy, int cx) {
    for (int y = -2; y <= 2; y++) {
      for (int x = -2; x <= 2; x++) {
        final py = cy + y;
        final px = cx + x;
        reserved[py][px] = true;
        if (x.abs() == 2 || y.abs() == 2 || (x == 0 && y == 0)) {
          matrix[py][px] = true;
        } else {
          matrix[py][px] = false;
        }
      }
    }
  }
}
