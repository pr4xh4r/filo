import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/database/transfer_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../core/theme/persona_provider.dart';
import '../../../../shared/components/filo_progress_ring.dart';
import '../../../../shared/components/filo_sheet.dart';
import '../providers/transfer_provider.dart';

/// Modal sheet displaying active and recent background file uploads & downloads.
class TransferQueueSheet extends ConsumerWidget {
  const TransferQueueSheet({super.key});

  static Future<void> show(BuildContext context) {
    return FiloSheet.show(
      context: context,
      title: 'Transfers',
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
      child: const TransferQueueSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(transferQueueProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (tasks.isEmpty) {
      return SizedBox(
        height: 250,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                FiloIllustrations.transfer,
                height: 160,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 12),
              const Text(
                'No Active Transfers',
                style: TextStyle(
                  fontFamily: FiloTypography.fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: FiloColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Uploads and downloads will stream here in real time',
                style: TextStyle(
                  fontFamily: FiloTypography.fontFamily,
                  fontSize: 13,
                  color: FiloColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 380),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: tasks.length,
        separatorBuilder: (context, index) => Divider(
          color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
          height: 1,
        ),
        itemBuilder: (context, index) {
          final task = tasks[index];

          Widget trailingWidget;
          if (task.status == TransferStatus.running) {
            trailingWidget = FiloProgressRing(
              value: task.progress > 0 ? task.progress : null,
              size: 24,
            );
          } else if (task.status == TransferStatus.completed) {
            trailingWidget = const Icon(
              Icons.check_circle_rounded,
              color: FiloColors.success,
              size: 24,
            );
          } else if (task.status == TransferStatus.failed) {
            trailingWidget = const Icon(
              Icons.error_rounded,
              color: FiloColors.destructive,
              size: 24,
            );
          } else {
            trailingWidget = const Icon(
              Icons.pause_circle_rounded,
              color: FiloColors.warning,
              size: 24,
            );
          }

          return ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: task.type == TransferType.upload
                    ? FiloColors.primary.withValues(alpha: 0.1)
                    : FiloColors.info.withValues(alpha: 0.1),
                borderRadius: FiloRadius.roundedMd,
              ),
              child: Icon(
                task.type == TransferType.upload
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                color: task.type == TransferType.upload
                    ? FiloColors.primary
                    : FiloColors.info,
                size: 20,
              ),
            ),
            title: Text(
              task.fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Text(
              '${HashUtils.formatBytes(task.bytesTransferred)} of ${HashUtils.formatBytes(task.totalBytes)}'
              '${task.errorMessage != null ? ' • ${task.errorMessage}' : ''}',
              style: TextStyle(
                fontSize: 12,
                color: task.status == TransferStatus.failed
                    ? FiloColors.destructive
                    : (isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary),
              ),
            ),
            trailing: trailingWidget,
          );
        },
      ),
    );
  }
}
