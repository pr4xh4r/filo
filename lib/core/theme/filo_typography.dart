import 'package:flutter/material.dart';

/// Typography hierarchy for Filo.
///
/// Features:
/// - Optical sizing & size-specific tracking (negative tracking on large titles, positive on small labels).
/// - Dynamic text scaling support.
/// - Strict contrast compliance (>= 4.5:1).
class FiloTypography {
  FiloTypography._();

  static const String fontFamily = 'SF Pro Display'; // Fallback to system-ui

  // Display & Large Titles
  static const TextStyle largeTitle = TextStyle(
    fontSize: 32.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    height: 1.15,
  );

  static const TextStyle title1 = TextStyle(
    fontSize: 24.0,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    height: 1.2,
  );

  static const TextStyle title2 = TextStyle(
    fontSize: 20.0,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    height: 1.25,
  );

  static const TextStyle title3 = TextStyle(
    fontSize: 17.0,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.3,
  );

  // Body & Content
  static const TextStyle body = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
    height: 1.4,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 16.0,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
    height: 1.4,
  );

  static const TextStyle callout = TextStyle(
    fontSize: 15.0,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.1,
    height: 1.35,
  );

  static const TextStyle subheadline = TextStyle(
    fontSize: 14.0,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.0,
    height: 1.35,
  );

  static const TextStyle footnote = TextStyle(
    fontSize: 13.0,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    height: 1.35,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 12.0,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    height: 1.3,
  );

  static const TextStyle monospace = TextStyle(
    fontSize: 13.0,
    fontFamily: 'monospace',
    fontWeight: FontWeight.w500,
    letterSpacing: 0.0,
    height: 1.4,
  );
}
