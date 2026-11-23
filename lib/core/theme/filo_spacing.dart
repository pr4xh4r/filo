/// Spacing scale tokens for Filo based on an 8pt baseline grid with 4pt half-steps.
class FiloSpacing {
  FiloSpacing._();

  static const double xxs = 2.0;
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 48.0;

  /// Minimum accessible touch target (Apple HIG & Material 3 specification).
  static const double minTouchTarget = 44.0;
}
