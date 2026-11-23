import 'package:flutter/material.dart';
import '../../core/theme/filo_colors.dart';
import '../../core/theme/filo_radius.dart';
import '../../core/theme/filo_spacing.dart';
import 'filo_button.dart';

/// Clean, high-craft empty state presentation component.
class FiloEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const FiloEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: FiloSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: isDark
                    ? FiloColors.darkSurfaceSecondary
                    : FiloColors.lightSurfaceSecondary,
                borderRadius: FiloRadius.roundedXl,
                border: Border.all(
                  color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
                  width: 1,
                ),
              ),
              child: Icon(
                icon,
                size: 32,
                color: isDark
                    ? FiloColors.darkTextSecondary
                    : FiloColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: FiloSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.3,
                color: isDark
                    ? FiloColors.darkTextPrimary
                    : FiloColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: FiloSpacing.xs),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: isDark
                    ? FiloColors.darkTextSecondary
                    : FiloColors.lightTextSecondary,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: FiloSpacing.xl),
              FiloButton(
                label: actionLabel!,
                onPressed: onAction,
                variant: FiloButtonVariant.primary,
                size: FiloButtonSize.medium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
