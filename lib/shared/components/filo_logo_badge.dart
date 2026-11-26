import 'package:flutter/material.dart';
import '../../core/theme/filo_typography.dart';

/// Minimal, text-only handwritten logo for Filo in the Ethereal Dawn aesthetic.
///
/// Features:
/// - True cursive handwriting typography using bundled 'Caveat' font.
/// - Ethereal dawn gradient styling (warm peach/coral apricot to obsidian ink / white).
/// - Diffused ambient warm glow.
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fontSize = size * 0.72;

    return RepaintBoundary(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: size * 0.15, vertical: size * 0.05),
        decoration: showGlow
            ? BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFFD7CA).withValues(alpha: isDark ? 0.25 : 0.60),
                    blurRadius: size * 0.45,
                    spreadRadius: size * 0.04,
                  ),
                ],
              )
            : null,
        child: ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? const [
                    Color(0xFFFFFFFF),
                    Color(0xFFFFD7CA),
                    Color(0xFFFFBBA8),
                  ]
                : const [
                    Color(0xFF1E1E2C),
                    Color(0xFF2E243B),
                    Color(0xFFFF6B4A),
                  ],
          ).createShader(bounds),
          child: Text(
            'filo',
            textAlign: TextAlign.center,
            style: FiloTypography.handwriting(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}
