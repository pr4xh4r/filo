import 'package:flutter/material.dart';

/// Centralized asset helper for Filo editorial illustrations.
///
/// Features unified, professional, gender-neutral editorial line-art with
/// soft translucent frosted-glass geometry and ambient Ethereal Dawn pastel halos.
class FiloIllustrations {
  FiloIllustrations._();

  static const String welcome = 'assets/illustrations/welcome.png';
  static const String emptyVault = 'assets/illustrations/empty_vault.png';
  static const String trash = 'assets/illustrations/trash.png';
  static const String security = 'assets/illustrations/s&tencrpt.png';
  static const String recovery = 'assets/illustrations/key.png';
  static const String transfer = 'assets/illustrations/upload.png';
  static const String starred = 'assets/illustrations/starred.png';
}

/// Adaptive editorial illustration widget:
/// - Renders precision monoline artwork with soft ambient pastel halo.
/// - In Dark Mode, inverts black lines into luminous celestial silver-white.
/// - In Light Mode, preserves fine midnight ink contours.
class FiloIllustrationView extends StatelessWidget {
  final String assetName;
  final double? maxHeight;
  final double? maxWidth;
  final BoxFit fit;

  const FiloIllustrationView({
    super.key,
    required this.assetName,
    this.maxHeight,
    this.maxWidth,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget image = Image.asset(
      assetName,
      fit: fit,
    );

    if (isDark) {
      // Invert ink contours for dark mode: black becomes bright luminous silver/white
      image = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          -1, 0, 0, 0, 255,
          0, -1, 0, 0, 255,
          0, 0, -1, 0, 255,
          0, 0, 0, 1, 0,
        ]),
        child: image,
      );
    }

    if (maxHeight != null || maxWidth != null) {
      return Container(
        constraints: BoxConstraints(
          maxHeight: maxHeight ?? double.infinity,
          maxWidth: maxWidth ?? double.infinity,
        ),
        child: image,
      );
    }

    return image;
  }
}
