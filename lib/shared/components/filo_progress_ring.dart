import 'package:flutter/material.dart';
import '../../core/theme/filo_colors.dart';

/// Smooth progress ring with support for indeterminate and determinate states.
class FiloProgressRing extends StatelessWidget {
  final double? value; // 0.0 to 1.0, or null for indeterminate
  final double size;
  final double strokeWidth;
  final Color? color;
  final Color? trackColor;

  const FiloProgressRing({
    super.key,
    this.value,
    this.size = 28.0,
    this.strokeWidth = 2.5,
    this.color,
    this.trackColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = color ?? FiloColors.primary;
    final ringTrackColor = trackColor ??
        (isDark ? FiloColors.darkBorder : FiloColors.lightBorder);

    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        value: value,
        strokeWidth: strokeWidth,
        strokeCap: StrokeCap.round,
        backgroundColor: ringTrackColor,
        valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
      ),
    );
  }
}
