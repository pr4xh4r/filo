import 'package:flutter/material.dart';

/// Typography hierarchy for Filo.
///
/// Features:
/// - Manrope font (geometric sans-serif with Apple neo-grotesque clarity, Image 9)
/// - Editorial serif accents for headlines (CRED aesthetic, Image 0-3)
/// - Monospaced JetBrains Mono for security hashes & keys
/// - Bundled local assets for 100% offline, zero-latency rendering
class FiloTypography {
  FiloTypography._();

  static const String fontFamily = 'Manrope';
  static const String editorialFontFamily = 'Newsreader';
  static const String monospaceFontFamily = 'JetBrainsMono';
  static const String handwritingFontFamily = 'Caveat';

  // Base font style generator
  static TextStyle font({
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    double? height,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
    );
  }

  // Handwritten cursive for captivating hero welcomes
  static TextStyle handwriting({
    double fontSize = 42.0,
    FontWeight fontWeight = FontWeight.w600,
    double letterSpacing = 0.5,
    double height = 1.2,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: handwritingFontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
    );
  }

  // Editorial Serif for Hero Headlines (CRED style)
  static TextStyle editorial({
    double fontSize = 34.0,
    FontWeight fontWeight = FontWeight.w600,
    double letterSpacing = -0.8,
    double height = 1.15,
    Color? color,
  }) {
    return TextStyle(
      fontFamily: editorialFontFamily,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
      height: height,
      color: color,
    );
  }

  // Display & Large Titles
  static TextStyle get largeTitle => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 34.0,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.0,
        height: 1.15,
      );

  static TextStyle get title1 => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 26.0,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.2,
      );

  static TextStyle get title2 => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 21.0,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        height: 1.25,
      );

  static TextStyle get title3 => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 18.0,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        height: 1.3,
      );

  // Body & Content
  static TextStyle get body => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 15.0,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.2,
        height: 1.45,
      );

  static TextStyle get bodyMedium => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 15.0,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
        height: 1.45,
      );

  static TextStyle get callout => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 14.0,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
        height: 1.35,
      );

  static TextStyle get subheadline => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 13.0,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.0,
        height: 1.35,
      );

  static TextStyle get footnote => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 12.0,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.1,
        height: 1.3,
      );

  static TextStyle get caption => const TextStyle(
        fontFamily: fontFamily,
        fontSize: 11.0,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
        height: 1.25,
      );

  // Monospaced for Hashes & Cipher keys
  static TextStyle get monospace => const TextStyle(
        fontFamily: monospaceFontFamily,
        fontSize: 13.0,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.0,
        height: 1.4,
      );
}
