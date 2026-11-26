import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_sheet.dart';
import '../../../broadcast/domain/broadcast_service.dart';

/// Modal sheet displaying application updates and announcements.
///
/// Designed cleanly with Ethereal Dawn styling, devoid of technical jargon.
class NotificationsSheet extends ConsumerWidget {
  const NotificationsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return FiloSheet.show(
      context: context,
      title: 'Notifications',
      trailing: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.05),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.close_rounded,
            size: 18,
            color: FiloColors.lightTextSecondary,
          ),
        ),
      ),
      child: const NotificationsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final broadcastState = ref.watch(broadcastNotifierProvider);
    final notifier = ref.read(broadcastNotifierProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final update = broadcastState.update;
    final broadcast = broadcastState.broadcast;

    final hasContent = update != null || broadcast != null;

    if (!hasContent) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Icon(
                  Icons.notifications_none_rounded,
                  size: 28,
                  color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'No New Notifications',
                style: FiloTypography.title3.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                "You're all caught up! New updates and notices will appear here.",
                textAlign: TextAlign.center,
                style: FiloTypography.caption.copyWith(
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.70,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. App Update Card (If Available)
            if (update != null) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark ? FiloColors.darkSurfaceSecondary : Colors.white,
                  borderRadius: FiloRadius.roundedXl,
                  border: Border.all(
                    color: isDark ? FiloColors.darkBorder : Colors.black.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: FiloRadius.roundedMd,
                          ),
                          child: const Icon(
                            Icons.system_update_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Update Available',
                                style: FiloTypography.title3.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                                ),
                              ),
                              Text(
                                'Version ${update.latestVersion}',
                                style: FiloTypography.caption.copyWith(
                                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (update.changelog.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        "What's New:",
                        style: FiloTypography.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white70 : FiloColors.lightTextPrimary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...update.changelog.map(
                        (note) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 6, right: 8),
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white54 : FiloColors.lightTextTertiary,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  note,
                                  style: TextStyle(
                                    fontFamily: FiloTypography.fontFamily,
                                    fontSize: 13,
                                    height: 1.35,
                                    color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              BroadcastNotifier.openUrl(update.downloadUrl);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: FiloRadius.roundedLg,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.download_rounded, size: 16, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text(
                                    'Update Now',
                                    style: TextStyle(
                                      fontFamily: FiloTypography.fontFamily,
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
                            Navigator.of(context).pop();
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
                              'Dismiss',
                              style: TextStyle(
                                fontFamily: FiloTypography.fontFamily,
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
              const SizedBox(height: FiloSpacing.md),
            ],

            // 2. Admin Broadcast Notice (If Available)
            if (broadcast != null) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isDark ? FiloColors.darkSurfaceSecondary : Colors.white,
                  borderRadius: FiloRadius.roundedXl,
                  border: Border.all(
                    color: isDark ? FiloColors.darkBorder : Colors.black.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.black,
                                borderRadius: FiloRadius.roundedMd,
                              ),
                              child: const Icon(
                                Icons.campaign_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'Notice',
                              style: FiloTypography.caption.copyWith(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                        if (broadcast.isDismissible)
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              notifier.dismissBroadcast(broadcast.id);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close_rounded,
                                size: 16,
                                color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      broadcast.title,
                      style: FiloTypography.title3.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      broadcast.message,
                      style: TextStyle(
                        fontFamily: FiloTypography.fontFamily,
                        fontSize: 13.5,
                        height: 1.4,
                        color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                      ),
                    ),
                    if (broadcast.actionTitle != null && broadcast.actionUrl != null) ...[
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          BroadcastNotifier.openUrl(broadcast.actionUrl!);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: FiloRadius.roundedMd,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                broadcast.actionTitle!,
                                style: const TextStyle(
                                  fontFamily: FiloTypography.fontFamily,
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.arrow_outward_rounded, size: 14, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
