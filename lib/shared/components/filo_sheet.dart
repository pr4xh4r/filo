import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/filo_colors.dart';
import '../../core/theme/filo_motion.dart';
import '../../core/theme/filo_spacing.dart';
import '../../core/theme/filo_typography.dart';

/// Adaptive, spring-driven bottom sheet modal following Ethereal Dawn frosted glass standards.
///
/// Features:
/// - Frosted glass backdrop blur (28px).
/// - Ethereal ambient gradient tint with white specular rim.
/// - Smooth spring physics (`FiloMotion.easeDrawer`).
/// - Pull handle with drag affordance.
/// - Safe area compliance.
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
      barrierColor: Colors.black.withValues(alpha: 0.35),
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
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(32),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFCFFF8F5),
                Color(0xFCF8F4FF),
              ],
            ),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(32),
            ),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.95),
                width: 1.5,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2C243B).withValues(alpha: 0.10),
                blurRadius: 32,
                offset: const Offset(0, -6),
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
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C243B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  if (title != null) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FiloSpacing.xl,
                        vertical: FiloSpacing.xs,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title!,
                              style: const TextStyle(
                                fontFamily: FiloTypography.fontFamily,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.4,
                                color: FiloColors.lightTextPrimary,
                              ),
                            ),
                          ),
                          if (trailing != null) trailing!,
                        ],
                      ),
                    ),
                    Divider(
                      color: Colors.black.withValues(alpha: 0.05),
                      height: 12,
                      indent: FiloSpacing.xl,
                      endIndent: FiloSpacing.xl,
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
        ),
      ),
    );
  }
}
