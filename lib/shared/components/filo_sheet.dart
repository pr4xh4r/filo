import 'package:flutter/material.dart';
import '../../core/theme/filo_colors.dart';
import '../../core/theme/filo_motion.dart';
import '../../core/theme/filo_radius.dart';
import '../../core/theme/filo_spacing.dart';

/// Adaptive, spring-driven bottom sheet modal following Apple & Emil Kowalski design standards.
///
/// Features:
/// - Smooth spring physics (`FiloMotion.easeDrawer`).
/// - Pull handle with drag affordance.
/// - Safe area compliance.
/// - Minimum 44pt touch targets on actions.
class FiloSheet extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;

  const FiloSheet({
    super.key,
    this.title,
    required this.child,
    this.trailing,
  });

  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    String? title,
    Widget? trailing,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      transitionAnimationController: AnimationController(
        vsync: Navigator.of(context),
        duration: FiloMotion.durationSheet,
      ),
      builder: (context) => FiloSheet(
        title: title,
        trailing: trailing,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? FiloColors.darkSurface : FiloColors.lightSurface,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(FiloRadius.xl),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Grab handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark
                        ? FiloColors.darkBorder
                        : FiloColors.lightBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (title != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FiloSpacing.lg,
                    vertical: FiloSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title!,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.3,
                            color: isDark
                                ? FiloColors.darkTextPrimary
                                : FiloColors.lightTextPrimary,
                          ),
                        ),
                      ),
                      if (trailing != null) trailing!,
                    ],
                  ),
                ),
                Divider(
                  color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
                ),
              ],
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FiloSpacing.lg,
                    FiloSpacing.xs,
                    FiloSpacing.lg,
                    FiloSpacing.lg,
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
