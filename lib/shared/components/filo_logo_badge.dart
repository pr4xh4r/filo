import 'dart:ui';
import 'package:flutter/material.dart';

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

                // 3. Welcome Illustration Logo Emblem
                Positioned.fill(
                  child: Padding(
                    padding: EdgeInsets.all(size * 0.04),
                    child: Image.asset(
                      'assets/illustrations/welcome.png',
                      fit: BoxFit.contain,
                    ),
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
