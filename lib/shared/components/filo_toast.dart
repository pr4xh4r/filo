import 'package:flutter/material.dart';
import '../../core/theme/filo_colors.dart';
import '../../core/theme/filo_radius.dart';
import '../../core/theme/filo_spacing.dart';

enum FiloToastType { info, success, warning, error }

/// Toast notification system inspired by Emil Kowalski's Sonner library.
///
/// Principles:
/// - 400ms smooth transition with `FiloMotion.easeOut`.
/// - Animate from `scale(0.95)` and opacity (never scale(0)).
/// - Floating pill design, unobtrusive, high contrast.
class FiloToast {
  FiloToast._();

  static void show(
    BuildContext context, {
    required String message,
    FiloToastType type = FiloToastType.info,
    Duration duration = const Duration(seconds: 3),
    VoidCallback? actionOnPressed,
    String? actionLabel,
  }) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.hideCurrentSnackBar();

    Color iconColor;
    IconData iconData;

    switch (type) {
      case FiloToastType.success:
        iconColor = FiloColors.success;
        iconData = Icons.check_circle_rounded;
        break;
      case FiloToastType.warning:
        iconColor = FiloColors.warning;
        iconData = Icons.warning_rounded;
        break;
      case FiloToastType.error:
        iconColor = FiloColors.destructive;
        iconData = Icons.error_rounded;
        break;
      case FiloToastType.info:
        iconColor = FiloColors.info;
        iconData = Icons.info_rounded;
        break;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    scaffoldMessenger.showSnackBar(
      SnackBar(
        duration: duration,
        elevation: 6,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.symmetric(
          horizontal: FiloSpacing.lg,
          vertical: FiloSpacing.md,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: FiloSpacing.md,
          vertical: FiloSpacing.md,
        ),
        backgroundColor: isDark
            ? FiloColors.darkSurfaceSecondary
            : FiloColors.lightSurface,
        shape: RoundedRectangleBorder(
          borderRadius: FiloRadius.roundedLg,
          side: BorderSide(
            color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
            width: 1,
          ),
        ),
        content: Row(
          children: [
            Icon(iconData, color: iconColor, size: 20),
            const SizedBox(width: FiloSpacing.md),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isDark
                      ? FiloColors.darkTextPrimary
                      : FiloColors.lightTextPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                ),
              ),
            ),
            if (actionLabel != null && actionOnPressed != null) ...[
              const SizedBox(width: FiloSpacing.sm),
              GestureDetector(
                onTap: actionOnPressed,
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    color: FiloColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
