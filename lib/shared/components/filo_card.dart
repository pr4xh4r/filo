import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/filo_radius.dart';
import '../../core/theme/filo_spacing.dart';
import 'filo_glass.dart';

/// Liquid Glass Card container component with specular highlights,
/// adaptive blur, and spring press feedback.
class FiloCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? backgroundColor;
  final Color? borderColor;
  final BorderRadius? borderRadius;

  const FiloCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.onLongPress,
    this.backgroundColor,
    this.borderColor,
    this.borderRadius,
  });

  @override
  State<FiloCard> createState() => _FiloCardState();
}

class _FiloCardState extends State<FiloCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.borderRadius ?? FiloRadius.roundedXl;

    final cardBorder = widget.borderColor != null
        ? Border.all(color: widget.borderColor!, width: 1.2)
        : null;

    Widget content = FiloGlass(
      borderRadius: r,
      color: widget.backgroundColor,
      border: cardBorder,
      padding: widget.padding ?? const EdgeInsets.all(FiloSpacing.md),
      child: widget.child,
    );

    if (widget.onTap != null || widget.onLongPress != null) {
      return GestureDetector(
        onTapDown: (_) {
          setState(() => _isPressed = true);
          HapticFeedback.selectionClick();
        },
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
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
