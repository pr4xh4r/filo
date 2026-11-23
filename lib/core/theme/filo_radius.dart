import 'package:flutter/material.dart';

/// Corner radius tokens for Filo following fluid physical curvature.
class FiloRadius {
  FiloRadius._();

  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 20.0;
  static const double xxl = 28.0;
  static const double full = 9999.0;

  // BorderRadius helpers
  static final BorderRadius roundedXs = BorderRadius.circular(xs);
  static final BorderRadius roundedSm = BorderRadius.circular(sm);
  static final BorderRadius roundedMd = BorderRadius.circular(md);
  static final BorderRadius roundedLg = BorderRadius.circular(lg);
  static final BorderRadius roundedXl = BorderRadius.circular(xl);
  static final BorderRadius roundedXxl = BorderRadius.circular(xxl);
  static final BorderRadius roundedFull = BorderRadius.circular(full);
}
