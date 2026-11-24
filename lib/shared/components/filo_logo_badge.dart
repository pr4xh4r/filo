import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/filo_colors.dart';

/// Distinctive, Apple-grade app logo badge for Filo (Ethereal Dawn Frosted Glass Aesthetic).
///
/// Features:
/// - iOS continuous squircle curvature with frosted glass refraction and multi-stop pastel mesh.
/// - Custom-painted architectural "F" vault emblem in Deep Midnight Ink (#0F172A).
/// - Luminous coral peach (#FF6B4A) cryptographic eye.
/// - Specular glass highlight reflection & diffused peach drop glow.
class FiloLogoBadge extends StatelessWidget {
  final double size;
  final bool showGlow;

  const FiloLogoBadge({
    super.key,
    this.size = 88.0,
    this.showGlow = true,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(size * 0.28);

    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: showGlow
              ? [
                  BoxShadow(
                    color: const Color(0xFFFFD7CA).withValues(alpha: 0.55),
                    blurRadius: size * 0.35,
                    offset: Offset(0, size * 0.12),
                    spreadRadius: 2,
                  ),
                  BoxShadow(
                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                    blurRadius: size * 0.2,
                    offset: Offset(0, size * 0.08),
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Stack(
              children: [
                // 1. Ethereal Dawn Frosted Glass Monogram Background
                Container(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFFFE8DF), // Warm Apricot Glow
                        Color(0xFFFFF7F2), // Champagne Silk
                        Color(0xFFEFEAFF), // Arctic Lavender Refraction
                      ],
                      stops: [0.0, 0.45, 1.0],
                    ),
                  ),
                ),

                // 2. Liquid Glass Ambient Sheen / Specular Arc
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: size * 0.52,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white.withValues(alpha: 0.75),
                          Colors.white.withValues(alpha: 0.15),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // 3. Custom-Painted Geometric Vault Monogram ("F" Emblem)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _FiloLogoPainter(size: size),
                  ),
                ),

                // 4. Crisp Specular Glass Border Outline
                Container(
                  decoration: BoxDecoration(
                    borderRadius: borderRadius,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.9),
                      width: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom painter rendering the precision architectural Filo vault monogram.
class _FiloLogoPainter extends CustomPainter {
  final double size;

  const _FiloLogoPainter({required this.size});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final w = canvasSize.width;
    final h = canvasSize.height;

    // Paint for the primary Deep Midnight Ink architectural glyph
    final glyphPaint = Paint()
      ..color = FiloColors.primary
      ..style = PaintingStyle.fill;

    // Soft shadow behind glyph for frosted tactile depth
    final shadowPaint = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.14)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);

    // Coral peach accent paint for the cryptographic lock eye
    final coralPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFFF8566), Color(0xFFFF5233)],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    // Draw Architectural Vault "F" Geometry:
    // Vertical spine of "F" (rounded bar)
    final spineRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.27, h * 0.23, w * 0.15, h * 0.53),
      Radius.circular(w * 0.075),
    );

    // Top horizontal bar of "F" (vault roof extending right)
    final topBarRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.27, h * 0.23, w * 0.46, h * 0.14),
      Radius.circular(w * 0.07),
    );

    // Middle horizontal bar of "F" (shield key bar)
    final midBarRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.27, h * 0.43, w * 0.33, h * 0.13),
      Radius.circular(w * 0.065),
    );

    // Soft drop shadow under bars
    canvas.drawRRect(spineRect.shift(Offset(0, h * 0.015)), shadowPaint);
    canvas.drawRRect(topBarRect.shift(Offset(0, h * 0.015)), shadowPaint);
    canvas.drawRRect(midBarRect.shift(Offset(0, h * 0.015)), shadowPaint);

    // Primary glyph fill
    canvas.drawRRect(spineRect, glyphPaint);
    canvas.drawRRect(topBarRect, glyphPaint);
    canvas.drawRRect(midBarRect, glyphPaint);

    // Luminous vault eye / cryptographic dot (zero-knowledge vault lock)
    final dotCenter = Offset(w * 0.64, h * 0.65);
    final dotRadius = w * 0.075;

    // Outer coral glow
    final glowPaint = Paint()
      ..color = const Color(0xFFFF6B4A).withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5);
    canvas.drawCircle(dotCenter, dotRadius * 1.5, glowPaint);

    // Center radiant coral dot
    canvas.drawCircle(dotCenter, dotRadius, coralPaint);

    // Inner bright white pinpoint
    final whitePin = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(dotCenter, dotRadius * 0.4, whitePin);
  }

  @override
  bool shouldRepaint(covariant _FiloLogoPainter oldDelegate) =>
      oldDelegate.size != size;
}
