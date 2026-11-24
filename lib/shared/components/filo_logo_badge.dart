import 'package:flutter/material.dart';

/// Distinctive, Apple-grade app logo badge for Filo.
///
/// Features:
/// - iOS continuous squircle curvature with multi-stop radial & linear gradients.
/// - Custom-painted geometric "F" vault emblem with cloud-safe aperture.
/// - Specular glass highlight reflection & diffused primary drop glow.
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
    final borderRadius = BorderRadius.circular(size * 0.26);

    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: showGlow
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: size * 0.35,
                    offset: Offset(0, size * 0.12),
                    spreadRadius: -2,
                  ),
                ]
              : null,
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Stack(
            children: [
              // 1. Deep Obsidian Titanium Monogram Background
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF0F0F12), // Deep Obsidian
                      Color(0xFF1E1E24), // Midnight Charcoal
                      Color(0xFF2B2B34), // Brushed Titanium
                    ],
                    stops: [0.0, 0.55, 1.0],
                  ),
                ),
              ),

              // 2. Liquid Glass Ambient Sheen / Specular Arc
              Positioned(
                top: -size * 0.2,
                left: -size * 0.2,
                right: -size * 0.2,
                height: size * 0.75,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: 0.32),
                        Colors.white.withValues(alpha: 0.05),
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

              // 4. Subtle Specular Border Outline
              Container(
                decoration: BoxDecoration(
                  borderRadius: borderRadius,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom painter rendering the precision geometric Filo vault monogram.
class _FiloLogoPainter extends CustomPainter {
  final double size;

  const _FiloLogoPainter({required this.size});

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final w = canvasSize.width;
    final h = canvasSize.height;

    // Paint for the primary white architectural glyph
    final glyphPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Subtle shadow behind glyph for 3D depth
    final shadowPaint = Paint()
      ..color = const Color(0xFF0F172A).withValues(alpha: 0.35)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    // Accent paint for the cyan vault beam
    final accentPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF67E8F9), Color(0xFF38BDF8)],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    // Draw Vault Geometry:
    // Vertical spine of "F" (rounded bar)
    final spineRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.27, h * 0.24, w * 0.15, h * 0.52),
      Radius.circular(w * 0.075),
    );

    // Top horizontal bar of "F" (vault roof extending right)
    final topBarRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.27, h * 0.24, w * 0.46, h * 0.14),
      Radius.circular(w * 0.07),
    );

    // Middle horizontal bar of "F" (shield key bar)
    final midBarRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.27, h * 0.44, w * 0.33, h * 0.13),
      Radius.circular(w * 0.065),
    );

    // Subtle drop shadow under bars
    canvas.drawRRect(spineRect.shift(Offset(0, h * 0.02)), shadowPaint);
    canvas.drawRRect(topBarRect.shift(Offset(0, h * 0.02)), shadowPaint);
    canvas.drawRRect(midBarRect.shift(Offset(0, h * 0.02)), shadowPaint);

    // Primary glyph fill
    canvas.drawRRect(spineRect, glyphPaint);
    canvas.drawRRect(topBarRect, glyphPaint);
    canvas.drawRRect(midBarRect, glyphPaint);

    // Luminous vault eye / cryptographic dot (representing zero-knowledge vault lock)
    final dotCenter = Offset(w * 0.64, h * 0.65);
    final dotRadius = w * 0.075;

    // Outer cyan glow
    final glowPaint = Paint()
      ..color = const Color(0xFF38BDF8).withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawCircle(dotCenter, dotRadius * 1.5, glowPaint);

    // Center radiant cyan dot
    canvas.drawCircle(dotCenter, dotRadius, accentPaint);

    // Inner bright white pinpoint
    final whitePin = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(dotCenter, dotRadius * 0.45, whitePin);
  }

  @override
  bool shouldRepaint(covariant _FiloLogoPainter oldDelegate) =>
      oldDelegate.size != size;
}
