import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/filo_colors.dart';
import '../../core/theme/filo_motion.dart';
import '../../core/theme/filo_radius.dart';
import '../../core/theme/filo_spacing.dart';

enum FiloButtonVariant { primary, secondary, destructive, ghost }
enum FiloButtonSize { small, medium, large }

/// Reusable high-craft button component following Apple & Emil Kowalski guidelines.
///
/// Principles:
/// - 44pt minimum touch target.
/// - Instant press feedback (`scale: 0.97`) on tap-down, restoring on tap-up.
/// - Meaningful haptics on tap (`HapticFeedback.lightImpact()`).
/// - Never animate keyboard shortcuts.
/// - Disabled and loading state handling with spinners.
class FiloButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final FiloButtonVariant variant;
  final FiloButtonSize size;
  final bool isLoading;
  final bool isFullWidth;

  const FiloButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = FiloButtonVariant.primary,
    this.size = FiloButtonSize.medium,
    this.isLoading = false,
    this.isFullWidth = false,
  });

  @override
  State<FiloButton> createState() => _FiloButtonState();
}

class _FiloButtonState extends State<FiloButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: FiloMotion.durationPress,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: FiloMotion.pressScale,
    ).animate(CurvedAnimation(
      parent: _pressController,
      curve: FiloMotion.easeOut,
    ));
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    if (widget.onPressed != null && !widget.isLoading) {
      _pressController.forward();
      HapticFeedback.lightImpact();
    }
  }

  void _handleTapUp(TapUpDetails _) {
    if (widget.onPressed != null && !widget.isLoading) {
      _pressController.reverse();
    }
  }

  void _handleTapCancel() {
    if (widget.onPressed != null && !widget.isLoading) {
      _pressController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEnabled = widget.onPressed != null && !widget.isLoading;

    Color backgroundColor;
    Color foregroundColor;
    BorderSide border = BorderSide.none;

    switch (widget.variant) {
      case FiloButtonVariant.primary:
        backgroundColor = isEnabled
            ? FiloColors.primary
            : (isDark ? FiloColors.darkSurfaceSecondary : FiloColors.lightBorder);
        foregroundColor = isEnabled
            ? Colors.white
            : (isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary);
        break;
      case FiloButtonVariant.secondary:
        backgroundColor = isDark
            ? FiloColors.darkSurfaceSecondary
            : FiloColors.lightSurfaceSecondary;
        foregroundColor = isDark
            ? FiloColors.darkTextPrimary
            : FiloColors.lightTextPrimary;
        border = BorderSide(
          color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
          width: 1,
        );
        break;
      case FiloButtonVariant.destructive:
        backgroundColor = isEnabled
            ? FiloColors.destructive
            : (isDark ? FiloColors.darkSurfaceSecondary : FiloColors.lightBorder);
        foregroundColor = Colors.white;
        break;
      case FiloButtonVariant.ghost:
        backgroundColor = Colors.transparent;
        foregroundColor = isDark
            ? FiloColors.darkTextPrimary
            : FiloColors.lightTextPrimary;
        break;
    }

    double height;
    double fontSize;
    EdgeInsets padding;

    switch (widget.size) {
      case FiloButtonSize.small:
        height = 36.0;
        fontSize = 13.0;
        padding = const EdgeInsets.symmetric(horizontal: FiloSpacing.md);
        break;
      case FiloButtonSize.medium:
        height = FiloSpacing.minTouchTarget; // 44pt minimum
        fontSize = 15.0;
        padding = const EdgeInsets.symmetric(horizontal: FiloSpacing.lg);
        break;
      case FiloButtonSize.large:
        height = 52.0;
        fontSize = 16.0;
        padding = const EdgeInsets.symmetric(horizontal: FiloSpacing.xl);
        break;
    }

    Widget content = Row(
      mainAxisSize: widget.isFullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.isLoading) ...[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
            ),
          ),
          const SizedBox(width: FiloSpacing.sm),
        ] else if (widget.icon != null) ...[
          widget.icon!,
          const SizedBox(width: FiloSpacing.sm),
        ],
        Text(
          widget.label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: foregroundColor,
            letterSpacing: -0.2,
          ),
        ),
      ],
    );

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: isEnabled ? widget.onPressed : null,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: Container(
          constraints: BoxConstraints(
            minHeight: FiloSpacing.minTouchTarget,
            minWidth: widget.isFullWidth ? double.infinity : FiloSpacing.minTouchTarget,
          ),
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: FiloRadius.roundedMd,
            border: border != BorderSide.none ? Border.fromBorderSide(border) : null,
          ),
          alignment: Alignment.center,
          child: content,
        ),
      ),
    );
  }
}
