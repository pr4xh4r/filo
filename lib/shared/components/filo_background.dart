import 'package:flutter/material.dart';
import '../../core/theme/filo_colors.dart';

/// Full-screen ambient mesh background for the Ethereal Dawn aesthetic.
///
/// Blends warm apricot rose, champagne glow, and misty arctic lavender
/// seamlessly behind frosted-glass surfaces.
class FiloBackground extends StatelessWidget {
  final Widget child;

  const FiloBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: FiloColors.etherealDawnGradient,
          stops: [0.0, 0.28, 0.65, 1.0],
        ),
      ),
      child: child,
    );
  }
}
