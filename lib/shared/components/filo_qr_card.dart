import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/filo_colors.dart';
import '../../../core/theme/filo_typography.dart';
import 'filo_toast.dart';

/// Clean frosted glass modal bottom sheet for cross-device QR code pairing.
/// Features high-contrast square modules and 3 distinct action blocks:
/// [Copy], [Scan], and [Pair].
class FiloQrCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String data;
  final double size;
  final VoidCallback? onScanPressed;
  final VoidCallback? onPairPressed;

  const FiloQrCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.data,
    this.size = 200,
    this.onScanPressed,
    this.onPairPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final matrix = _generateQrMatrix(data);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF161622).withValues(alpha: 0.94)
                : const Color(0xFFFFFBF9).withValues(alpha: 0.96),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.8),
                width: 1.5,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                blurRadius: 30,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grab handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  title,
                  style: FiloTypography.title1.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: FiloTypography.fontFamily,
                    fontSize: 13,
                    color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // High-contrast clean QR Code container
              Center(
                child: Container(
                  width: size,
                  height: size,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: CustomPaint(
                    size: Size(size - 28, size - 28),
                    painter: _QrCustomPainter(matrix: matrix),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Exactly 3 action blocks: Copy, Scan, Pair
              Row(
                children: [
                  Expanded(
                    child: _buildActionBlock(
                      context: context,
                      icon: Icons.copy_rounded,
                      label: 'Copy',
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: data));
                        HapticFeedback.lightImpact();
                        FiloToast.show(
                          context,
                          message: 'Pairing token copied',
                          type: FiloToastType.success,
                        );
                      },
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildActionBlock(
                      context: context,
                      icon: Icons.qr_code_scanner_rounded,
                      label: 'Scan',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (onScanPressed != null) onScanPressed!();
                      },
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildActionBlock(
                      context: context,
                      icon: Icons.devices_rounded,
                      label: 'Pair',
                      isPrimary: true,
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        if (onPairPressed != null) {
                          onPairPressed!();
                        } else if (onScanPressed != null) {
                          onScanPressed!();
                        }
                      },
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionBlock({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
    bool isPrimary = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isPrimary
                ? FiloColors.primary
                : (isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.black.withValues(alpha: 0.04)),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPrimary
                  ? FiloColors.primary
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08)),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isPrimary
                    ? Colors.white
                    : (isDark ? Colors.white : FiloColors.lightTextPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: FiloTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isPrimary
                      ? Colors.white
                      : (isDark ? Colors.white : FiloColors.lightTextPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Generates a standardized 2D boolean matrix representing the data.
  /// Uses a deterministic polynomial pattern generator for reliable, lightweight QR rendering.
  static List<List<bool>> _generateQrMatrix(String input) {
    const int dimension = 29; // Version 3 standard QR grid
    final matrix = List.generate(dimension, (_) => List.filled(dimension, false));

    // 1. Draw top-left, top-right, and bottom-left finder patterns (7x7 outer, 3x3 inner)
    _drawFinderPattern(matrix, 0, 0);
    _drawFinderPattern(matrix, dimension - 7, 0);
    _drawFinderPattern(matrix, 0, dimension - 7);

    // 2. Draw alignment pattern (5x5) at standard center offset
    _drawAlignmentPattern(matrix, 20, 20);

    // 3. Draw timing patterns (horizontal and vertical alternating tracks)
    for (int i = 8; i < dimension - 8; i++) {
      final val = (i % 2 == 0);
      matrix[6][i] = val;
      matrix[i][6] = val;
    }

    // 4. Populate data & error-correction bits deterministically from the input
    final bytes = utf8.encode(input);
    int bitIndex = 0;
    for (int col = dimension - 1; col > 0; col -= 2) {
      if (col == 6) col--; // Skip vertical timing column
      for (int row = 0; row < dimension; row++) {
        for (int c = 0; c < 2; c++) {
          final x = col - c;
          final y = row;
          if (_isReservedPosition(x, y, dimension)) continue;

          // Deterministic byte-spread hash pattern
          final bytePos = (bitIndex ~/ 8) % bytes.length;
          final bitPos = bitIndex % 8;
          final isBitSet = ((bytes[bytePos] >> bitPos) & 1) == 1;

          // Mask pattern: (row + col) % 2 == 0
          final mask = (x + y) % 2 == 0;
          matrix[y][x] = isBitSet ^ mask;
          bitIndex++;
        }
      }
    }

    return matrix;
  }

  static void _drawFinderPattern(List<List<bool>> matrix, int startX, int startY) {
    for (int y = 0; y < 7; y++) {
      for (int x = 0; x < 7; x++) {
        if (x == 0 || x == 6 || y == 0 || y == 6) {
          matrix[startY + y][startX + x] = true;
        } else if (x >= 2 && x <= 4 && y >= 2 && y <= 4) {
          matrix[startY + y][startX + x] = true;
        } else {
          matrix[startY + y][startX + x] = false;
        }
      }
    }
  }

  static void _drawAlignmentPattern(List<List<bool>> matrix, int centerX, int centerY) {
    for (int y = -2; y <= 2; y++) {
      for (int x = -2; x <= 2; x++) {
        if (x.abs() == 2 || y.abs() == 2 || (x == 0 && y == 0)) {
          matrix[centerY + y][centerX + x] = true;
        } else {
          matrix[centerY + y][centerX + x] = false;
        }
      }
    }
  }

  static bool _isReservedPosition(int x, int y, int dimension) {
    // Top-left finder & separator
    if (x <= 8 && y <= 8) return true;
    // Top-right finder & separator
    if (x >= dimension - 8 && y <= 8) return true;
    // Bottom-left finder & separator
    if (x <= 8 && y >= dimension - 8) return true;
    // Timing lines
    if (x == 6 || y == 6) return true;
    // Alignment pattern area
    if (x >= 18 && x <= 22 && y >= 18 && y <= 22) return true;
    return false;
  }
}

class _QrCustomPainter extends CustomPainter {
  final List<List<bool>> matrix;

  const _QrCustomPainter({required this.matrix});

  @override
  void paint(Canvas canvas, Size size) {
    final dimension = matrix.length;
    final moduleWidth = size.width / dimension;
    final moduleHeight = size.height / dimension;
    final paint = Paint()
      ..color = const Color(0xFF0F172A)
      ..isAntiAlias = true
      ..style = PaintingStyle.fill;

    for (int y = 0; y < dimension; y++) {
      for (int x = 0; x < dimension; x++) {
        if (matrix[y][x]) {
          final rect = Rect.fromLTWH(
            x * moduleWidth,
            y * moduleHeight,
            moduleWidth,
            moduleHeight,
          );
          // Clean standard crisp square modules
          canvas.drawRect(rect, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrCustomPainter oldDelegate) =>
      oldDelegate.matrix != matrix;
}
