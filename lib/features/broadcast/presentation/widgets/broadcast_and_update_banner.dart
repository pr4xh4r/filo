import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_glass.dart';
import '../../../../shared/components/filo_toast.dart';
import '../../domain/broadcast_service.dart';

/// Theme-synced liquid glass banner for admin broadcasts and polite version update reminders.
///
/// Features:
/// - 100% synced with Filo's Ethereal Dawn (Light) and Midnight Aurora (Dark) design systems.
/// - Notification icons inside cards replacing text buttons.
/// - Non-blocking polite user-choice update experience.
class BroadcastAndUpdateBanner extends ConsumerWidget {
  const BroadcastAndUpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(broadcastNotifierProvider);
    final notifier = ref.read(broadcastNotifierProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final hasBroadcast = state.broadcast != null;
    final hasUpdate = state.update != null;

    if (!hasBroadcast && !hasUpdate) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(FiloSpacing.lg, 4, FiloSpacing.lg, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Admin Broadcast Announcement Card
          if (hasBroadcast) ...[
            FiloGlass(
              borderRadius: FiloRadius.roundedXl,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: FiloColors.brandGradient),
                          borderRadius: BorderRadius.circular(100),
                          boxShadow: [
                            BoxShadow(
                              color: FiloColors.accentCoral.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.campaign_rounded,
                              size: 13,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              'ANNOUNCEMENT',
                              style: FiloTypography.caption.copyWith(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (state.broadcast!.isDismissible)
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            notifier.dismissBroadcast(state.broadcast!.id);
                            FiloToast.show(context, message: 'Announcement dismissed', type: FiloToastType.info);
                          },
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.06),
                              ),
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    state.broadcast!.title,
                    style: FiloTypography.title3.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 15.5,
                      color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    state.broadcast!.message,
                    style: FiloTypography.body.copyWith(
                      fontSize: 13,
                      color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                      height: 1.4,
                    ),
                  ),
                  if (state.broadcast!.actionUrl != null && state.broadcast!.actionUrl!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        BroadcastNotifier.openUrl(state.broadcast!.actionUrl!);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: FiloColors.brandGradient),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: FiloColors.accentCoral.withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              state.broadcast!.actionTitle ?? 'Learn More',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 5),
                            const Icon(Icons.arrow_outward_rounded, size: 13, color: Colors.white),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // 2. Persistent Non-Annoying Update Banner (Theme-Synced)
          if (hasUpdate) ...[
            if (state.isUpdateCollapsed)
              // Collapsed Minimal Notification Chip with Bell Icon
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  notifier.toggleCollapseUpdate(false);
                },
                child: FiloGlass(
                  borderRadius: BorderRadius.circular(100),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              color: FiloColors.accentCoral.withValues(alpha: isDark ? 0.22 : 0.12),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: FiloColors.accentCoral.withValues(alpha: isDark ? 0.45 : 0.25),
                              ),
                            ),
                            child: const Icon(
                              Icons.notifications_active_rounded,
                              size: 14,
                              color: FiloColors.accentCoral,
                            ),
                          ),
                          const SizedBox(width: 9),
                          Text(
                            'Filo v${state.update!.latestVersion} update available',
                            style: FiloTypography.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            'view',
                            style: FiloTypography.caption.copyWith(
                              color: FiloColors.accentCoral,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: FiloColors.accentCoral,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else
              // Expanded Elegant Theme-Synced Card
              FiloGlass(
                borderRadius: FiloRadius.roundedXl,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Left: Theme-synced notification badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: FiloColors.accentCoral.withValues(alpha: isDark ? 0.20 : 0.12),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: FiloColors.accentCoral.withValues(alpha: isDark ? 0.40 : 0.28),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.notifications_active_rounded,
                                size: 13,
                                color: FiloColors.accentCoral,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'NEW UPDATE • v${state.update!.latestVersion}',
                                style: FiloTypography.caption.copyWith(
                                  color: FiloColors.accentCoral,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Right: Notification icon button replacing the text button
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            notifier.toggleCollapseUpdate(true);
                          },
                          child: Tooltip(
                            message: 'Minimize notification',
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.black.withValues(alpha: 0.05),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.06),
                                ),
                              ),
                              child: Icon(
                                Icons.notifications_active_outlined,
                                size: 16,
                                color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.update!.title,
                      style: FiloTypography.title3.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (state.update!.changelog.isNotEmpty) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: state.update!.changelog.map((item) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: FiloColors.success.withValues(alpha: isDark ? 0.20 : 0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check_rounded,
                                      size: 11,
                                      color: FiloColors.success,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    item,
                                    style: FiloTypography.caption.copyWith(
                                      color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              BroadcastNotifier.openUrl(state.update!.downloadUrl);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: FiloColors.brandGradient),
                                borderRadius: FiloRadius.roundedLg,
                                boxShadow: [
                                  BoxShadow(
                                    color: FiloColors.accentCoral.withValues(alpha: 0.35),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.download_rounded, size: 16, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Text(
                                    'update now',
                                    style: FiloTypography.callout.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            notifier.toggleCollapseUpdate(true);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                              borderRadius: FiloRadius.roundedLg,
                              border: Border.all(
                                color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
                              ),
                            ),
                            child: Text(
                              'later',
                              style: TextStyle(
                                color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
