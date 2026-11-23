import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/filo_radius.dart';

/// Apple iOS 18 / visionOS-inspired Liquid Glass surface.
///
/// Features:
/// - 20px Gaussian blur via `BackdropFilter`
/// - Multi-layered specular highlights (subtle 1px gradient stroke)
/// - Adaptive translucency in light and dark modes
/// - RepaintBoundary for 60/120fps GPU caching
class FiloGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? color;
  final double blur;
  final Border? border;
  final List<BoxShadow>? boxShadow;

  const FiloGlass({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.margin,
    this.color,
    this.blur = 20.0,
    this.border,
    this.boxShadow,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final r = borderRadius ?? FiloRadius.roundedXl;

    final defaultBg = isDark
        ? const Color(0xCC131B2E)
        : const Color(0xD9FFFFFF);

    final defaultBorder = border ??
        Border.all(
          color: isDark ? const Color(0x26FFFFFF) : const Color(0x26000000),
          width: 0.8,
        );

    final defaultShadow = boxShadow ??
        [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ];

    return RepaintBoundary(
      child: Container(
        margin: margin,
        decoration: BoxDecoration(
          borderRadius: r,
          boxShadow: defaultShadow,
        ),
        child: ClipRRect(
          borderRadius: r,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(
              padding: padding,
              decoration: BoxDecoration(
                color: color ?? defaultBg,
                borderRadius: r,
                border: defaultBorder,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
