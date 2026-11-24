import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/filo_radius.dart';

import 'filo_background.dart';

/// Backward-compatible alias for full-screen Ethereal Dawn mesh gradient.
typedef FiloAmbientBackground = FiloBackground;

///
/// Features:
/// - 20px Gaussian blur via `BackdropFilter`
/// - Multi-layered specular highlights (crisp semi-translucent white rim)
/// - Translucent milky optical glass over ethereal gradients
/// - Responsive Emil Kowalski spring scale (0.98x) with subtle haptic tap
/// - RepaintBoundary for silky 60/120fps performance
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
    this.blur = 20.0,
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
    final r = widget.borderRadius ?? FiloRadius.roundedXl;

    final defaultBorder = widget.border ??
        Border.all(
          color: Colors.white.withValues(alpha: 0.85),
          width: 1.2,
        );

    final defaultShadow = widget.boxShadow ??
        [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: const Color(0xFFFFD7CA).withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, 12),
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
                borderRadius: r,
                border: defaultBorder,
                color: widget.color ?? Colors.white.withValues(alpha: 0.72),
                gradient: widget.color == null
                    ? LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: 0.88),
                          Colors.white.withValues(alpha: 0.65),
                        ],
                      )
                    : null,
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
          HapticFeedback.selectionClick();
          setState(() => _isPressed = true);
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
