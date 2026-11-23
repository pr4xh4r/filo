import 'package:flutter/material.dart';

/// Motion tokens translating Emil Kowalski & Apple Design principles to Flutter.
///
/// Rules:
/// - UI animations stay strictly under 300ms (modals/drawers up to 400ms).
/// - Strong custom cubic curves instead of weak default easings.
/// - Never ease-in on interactive UI.
/// - Scale press feedback at 0.97.
/// - Entrance starts at 0.95 scale + opacity (NEVER scale 0).
class FiloMotion {
  FiloMotion._();

  // Durations
  static const Duration durationPress = Duration(milliseconds: 140);
  static const Duration durationFast = Duration(milliseconds: 180);
  static const Duration durationNormal = Duration(milliseconds: 240);
  static const Duration durationSheet = Duration(milliseconds: 320);
  static const Duration durationModal = Duration(milliseconds: 280);

  // Emil Kowalski & Apple Custom Curves
  /// Strong ease-out for UI entrances, popovers, and immediate touch feedback
  static const Curve easeOut = Cubic(0.23, 1.0, 0.32, 1.0);

  /// iOS-like drawer / bottom sheet curve
  static const Curve easeDrawer = Cubic(0.32, 0.72, 0.0, 1.0);

  /// Natural morphing & on-screen repositioning curve
  static const Curve easeInOut = Cubic(0.77, 0.0, 0.175, 1.0);

  /// Deliberate hold action timing (e.g. hold-to-delete)
  static const Duration durationHoldConfirm = Duration(milliseconds: 1800);

  /// Active button press scale factor (0.97 gives instantaneous physical feedback)
  static const double pressScale = 0.97;

  /// Entrance initial scale factor (never scale from 0)
  static const double entranceInitialScale = 0.95;

  /// Stagger item delay for cascading lists (30ms - 50ms per item)
  static const Duration staggerDelay = Duration(milliseconds: 35);

  /// Respects system prefers-reduced-motion setting.
  /// If animations are disabled, returns Duration.zero so vestibular motion is eliminated.
  static Duration getDuration(BuildContext context, Duration normal) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      return Duration.zero;
    }
    return normal;
  }
}
