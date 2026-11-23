import 'package:flutter/material.dart';
import '../../core/theme/filo_colors.dart';
import '../../core/theme/filo_radius.dart';
import '../../core/theme/filo_spacing.dart';

/// Clean card container component with adaptive borders and dark mode handling.
class FiloCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? backgroundColor;
  final Color? borderColor;

  const FiloCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.onLongPress,
    this.backgroundColor,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = backgroundColor ??
        (isDark ? FiloColors.darkSurface : FiloColors.lightSurface);
    final border = borderColor ??
        (isDark ? FiloColors.darkBorder : FiloColors.lightBorder);

    Widget content = Container(
      padding: padding ?? const EdgeInsets.all(FiloSpacing.lg),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: FiloRadius.roundedLg,
        border: Border.all(color: border, width: 1.0),
      ),
      child: child,
    );

    if (onTap != null || onLongPress != null) {
      return InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: FiloRadius.roundedLg,
        child: content,
      );
    }

    return content;
  }
}
