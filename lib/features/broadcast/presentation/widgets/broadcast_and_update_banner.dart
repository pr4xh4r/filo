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
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: FiloColors.brandGradient),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Text(
                          'ANNOUNCEMENT',
                          style: FiloTypography.caption.copyWith(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
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
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.05),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 14,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    state.broadcast!.title,
                    style: FiloTypography.title3.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.broadcast!.message,
                    style: FiloTypography.body.copyWith(
                      fontSize: 13,
                      color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                      height: 1.35,
                    ),
                  ),
                  if (state.broadcast!.actionUrl != null && state.broadcast!.actionUrl!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        BroadcastNotifier.openUrl(state.broadcast!.actionUrl!);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark ? FiloColors.darkSurfaceSecondary : Colors.black,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              state.broadcast!.actionTitle ?? 'Learn More',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
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

          // 2. Persistent Non-Annoying Update Banner
          if (hasUpdate) ...[
            if (state.isUpdateCollapsed)
              // Collapsed Minimal Chip
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
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: FiloColors.accentCoral,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Filo v${state.update!.latestVersion} update available',
                            style: FiloTypography.caption.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Text(
                            'view details',
                            style: FiloTypography.caption.copyWith(
                              color: FiloColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 2),
                          const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: FiloColors.primary),
                        ],
                      ),
                    ],
                  ),
                ),
              )
            else
              // Expanded Elegant Card
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
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: FiloColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: FiloColors.primary.withValues(alpha: 0.25)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.rocket_launch_rounded, size: 12, color: FiloColors.primary),
                              const SizedBox(width: 4),
                              Text(
                                'NEW VERSION • v${state.update!.latestVersion}',
                                style: FiloTypography.caption.copyWith(
                                  color: FiloColors.primary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Collapse / Minimize Button
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            notifier.toggleCollapseUpdate(true);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'minimize',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white70 : Colors.black54,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Icon(Icons.keyboard_arrow_up_rounded, size: 14, color: isDark ? Colors.white70 : Colors.black54),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
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
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(Icons.check_circle_rounded, size: 13, color: FiloColors.success),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    item,
                                    style: FiloTypography.caption.copyWith(
                                      color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 12),
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
                                    color: FiloColors.primary.withValues(alpha: 0.3),
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
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: FiloRadius.roundedLg),
                            side: BorderSide(
                              color: isDark ? Colors.white24 : Colors.black12,
                            ),
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            notifier.toggleCollapseUpdate(true);
                          },
                          child: Text(
                            'later',
                            style: TextStyle(
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
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
