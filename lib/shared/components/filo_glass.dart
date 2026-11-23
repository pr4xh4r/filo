import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/filo_colors.dart';
import '../../core/theme/filo_radius.dart';

/// Apple iOS 18 / visionOS-inspired Liquid Glass surface.
///
/// Features:
/// - 24px Gaussian blur via `BackdropFilter`
/// - Multi-layered specular highlights (top-left light reflection, bottom-right ambient tint)
/// - Adaptive translucency in light (milk-glass) and dark (CRED obsidian-glass) modes
/// - Responsive press feedback (Emil Kowalski spring scale 0.98x) with haptics
/// - RepaintBoundary for 60/120fps GPU performance
class FiloGlass extends StatefulWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double blur;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;

  const FiloGlass({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.margin,
    this.color,
    this.blur = 24.0,
    this.border,
    this.boxShadow,
    this.onTap,
  });

  @override
  State<FiloGlass> createState() => _FiloGlassState();
}

class _FiloGlassState extends State<FiloGlass> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = widget.borderRadius ?? FiloRadius.roundedXl;

    final defaultBg = isDark
        ? const Color(0xCC0F0B26)
        : const Color(0xE6FFFFFF);

    final defaultBorder = widget.border ??
        Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.65),
          width: 1.0,
        );

    final defaultShadow = widget.boxShadow ??
        [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.45)
                : const Color(0xFF5E6CE7).withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ];

    Widget content = RepaintBoundary(
      child: Container(
        margin: widget.margin,
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: defaultShadow,
        ),
        child: ClipRRect(
          borderRadius: r,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
            child: Container(
              padding: widget.padding,
              decoration: BoxDecoration(
                color: widget.color ?? defaultBg,
                borderRadius: r,
                border: defaultBorder,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          Colors.white.withValues(alpha: 0.08),
                          Colors.white.withValues(alpha: 0.02),
                        ]
                      : [
                          Colors.white.withValues(alpha: 0.85),
                          Colors.white.withValues(alpha: 0.45),
                        ],
                ),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );

    if (widget.onTap != null) {
      return GestureDetector(
        onTapDown: (_) {
          setState(() => _isPressed = true);
          HapticFeedback.lightImpact();
        },
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          child: content,
        ),
      );
    }

    return content;
  }
}

/// Ambient Dreamlike Mesh Background (matching Image 5 in light mode, CRED in dark mode)
class FiloAmbientBackground extends StatelessWidget {
  final Widget child;

  const FiloAmbientBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // Base Canvas
        Container(
          color: isDark ? FiloColors.darkBackground : FiloColors.lightBackground,
        ),

        // Ambient Dreamy Mesh Glow 1 (Top-Right: Electric Indigo)
        Positioned(
          top: -120,
          right: -80,
          width: 380,
          height: 380,
          child: RepaintBoundary(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: isDark
                      ? [
                          const Color(0xFF5E6CE7).withValues(alpha: 0.28),
                          Colors.transparent,
                        ]
                      : [
                          const Color(0xFFC645F9).withValues(alpha: 0.16),
                          Colors.transparent,
                        ],
                ),
              ),
            ),
          ),
        ),

        // Ambient Dreamy Mesh Glow 2 (Bottom-Left: Neon Orchid)
        Positioned(
          bottom: -100,
          left: -80,
          width: 360,
          height: 360,
          child: RepaintBoundary(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: isDark
                      ? [
                          const Color(0xFFC645F9).withValues(alpha: 0.22),
                          Colors.transparent,
                        ]
                      : [
                          const Color(0xFF5E6CE7).withValues(alpha: 0.14),
                          Colors.transparent,
                        ],
                ),
              ),
            ),
          ),
        ),

        // Child Content
        child,
      ],
    );
  }
}
