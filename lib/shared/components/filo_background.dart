import 'package:flutter/material.dart';
import '../../core/theme/filo_colors.dart';

/// Full-screen ambient mesh background for Filo.
///
/// Light Mode: Ethereal Dawn (apricot rose, champagne glow, arctic lavender).
/// Dark Mode: Midnight Aurora (midnight plum aurora, obsidian violet, void slate).
class FiloBackground extends StatelessWidget {
  final Widget child;

  const FiloBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: isDark
              ? FiloColors.etherealDarkGradient
              : FiloColors.etherealDawnGradient,
          stops: const [0.0, 0.28, 0.65, 1.0],
        ),
      ),
      child: child,
    );
  }
}
