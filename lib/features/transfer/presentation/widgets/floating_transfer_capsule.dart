import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/transfer_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_motion.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../shared/components/filo_glass.dart';
import '../../../../shared/components/filo_progress_ring.dart';
import '../providers/transfer_provider.dart';
import '../screens/transfer_queue_sheet.dart';

/// Floating Dynamic Island-style capsule displaying active upload/download progress in real-time.
class FloatingTransferCapsule extends ConsumerStatefulWidget {
  const FloatingTransferCapsule({super.key});

  @override
  ConsumerState<FloatingTransferCapsule> createState() =>
      _FloatingTransferCapsuleState();
}

class _FloatingTransferCapsuleState extends ConsumerState<FloatingTransferCapsule>
    with SingleTickerProviderStateMixin {
  Timer? _dismissTimer;
  String? _lastCompletedId;
  bool _showCompleted = false;

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(transferQueueProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Check for active running tasks
    final runningTasks = tasks.where((t) => t.status == TransferStatus.running).toList();
    final recentlyCompleted = tasks.where((t) => t.status == TransferStatus.completed).toList();

    TransferTask? displayTask;
    bool isCompletedState = false;

    if (runningTasks.isNotEmpty) {
      displayTask = runningTasks.first;
      _showCompleted = false;
    } else if (recentlyCompleted.isNotEmpty) {
      final latest = recentlyCompleted.last;
      if (latest.id != _lastCompletedId) {
        _lastCompletedId = latest.id;
        _showCompleted = true;
        _dismissTimer?.cancel();
        _dismissTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _showCompleted = false;
            });
          }
        });
      }
      if (_showCompleted) {
        displayTask = latest;
        isCompletedState = true;
      }
    }

    final isVisible = displayTask != null;

    return AnimatedSlide(
      duration: FiloMotion.durationMedium,
      curve: FiloMotion.easeSpring,
      offset: isVisible ? Offset.zero : const Offset(0, 1.5),
      child: AnimatedOpacity(
        duration: FiloMotion.durationFast,
        opacity: isVisible ? 1.0 : 0.0,
        child: isVisible
            ? Center(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    TransferQueueSheet.show(context);
                  },
                  child: FiloGlass(
                    borderRadius: BorderRadius.circular(100),
                    padding: const EdgeInsets.symmetric(
                      horizontal: FiloSpacing.md + 2,
                      vertical: FiloSpacing.sm + 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Progress ring or status icon
                        if (isCompletedState)
                          const Icon(
                            Icons.check_circle_rounded,
                            size: 20,
                            color: FiloColors.success,
                          )
                        else
                          FiloProgressRing(
                            value: displayTask.progress > 0 ? displayTask.progress : null,
                            size: 18,
                            strokeWidth: 2.2,
                            color: displayTask.type == TransferType.upload
                                ? FiloColors.primary
                                : FiloColors.info,
                          ),
                        const SizedBox(width: FiloSpacing.sm + 2),

                        // Transfer Text Details
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            isCompletedState
                                ? '✓ Completed ${displayTask.fileName}'
                                : '${displayTask.type == TransferType.upload ? 'Uploading' : 'Downloading'} ${displayTask.fileName} • ${(displayTask.progress * 100).clamp(0, 100).toInt()}%',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: isDark
                                  ? FiloColors.darkTextPrimary
                                  : FiloColors.lightTextPrimary,
                            ),
                          ),
                        ),

                        const SizedBox(width: FiloSpacing.sm),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: isDark
                              ? FiloColors.darkTextTertiary
                              : FiloColors.lightTextTertiary,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
