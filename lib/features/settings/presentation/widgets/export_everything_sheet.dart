import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/cache/session_cache_service.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../../shared/components/filo_progress_ring.dart';
import '../../../../shared/components/filo_sheet.dart';
import '../../../../shared/components/filo_toast.dart';
import '../../../transfer/domain/vault_export_service.dart';
import '../../../transfer/presentation/providers/export_provider.dart';

/// Resumable, streaming multi-GB Export Everything modal sheet.
class ExportEverythingSheet extends ConsumerStatefulWidget {
  const ExportEverythingSheet({super.key});

  static Future<void> show(BuildContext context) {
    return FiloSheet.show(
      context: context,
      title: 'Export Everything',
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
      child: const ExportEverythingSheet(),
    );
  }

  @override
  ConsumerState<ExportEverythingSheet> createState() =>
      _ExportEverythingSheetState();
}

class _ExportEverythingSheetState extends ConsumerState<ExportEverythingSheet> {
  ({int fileCount, int totalBytes})? _estimate;
  int? _availableStorageBytes;
  String? _selectedDestinationDir;
  bool _loadingEstimate = true;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    final notifier = ref.read(vaultExportProvider.notifier);
    ({int fileCount, int totalBytes})? estimate;
    try {
      estimate = await notifier.estimateExportSize();
    } catch (_) {
      // Non-fatal if DB unavailable during teardown
    }
    if (mounted) {
      setState(() {
        _estimate = estimate;
        _loadingEstimate = false;
      });
    }

    await notifier.refreshCheckpoint();
    int? freeBytes;
    try {
      freeBytes = await notifier.getAvailableStorageBytes();
    } catch (_) {
      // Best-effort storage check
    }

    if (mounted) {
      setState(() {
        _availableStorageBytes = freeBytes;
      });
    }
  }

  bool get _isDesktopPlatform =>
      !kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows);

  Future<void> _pickDestinationFolder() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Select Export Destination Folder',
      );
      if (path != null && path.isNotEmpty && mounted) {
        setState(() => _selectedDestinationDir = path);
      }
    } catch (e) {
      if (mounted) {
        FiloToast.show(
          context,
          message: 'Could not select folder: $e',
          type: FiloToastType.error,
        );
      }
    }
  }

  Future<void> _startFresh() async {
    try {
      await ref.read(vaultExportProvider.notifier).startFreshExport(
            customDestinationDir: _selectedDestinationDir,
          );
    } catch (e) {
      if (mounted) {
        FiloToast.show(
          context,
          message: 'Export failed: $e',
          type: FiloToastType.error,
        );
      }
    }
  }

  Future<void> _resume({bool finalizePartialOnly = false}) async {
    try {
      await ref.read(vaultExportProvider.notifier).resumeExport(
            finalizePartialOnly: finalizePartialOnly,
          );
    } catch (e) {
      if (mounted) {
        FiloToast.show(
          context,
          message: 'Resume failed: $e',
          type: FiloToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final exportState = ref.watch(vaultExportProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary =
        isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary;
    final textSecondary =
        isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary;

    if (exportState.isActive) {
      return _buildActiveView(exportState, textPrimary, textSecondary, isDark);
    }

    if (exportState.status == VaultExportStatus.paused ||
        exportState.status == VaultExportStatus.partialNeedsAction) {
      return _buildResumableView(
        exportState,
        textPrimary,
        textSecondary,
        isDark,
      );
    }

    if (exportState.status == VaultExportStatus.completed) {
      return _buildCompletedView(
        exportState,
        textPrimary,
        textSecondary,
        isDark,
      );
    }

    if (exportState.status == VaultExportStatus.failed) {
      return _buildFailedView(exportState, textPrimary, textSecondary, isDark);
    }

    return _buildIdleView(textPrimary, textSecondary, isDark);
  }

  Widget _buildIdleView(Color textPrimary, Color textSecondary, bool isDark) {
    final fileCount = _estimate?.fileCount ?? 0;
    final totalBytes = _estimate?.totalBytes ?? 0;
    final lowStorage = _availableStorageBytes != null &&
        totalBytes > 0 &&
        _availableStorageBytes! < (totalBytes * 1.1).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _infoCard(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _loadingEstimate
                    ? 'Calculating vault size...'
                    : (fileCount == 0
                        ? 'Your vault has no files to export.'
                        : '$fileCount files • ${HashUtils.formatBytes(totalBytes)}'),
                style: FiloTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Streams files chunk-by-chunk directly to disk in a Zip64 archive, staying protected against screen lock and interruptions.',
                style: FiloTypography.caption.copyWith(color: textSecondary),
              ),
              if (_availableStorageBytes != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Available device storage: ${HashUtils.formatBytes(_availableStorageBytes!)}',
                  style: FiloTypography.caption.copyWith(
                    color: lowStorage ? FiloColors.warning : textSecondary,
                    fontWeight: lowStorage ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (lowStorage) ...[
          const SizedBox(height: FiloSpacing.sm),
          Text(
            'Warning: Free storage may be insufficient for a full archive export. Consider freeing space first.',
            style: FiloTypography.caption.copyWith(
              color: FiloColors.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (_isDesktopPlatform) ...[
          const SizedBox(height: FiloSpacing.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  _selectedDestinationDir ?? 'Destination: Downloads folder',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FiloTypography.caption.copyWith(color: textSecondary),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: _pickDestinationFolder,
                child: const Text('Choose Folder'),
              ),
            ],
          ),
        ],
        const SizedBox(height: FiloSpacing.lg),
        FiloButton(
          label: 'Start Full Export',
          icon: const Icon(Icons.download_rounded, size: 18),
          isFullWidth: true,
          onPressed: (!_loadingEstimate && fileCount > 0) ? _startFresh : null,
        ),
      ],
    );
  }

  Widget _buildActiveView(
    VaultExportState state,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    final pct = (state.progress * 100).clamp(0, 100).toInt();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _infoCard(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  FiloProgressRing(
                    value: state.progress > 0 ? state.progress : null,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      state.status == VaultExportStatus.finalizing
                          ? 'Finalizing Zip64 archive...'
                          : (state.currentFileName ??
                              state.statusMessage ??
                              'Preparing export...'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FiloTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '$pct%',
                    style: FiloTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: FiloColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: state.totalBytes > 0 ? state.progress : null,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${state.completedFiles} of ${state.totalFiles} files • '
                '${HashUtils.formatBytes(state.bytesTransferred)} of ${HashUtils.formatBytes(state.totalBytes)}',
                style: FiloTypography.caption.copyWith(color: textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: FiloSpacing.md),
        Row(
          children: [
            Expanded(
              child: FiloButton(
                label: 'Pause & Save',
                variant: FiloButtonVariant.secondary,
                onPressed: state.status == VaultExportStatus.finalizing
                    ? null
                    : () => ref
                        .read(vaultExportProvider.notifier)
                        .pauseOrCancelExport(),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FiloButton(
                label: 'Run in Background',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResumableView(
    VaultExportState state,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    final hasFailures = state.failedFiles.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _infoCard(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hasFailures
                    ? '${state.completedFiles}/${state.totalFiles} files packed • ${state.failedFiles.length} failed'
                    : 'Paused: ${state.completedFiles}/${state.totalFiles} files ready',
                style: FiloTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${HashUtils.formatBytes(state.bytesTransferred)} of ${HashUtils.formatBytes(state.totalBytes)} saved in checkpoint.',
                style: FiloTypography.caption.copyWith(color: textSecondary),
              ),
              if (state.statusMessage != null) ...[
                const SizedBox(height: 6),
                Text(
                  state.statusMessage!,
                  style: FiloTypography.caption.copyWith(
                    color: hasFailures ? FiloColors.warning : textSecondary,
                  ),
                ),
              ],
              if (hasFailures) ...[
                const SizedBox(height: 8),
                ...state.failedFiles.take(3).map(
                      (f) => Text(
                        '• ${f.fileName}: ${f.error}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FiloTypography.caption.copyWith(
                          color: FiloColors.destructive,
                        ),
                      ),
                    ),
                if (state.failedFiles.length > 3)
                  Text(
                    '+ ${state.failedFiles.length - 3} more',
                    style: FiloTypography.caption.copyWith(
                      color: FiloColors.destructive,
                    ),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: FiloSpacing.md),
        FiloButton(
          label: hasFailures ? 'Retry Failed Files' : 'Resume Export',
          isFullWidth: true,
          onPressed: () => _resume(finalizePartialOnly: false),
        ),
        if (hasFailures && state.completedFiles > 0) ...[
          const SizedBox(height: 8),
          FiloButton(
            label: 'Finalize ZIP Without Failed',
            variant: FiloButtonVariant.secondary,
            isFullWidth: true,
            onPressed: () => _resume(finalizePartialOnly: true),
          ),
        ],
        const SizedBox(height: 8),
        FiloButton(
          label: 'Discard Progress',
          variant: FiloButtonVariant.destructive,
          isFullWidth: true,
          onPressed: () =>
              ref.read(vaultExportProvider.notifier).discardResumableExport(),
        ),
      ],
    );
  }

  Widget _buildCompletedView(
    VaultExportState state,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    final shareablePath = state.localShareableFilePath;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _infoCard(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: FiloColors.success,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Exported ${state.completedFiles} files (${HashUtils.formatBytes(state.totalBytes)})',
                      style: FiloTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              if (state.outputDisplayPath != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Saved to: ${state.outputDisplayPath}',
                  style: FiloTypography.caption.copyWith(color: textSecondary),
                ),
              ],
              if (state.failedFiles.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Skipped ${state.failedFiles.length} failed file(s): '
                  '${state.failedFiles.map((e) => e.fileName).take(3).join(', ')}',
                  style: FiloTypography.caption.copyWith(
                    color: FiloColors.warning,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: FiloSpacing.md),
        if (shareablePath != null && File(shareablePath).existsSync()) ...[
          Row(
            children: [
              Expanded(
                child: FiloButton(
                  label: 'Share Archive',
                  variant: FiloButtonVariant.secondary,
                  onPressed: () async {
                    await Share.shareXFiles(
                      [XFile(shareablePath, mimeType: 'application/zip')],
                      text:
                          '${AppConfig.appName} Complete Archive Backup (${state.completedFiles} files)',
                    );
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FiloButton(
                  label: 'Scrub Copy',
                  variant: FiloButtonVariant.destructive,
                  onPressed: () async {
                    await SessionCacheService.secureDeleteFile(
                      File(shareablePath),
                    );
                    await ref
                        .read(vaultExportProvider.notifier)
                        .discardResumableExport();
                    if (mounted) {
                      FiloToast.show(
                        context,
                        message: 'Local export copy securely erased',
                        type: FiloToastType.info,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        FiloButton(
          label: 'Start New Export',
          isFullWidth: true,
          onPressed: _startFresh,
        ),
      ],
    );
  }

  Widget _buildFailedView(
    VaultExportState state,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _infoCard(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Export Failed',
                style: FiloTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                  color: FiloColors.destructive,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                state.errorMessage ?? 'Unknown export error',
                style: FiloTypography.caption.copyWith(color: textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: FiloSpacing.md),
        FiloButton(
          label: state.resumableCheckpoint != null
              ? 'Resume Export'
              : 'Try Again',
          isFullWidth: true,
          onPressed: state.resumableCheckpoint != null
              ? () => _resume(finalizePartialOnly: false)
              : _startFresh,
        ),
      ],
    );
  }

  Widget _infoCard({required bool isDark, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: FiloRadius.roundedMd,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: child,
    );
  }
}
