import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/database/transfer_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/persona_provider.dart';
import '../../../../shared/components/filo_background.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../../shared/components/filo_glass.dart';
import '../../../../shared/components/filo_sheet.dart';
import '../../../../shared/components/filo_toast.dart';
import '../../../preview/presentation/screens/file_preview_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../../broadcast/presentation/widgets/broadcast_and_update_banner.dart';
import '../../../transfer/presentation/providers/transfer_provider.dart';
import '../../../transfer/presentation/screens/transfer_queue_sheet.dart';
import '../providers/file_browser_provider.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../domain/smart_tag.dart';
import '../../domain/workspace.dart';
import '../widgets/add_content_sheet.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/create_folder_dialog.dart';
import '../widgets/file_action_sheet.dart';
import '../widgets/file_grid_card.dart';
import '../widgets/file_list_row.dart';
import '../widgets/workspace_switcher_sheet.dart';
import 'trash_screen.dart';

/// Primary file manager interface.
///
/// Features:
/// - Handwritten cursive "cloud" with cloud outline icon in top header
/// - Horizontal Categories bar with clean iOS outline icons (no emojis)
/// - Artistic minimal "quiet space" empty state (no upload button block)
/// - Full transparent liquid glass bottom navbar with black filled active icons
/// - Pure, lightweight 120fps light theme
class FileBrowserScreen extends ConsumerStatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  ConsumerState<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends ConsumerState<FileBrowserScreen> {
  bool _isSearchActive = false;
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _handleUploadFile() async {
    final transferNotifier = ref.read(transferQueueProvider.notifier);
    final browserState = ref.read(fileBrowserProvider);

    try {
      final tags = browserState.selectedTagId != null ? [browserState.selectedTagId!] : const <String>[];
      final nodes = await transferNotifier.pickAndUploadFiles(
        parentId: browserState.currentFolderId,
        workspaceId: browserState.activeWorkspaceId,
        tags: tags,
        onTaskCreated: (node) {
          if (mounted) {
            ref.read(fileBrowserProvider.notifier).loadCurrentFolder();
          }
        },
      );
      if (mounted) {
        ref.read(fileBrowserProvider.notifier).loadCurrentFolder();
        if (nodes.isNotEmpty) {
          FiloToast.show(
            context,
            message: '${nodes.length} file${nodes.length > 1 ? 's' : ''} queued for upload',
            type: FiloToastType.success,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        FiloToast.show(
          context,
          message: 'Upload error: $e',
          type: FiloToastType.error,
        );
      }
    }
  }

  void _handleUploadMedia() async {
    final transferNotifier = ref.read(transferQueueProvider.notifier);
    final browserState = ref.read(fileBrowserProvider);

    try {
      final picker = ImagePicker();
      final medias = await picker.pickMultipleMedia();
      if (medias.isEmpty) return;

      final files = medias.map((m) => File(m.path)).toList();
      final tags = browserState.selectedTagId != null ? [browserState.selectedTagId!] : const <String>[];
      final nodes = await transferNotifier.uploadLocalFiles(
        files: files,
        parentId: browserState.currentFolderId,
        workspaceId: browserState.activeWorkspaceId,
        tags: tags,
        onTaskCreated: (node) {
          if (mounted) {
            ref.read(fileBrowserProvider.notifier).loadCurrentFolder();
          }
        },
      );
      if (mounted) {
        ref.read(fileBrowserProvider.notifier).loadCurrentFolder();
        if (nodes.isNotEmpty) {
          FiloToast.show(
            context,
            message: '${nodes.length} photo/video${nodes.length > 1 ? 's' : ''} queued for upload',
            type: FiloToastType.success,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        FiloToast.show(
          context,
          message: 'Media error: $e',
          type: FiloToastType.error,
        );
      }
    }
  }

  void _handleTakePhoto() async {
    final transferNotifier = ref.read(transferQueueProvider.notifier);
    final browserState = ref.read(fileBrowserProvider);

    try {
      final picker = ImagePicker();
      final photo = await picker.pickImage(source: ImageSource.camera);
      if (photo == null) return;

      final file = File(photo.path);
      final tags = browserState.selectedTagId != null ? [browserState.selectedTagId!] : const <String>[];
      await transferNotifier.uploadLocalFile(
        file: file,
        parentId: browserState.currentFolderId,
        workspaceId: browserState.activeWorkspaceId,
        tags: tags,
        onTaskCreated: (node) {
          if (mounted) {
            ref.read(fileBrowserProvider.notifier).loadCurrentFolder();
          }
        },
      );
      if (mounted) {
        ref.read(fileBrowserProvider.notifier).loadCurrentFolder();
        FiloToast.show(
          context,
          message: 'Photo captured & queued for encrypted upload',
          type: FiloToastType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        FiloToast.show(
          context,
          message: 'Camera error: $e',
          type: FiloToastType.error,
        );
      }
    }
  }

  void _showNewFolderDialog() {
    CreateFolderDialog.show(
      context,
      onCreate: (name) {
        ref.read(fileBrowserProvider.notifier).createFolder(name);
        FiloToast.show(context, message: 'Folder created', type: FiloToastType.success);
      },
    );
  }

  void _showCreateWorkspaceDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: isDark
                      ? const LinearGradient(
                          colors: [Color(0xFF1E1E2C), Color(0xFF26263A)],
                        )
                      : const LinearGradient(
                          colors: [Color(0xFFFFF9F7), Color(0xFFFBF4FF)],
                        ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.85),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: FiloColors.primary.withValues(alpha: 0.1),
                            borderRadius: FiloRadius.roundedMd,
                          ),
                          child: const Icon(
                            Icons.workspaces_outlined,
                            color: FiloColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'New Space',
                          style: FiloTypography.title3.copyWith(
                            fontWeight: FontWeight.w700,
                            fontFamily: FiloTypography.fontFamily,
                            color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Create an isolated space with dedicated encryption tags.',
                      style: FiloTypography.caption.copyWith(
                        fontFamily: FiloTypography.fontFamily,
                        color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.white.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        style: TextStyle(
                          fontFamily: FiloTypography.fontFamily,
                          fontSize: 15,
                          color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'E.g. Work, Personal, Archive',
                          hintStyle: TextStyle(
                            fontFamily: FiloTypography.fontFamily,
                            color: isDark ? Colors.white38 : FiloColors.lightTextTertiary,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: (val) {
                          final name = val.trim();
                          if (name.isNotEmpty) {
                            Navigator.of(ctx).pop();
                            ref.read(fileBrowserProvider.notifier).addWorkspace(name);
                            FiloToast.show(context, message: 'Created & switched to $name', type: FiloToastType.success);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontFamily: FiloTypography.fontFamily,
                              color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FiloButton(
                          label: 'Create',
                          size: FiloButtonSize.small,
                          onPressed: () {
                            final name = controller.text.trim();
                            if (name.isNotEmpty) {
                              Navigator.of(ctx).pop();
                              ref.read(fileBrowserProvider.notifier).addWorkspace(name);
                              FiloToast.show(context, message: 'Created & switched to $name', type: FiloToastType.success);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showTagManagerDialog(FileNode node) {
    final currentTags = List<String>.from(node.tags);
    FiloSheet.show(
      context: context,
      title: 'Smart Tags',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          node.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: FiloTypography.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: FiloColors.lightTextSecondary,
          ),
        ),
      ),
      child: StatefulBuilder(
        builder: (ctx, setSheetState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assign smart tags to organize "${node.name}" for instant access.',
                style: FiloTypography.caption.copyWith(
                  fontFamily: FiloTypography.fontFamily,
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 16),
              ...SmartTag.defaultTags.map((tag) {
                final isTagged = currentTags.contains(tag.id);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: isTagged
                        ? (isDark
                            ? tag.color.withValues(alpha: 0.18)
                            : tag.bgColor)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.white.withValues(alpha: 0.72)),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setSheetState(() {
                          if (isTagged) {
                            currentTags.remove(tag.id);
                          } else {
                            currentTags.add(tag.id);
                          }
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isTagged
                                ? tag.color.withValues(alpha: 0.6)
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.05)),
                            width: isTagged ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: tag.color.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                tag.icon,
                                color: tag.color,
                                size: 17,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                tag.name,
                                style: TextStyle(
                                  fontFamily: FiloTypography.fontFamily,
                                  fontSize: 14.5,
                                  fontWeight: isTagged ? FontWeight.w700 : FontWeight.w600,
                                  color: isTagged
                                      ? (isDark ? Colors.white : FiloColors.lightTextPrimary)
                                      : (isDark ? Colors.white70 : FiloColors.lightTextPrimary),
                                ),
                              ),
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: isTagged ? tag.color : Colors.transparent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isTagged
                                      ? tag.color
                                      : (isDark ? Colors.white30 : Colors.black26),
                                  width: 1.5,
                                ),
                              ),
                              child: isTagged
                                  ? const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 15,
                                    )
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontFamily: FiloTypography.fontFamily,
                        color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FiloButton(
                    label: 'Save Tags',
                    size: FiloButtonSize.small,
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      ref.read(fileBrowserProvider.notifier).updateNodeTags(node.id, currentTags);
                      FiloToast.show(context, message: 'Tags updated', type: FiloToastType.success);
                    },
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _showChangeWorkspaceDialog(FileNode node) {
    final workspaces = ref.read(fileBrowserProvider).workspaces;
    FiloSheet.show(
      context: context,
      title: 'Move to Space',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          node.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: FiloTypography.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: FiloColors.lightTextSecondary,
          ),
        ),
      ),
      child: Builder(
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose a space to relocate "${node.name}".',
                style: FiloTypography.caption.copyWith(
                  fontFamily: FiloTypography.fontFamily,
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 16),
              ...workspaces.map((ws) {
                final isCurrent = node.workspaceId == ws.id;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: isCurrent
                        ? (isDark
                            ? FiloColors.primary.withValues(alpha: 0.15)
                            : FiloColors.primary.withValues(alpha: 0.06))
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.white.withValues(alpha: 0.72)),
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.of(ctx).pop();
                        ref.read(fileBrowserProvider.notifier).updateNodeWorkspace(node.id, ws.id);
                        FiloToast.show(context, message: 'Moved to ${ws.name}', type: FiloToastType.success);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isCurrent
                                ? FiloColors.primary.withValues(alpha: 0.5)
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.05)),
                            width: isCurrent ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? FiloColors.primary.withValues(alpha: 0.15)
                                    : (isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.black.withValues(alpha: 0.04)),
                                borderRadius: FiloRadius.roundedMd,
                              ),
                              child: Icon(
                                ws.icon,
                                color: isCurrent
                                    ? FiloColors.primary
                                    : (isDark ? Colors.white70 : FiloColors.lightTextPrimary),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ws.name,
                                    style: TextStyle(
                                      fontFamily: FiloTypography.fontFamily,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    ws.description,
                                    style: TextStyle(
                                      fontFamily: FiloTypography.fontFamily,
                                      fontSize: 11.5,
                                      color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isCurrent)
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: FiloColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              )
                            else
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.3)
                                    : Colors.black.withValues(alpha: 0.2),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  void _handleFileTap(FileNode node) {
    final notifier = ref.read(fileBrowserProvider.notifier);
    final state = ref.read(fileBrowserProvider);

    if (state.isMultiSelect) {
      notifier.toggleSelect(node.id);
    } else if (node.isFolder) {
      notifier.navigateToFolder(node.id);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => FilePreviewScreen(node: node),
        ),
      );
    }
  }

  void _showFileActions(FileNode node) {
    final notifier = ref.read(fileBrowserProvider.notifier);

    FileActionSheet.show(
      context,
      node: node,
      onToggleFavorite: () => notifier.toggleFavorite(node.id, !node.isFavorite),
      onRename: () => _showRenameDialog(node),
      onMove: () => _showMoveDialog(node),
      onShare: () => _handleShareFile(node),
      onDownload: () => _handleDownloadFile(node),
      onManageTags: () => _showTagManagerDialog(node),
      onChangeWorkspace: () => _showChangeWorkspaceDialog(node),
      onDelete: () {
        notifier.moveToTrash(node.id);
        FiloToast.show(context, message: '${node.name} moved to trash', type: FiloToastType.info);
      },
    );
  }

  void _handleDownloadFile(FileNode node) async {
    FiloToast.show(context, message: 'Downloading ${node.name}...', type: FiloToastType.info);
    try {
      await ref.read(transferQueueProvider.notifier).downloadFileToDevice(node);
      if (mounted) {
        FiloToast.show(context, message: 'Saved ${node.name} to Downloads', type: FiloToastType.success);
      }
    } catch (e) {
      if (mounted) {
        FiloToast.show(context, message: 'Download failed: $e', type: FiloToastType.error);
      }
    }
  }

  void _showRenameDialog(FileNode node) {
    final controller = TextEditingController(text: node.name);
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: isDark
                      ? const LinearGradient(
                          colors: [Color(0xFF1E1E2C), Color(0xFF26263A)],
                        )
                      : const LinearGradient(
                          colors: [Color(0xFFFFF9F7), Color(0xFFFBF4FF)],
                        ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.85),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: FiloColors.primary.withValues(alpha: 0.1),
                            borderRadius: FiloRadius.roundedMd,
                          ),
                          child: Icon(
                            node.isFolder ? Icons.folder_outlined : Icons.edit_outlined,
                            color: FiloColors.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            node.isFolder ? 'Rename Folder' : 'Rename File',
                            style: FiloTypography.title3.copyWith(
                              fontWeight: FontWeight.w700,
                              fontFamily: FiloTypography.fontFamily,
                              color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      node.isFolder
                          ? 'Enter a new name for this folder.'
                          : 'Enter a new name for this file.',
                      style: FiloTypography.caption.copyWith(
                        fontFamily: FiloTypography.fontFamily,
                        color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.white.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.12)
                              : Colors.black.withValues(alpha: 0.08),
                        ),
                      ),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        textCapitalization: TextCapitalization.sentences,
                        style: TextStyle(
                          fontFamily: FiloTypography.fontFamily,
                          fontSize: 15,
                          color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: node.isFolder ? 'Folder name' : 'File name',
                          hintStyle: TextStyle(
                            fontFamily: FiloTypography.fontFamily,
                            color: isDark ? Colors.white38 : FiloColors.lightTextTertiary,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onSubmitted: (val) {
                          final newName = val.trim();
                          if (newName.isNotEmpty) {
                            ref.read(fileBrowserProvider.notifier).renameNode(node.id, newName);
                            Navigator.of(ctx).pop();
                            FiloToast.show(context, message: 'Renamed successfully', type: FiloToastType.success);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              fontFamily: FiloTypography.fontFamily,
                              color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FiloButton(
                          label: 'Save',
                          size: FiloButtonSize.small,
                          onPressed: () {
                            final newName = controller.text.trim();
                            if (newName.isNotEmpty) {
                              ref.read(fileBrowserProvider.notifier).renameNode(node.id, newName);
                              Navigator.of(ctx).pop();
                              FiloToast.show(context, message: 'Renamed successfully', type: FiloToastType.success);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showMoveDialog(FileNode node) async {
    final repo = ref.read(fileRepositoryProvider);
    final folders = await repo.getFolders();
    final candidateFolders = folders.where((f) => f.id != node.id).toList();

    if (!mounted) return;

    FiloSheet.show(
      context: context,
      title: 'Move to Folder',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          node.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: FiloTypography.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: FiloColors.lightTextSecondary,
          ),
        ),
      ),
      child: Builder(
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select a destination folder for "${node.name}".',
                style: FiloTypography.caption.copyWith(
                  fontFamily: FiloTypography.fontFamily,
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 16),
              // Vault Root Destination Option
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isDark
                      ? const Color(0xFF222234)
                      : Colors.white.withValues(alpha: 0.82),
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(ctx).pop();
                      ref.read(fileBrowserProvider.notifier).moveNode(node.id, null);
                      FiloToast.show(context, message: 'Moved to Vault Root', type: FiloToastType.success);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.05),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: FiloColors.primary.withValues(alpha: 0.1),
                              borderRadius: FiloRadius.roundedMd,
                            ),
                            child: const Icon(
                              Icons.cloud_outlined,
                              color: FiloColors.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Vault Root',
                                  style: TextStyle(
                                    fontFamily: FiloTypography.fontFamily,
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Top-level space directory',
                                  style: TextStyle(
                                    fontFamily: FiloTypography.fontFamily,
                                    fontSize: 11.5,
                                    color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.3)
                                : Colors.black.withValues(alpha: 0.2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (candidateFolders.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Folders',
                    style: TextStyle(
                      fontFamily: FiloTypography.fontFamily,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                    ),
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.32,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: candidateFolders.length,
                    itemBuilder: (c, idx) {
                      final folder = candidateFolders[idx];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: isDark
                              ? const Color(0xFF222234)
                              : Colors.white.withValues(alpha: 0.82),
                          borderRadius: BorderRadius.circular(18),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(ctx).pop();
                              ref.read(fileBrowserProvider.notifier).moveNode(node.id, folder.id);
                              FiloToast.show(
                                context,
                                message: 'Moved to ${folder.name}',
                                type: FiloToastType.success,
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.05),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: FiloColors.accentCoral.withValues(alpha: 0.12),
                                      borderRadius: FiloRadius.roundedMd,
                                    ),
                                    child: const Icon(
                                      Icons.folder_outlined,
                                      color: FiloColors.accentCoral,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      folder.name,
                                      style: TextStyle(
                                        fontFamily: FiloTypography.fontFamily,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                        color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                                      ),
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 20,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.3)
                                        : Colors.black.withValues(alpha: 0.2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _handleShareFile(FileNode node) async {
    // BUG 8 FIX: Decrypt and invoke OS share sheet
    FiloToast.show(context, message: 'Decrypting ${node.name}...', type: FiloToastType.info);
    try {
      await ref.read(transferQueueProvider.notifier).shareDecryptedCopy(node);
    } catch (e) {
      if (mounted) {
        FiloToast.show(context, message: 'Share failed: $e', type: FiloToastType.error);
      }
    }
  }

  void _navigateUp() {
    final state = ref.read(fileBrowserProvider);
    final notifier = ref.read(fileBrowserProvider.notifier);
    if (state.breadcrumbs.length > 1) {
      notifier.navigateToFolder(state.breadcrumbs[state.breadcrumbs.length - 2].id);
    } else {
      notifier.navigateToFolder(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fileBrowserProvider);
    final notifier = ref.read(fileBrowserProvider.notifier);

    final tasks = ref.watch(transferQueueProvider);
    final activeTasks = tasks.where((t) => t.status == TransferStatus.running).toList();
    final activeTasksCount = activeTasks.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeWorkspace = Workspace.fromId(state.activeWorkspaceId, state.workspaces);

    return Scaffold(
      body: FiloBackground(
        child: SafeArea(
          bottom: false,
          child: Stack(
          children: [
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // 1. Top Header: Handwritten "cloud" with Cloud Outline Icon
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      FiloSpacing.xl,
                      FiloSpacing.sm,
                      FiloSpacing.xl,
                      FiloSpacing.xs,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (state.currentFolderId != null)
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                            onPressed: _navigateUp,
                          )
                        else
                          // Space Switcher Pill (Properly fitted, flexible, no overflow)
                          Flexible(
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                WorkspaceSwitcherSheet.show(
                                  context,
                                  activeWorkspaceId: state.activeWorkspaceId,
                                  workspaces: state.workspaces,
                                  onWorkspaceSelected: (wsId) {
                                    notifier.setActiveWorkspace(wsId);
                                  },
                                  onAddWorkspace: () {
                                    _showCreateWorkspaceDialog();
                                  },
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.white.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(100),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.15)
                                        : Colors.black.withValues(alpha: 0.08),
                                    width: 1.2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      activeWorkspace.icon,
                                      size: 16,
                                      color: isDark ? Colors.white : FiloColors.primary,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        activeWorkspace.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: FiloTypography.fontFamily,
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                                          letterSpacing: -0.2,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 16,
                                      color: isDark ? Colors.white70 : Colors.black45,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(width: 8),
                        Row(
                          children: [
                            _buildHeaderIconButton(
                              icon: _isSearchActive ? Icons.close_rounded : Icons.search_rounded,
                              onTap: () {
                                setState(() {
                                  _isSearchActive = !_isSearchActive;
                                  if (!_isSearchActive) {
                                    _searchController.clear();
                                    notifier.setSearchQuery(null);
                                  }
                                });
                              },
                            ),
                            const SizedBox(width: 6),
                            _buildHeaderIconButton(
                              icon: Icons.notifications_none_rounded,
                              onTap: () => TransferQueueSheet.show(context),
                              badgeCount: activeTasksCount > 0 ? activeTasksCount : null,
                            ),
                            const SizedBox(width: 6),
                            _buildHeaderIconButton(
                              icon: Icons.delete_outline_rounded,
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (context) => const TrashScreen()),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 1.2 Admin Broadcast & Update Banner (Theme-synced, persistent, polite)
                const SliverToBoxAdapter(
                  child: BroadcastAndUpdateBanner(),
                ),

                // Search Bar if Active
                if (_isSearchActive)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: FiloSpacing.xl, vertical: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? FiloColors.darkSurface
                              : Colors.white,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.white.withValues(alpha: 0.12)
                                : Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          style: FiloTypography.bodyMedium.copyWith(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? FiloColors.darkTextPrimary
                                : FiloColors.lightTextPrimary,
                          ),
                          decoration: InputDecoration(
                            filled: false,
                            fillColor: Colors.transparent,
                            hintText: 'Search files and folders...',
                            hintStyle: FiloTypography.body.copyWith(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? FiloColors.darkTextTertiary
                                  : FiloColors.lightTextTertiary,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          ),
                          onChanged: (val) => notifier.setSearchQuery(val),
                        ),
                      ),
                    ),
                  ),

                // 2. Categories Option (Directly in place of card, with iOS outline icons, NO emojis)
                if (state.currentFolderId == null && !_isSearchActive)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        FiloSpacing.xl,
                        FiloSpacing.md,
                        FiloSpacing.xl,
                        FiloSpacing.xs,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Categories',
                            style: FiloTypography.title3.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? FiloColors.darkTextPrimary
                                  : FiloColors.lightTextPrimary,
                            ),
                          ),
                          GestureDetector(
                            onTap: _showNewFolderDialog,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.white.withValues(alpha: 0.8),
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.12)
                                      : Colors.black.withValues(alpha: 0.08),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.add_rounded,
                                    size: 15,
                                    color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Folder',
                                    style: FiloTypography.caption.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (state.currentFolderId == null && !_isSearchActive)
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 110,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: FiloSpacing.xl, vertical: 8),
                        physics: const BouncingScrollPhysics(),
                        children: [
                          _buildCategoryCard(
                            title: 'Photos',
                            icon: Icons.photo_outlined,
                            count: '${state.items.where((i) => (i.mimeType?.startsWith('image/') ?? false) || i.name.toLowerCase().endsWith('.jpg') || i.name.toLowerCase().endsWith('.png') || i.name.toLowerCase().endsWith('.jpeg') || i.name.toLowerCase().endsWith('.webp') || i.name.toLowerCase().endsWith('.heic')).length} files',
                          ),
                          const SizedBox(width: 12),
                          _buildCategoryCard(
                            title: 'Videos',
                            icon: Icons.videocam_outlined,
                            count: '${state.items.where((i) => (i.mimeType?.startsWith('video/') ?? false) || i.name.toLowerCase().endsWith('.mp4') || i.name.toLowerCase().endsWith('.mov') || i.name.toLowerCase().endsWith('.mkv')).length} files',
                          ),
                          const SizedBox(width: 12),
                          _buildCategoryCard(
                            title: 'Docs',
                            icon: Icons.description_outlined,
                            count: '${state.items.where((i) => (i.mimeType?.contains('pdf') ?? false) || (i.mimeType?.contains('document') ?? false) || (i.mimeType?.contains('text') ?? false) || i.name.toLowerCase().endsWith('.pdf') || i.name.toLowerCase().endsWith('.txt') || i.name.toLowerCase().endsWith('.docx') || i.name.toLowerCase().endsWith('.xlsx')).length} files',
                          ),
                          const SizedBox(width: 12),
                          _buildCategoryCard(
                            title: 'Audio',
                            icon: Icons.headphones_outlined,
                            count: '${state.items.where((i) => (i.mimeType?.startsWith('audio/') ?? false) || i.name.toLowerCase().endsWith('.mp3') || i.name.toLowerCase().endsWith('.m4a') || i.name.toLowerCase().endsWith('.flac') || i.name.toLowerCase().endsWith('.wav')).length} files',
                          ),
                          const SizedBox(width: 12),
                          _buildCategoryCard(
                            title: 'Folders',
                            icon: Icons.folder_outlined,
                            count: '${state.items.where((i) => i.isFolder).length} folders',
                          ),
                        ],
                      ),
                    ),
                  ),

                // Smart Tags horizontal chip selector
                if (state.currentFolderId == null && !_isSearchActive)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, bottom: 4),
                      child: SizedBox(
                        height: 36,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: FiloSpacing.xl),
                          physics: const BouncingScrollPhysics(),
                          children: [
                            // "All" Chip
                            _buildTagChip(
                              label: 'All',
                              icon: Icons.grid_view_rounded,
                              isSelected: state.selectedTagId == null,
                              onTap: () => notifier.setSelectedTag(null),
                              isDark: isDark,
                            ),
                            const SizedBox(width: 8),
                            // Smart tags list
                            ...SmartTag.defaultTags.map((tag) {
                              final isSelected = state.selectedTagId == tag.id;
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _buildTagChip(
                                  label: tag.name,
                                  icon: tag.icon,
                                  tagDotColor: tag.color,
                                  isSelected: isSelected,
                                  onTap: () => notifier.setSelectedTag(tag.id),
                                  isDark: isDark,
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Breadcrumbs if inside a subfolder
                if (!state.isMultiSelect && state.breadcrumbs.isNotEmpty)
                  SliverToBoxAdapter(
                    child: BreadcrumbBar(
                      breadcrumbs: state.breadcrumbs,
                      onNavigate: (folderId) => notifier.navigateToFolder(folderId),
                    ),
                  ),

                // 3. Recent Files Section Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      FiloSpacing.xl,
                      FiloSpacing.md,
                      FiloSpacing.xl,
                      FiloSpacing.xs,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          state.currentFolderId == null ? 'Recent Files' : 'Files',
                          style: FiloTypography.title3.copyWith(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: Theme.of(context).brightness == Brightness.dark
                                ? FiloColors.darkTextPrimary
                                : FiloColors.lightTextPrimary,
                          ),
                        ),
                        IconButton(
                          icon: Icon(state.isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded, size: 20),
                          onPressed: () => notifier.toggleViewMode(),
                        ),
                      ],
                    ),
                  ),
                ),

                // 4. Files List / Grid / Unique Artistic Empty Space (No button block)
                if (state.isLoading)
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(FiloColors.primary),
                      ),
                    ),
                  )
                else if (state.items.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 120),
                      child: _buildUniqueEmptySpace(state.isFavoritesOnly),
                    ),
                  )
                else if (state.isGridView)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      FiloSpacing.xl,
                      FiloSpacing.xs,
                      FiloSpacing.xl,
                      120,
                    ),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: FiloSpacing.md,
                        mainAxisSpacing: FiloSpacing.md,
                        childAspectRatio: 0.85,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final node = state.items[index];
                          return FileGridCard(
                            node: node,
                            isSelected: state.selectedIds.contains(node.id),
                            isSelectionMode: state.isMultiSelect,
                            onTap: () => _handleFileTap(node),
                            onLongPress: () => _showFileActions(node),
                            onMoreTap: () => _showFileActions(node),
                          );
                        },
                        childCount: state.items.length,
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      FiloSpacing.xl,
                      FiloSpacing.xs,
                      FiloSpacing.xl,
                      120,
                    ),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final node = state.items[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: FileListRow(
                              node: node,
                              isSelected: state.selectedIds.contains(node.id),
                              isSelectionMode: state.isMultiSelect,
                              onTap: () => _handleFileTap(node),
                              onLongPress: () => _showFileActions(node),
                              onMoreTap: () => _showFileActions(node),
                            ),
                          );
                        },
                        childCount: state.items.length,
                      ),
                    ),
                  ),
              ],
            ),

            // 4. Dynamic Island Active Transfer Pill
            if (activeTasks.isNotEmpty)
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: _buildDynamicIsland(activeTasks, isDark),
              ),

            // 5. Full Transparent Liquid Glass Bottom Navbar (Exact 5 Options, Black Filled Icons)
            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: _buildTransparentNavbar(state.isFavoritesOnly, activeTasksCount),
            ),
          ],
        ),
      ),
    ),
  );
  }

  // Dynamic Island Floating Transfer Pill
  Widget _buildDynamicIsland(List<TransferTask> activeTasks, bool isDark) {
    if (activeTasks.isEmpty) return const SizedBox.shrink();

    final task = activeTasks.first;
    final totalBytes = activeTasks.fold<int>(0, (sum, t) => sum + t.totalBytes);
    final transferredBytes = activeTasks.fold<int>(0, (sum, t) => sum + t.bytesTransferred);
    final progress = totalBytes > 0 ? (transferredBytes / totalBytes).clamp(0.0, 1.0) : 0.0;
    final pct = (progress * 100).toInt();

    return Center(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          TransferQueueSheet.show(context);
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E22).withValues(alpha: 0.95) : Colors.black,
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: isDark ? 0.15 : 0.2),
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.arrow_upward_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      activeTasks.length == 1
                          ? task.fileName
                          : 'Syncing ${activeTasks.length} files',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 60,
                          height: 3,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.white24,
                              valueColor: const AlwaysStoppedAnimation<Color>(FiloColors.accentCoral),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$pct%',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Unique Artistic Empty State (Editorial Monoline & Frosted Glass)
  Widget _buildUniqueEmptySpace(bool isFavoritesOnly) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final illustrationAsset = isFavoritesOnly
        ? FiloIllustrations.starred
        : FiloIllustrations.emptyVault;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FiloIllustrationView(
            assetName: illustrationAsset,
            maxHeight: 250,
            maxWidth: 280,
          ),
          const SizedBox(height: FiloSpacing.lg),
          Text(
            isFavoritesOnly ? 'no starred files' : 'your vault is clear',
            style: FiloTypography.title2.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 22,
              letterSpacing: -0.5,
              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              isFavoritesOnly
                  ? 'star files to keep them one tap away'
                  : 'your encrypted vault is peaceful and ready.\ntap + below to store your first file',
              textAlign: TextAlign.center,
              style: FiloTypography.body.copyWith(
                color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Category Squircle Card (Clean iOS Outline Icons, NO emojis)
  Widget _buildCategoryCard({
    required String title,
    required IconData icon,
    required String count,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 125,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? FiloColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: FiloColors.primary),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontFamily: FiloTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            count,
            style: TextStyle(
              fontFamily: FiloTypography.fontFamily,
              fontSize: 12,
              color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
    Color? tagDotColor,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white : FiloColors.primary)
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.8)),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(
            color: isSelected
                ? (isDark ? Colors.white : FiloColors.primary)
                : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.06)),
            width: isSelected ? 1.2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.15 : 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tagDotColor != null && !isSelected) ...[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: tagDotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
            ] else ...[
              Icon(
                icon,
                size: 13,
                color: isSelected
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark ? Colors.white60 : Colors.black54),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark ? Colors.white70 : FiloColors.lightTextPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderIconButton({
    required IconData icon,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.06),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              icon,
              size: 18,
              color: FiloColors.lightTextPrimary,
            ),
          ),
          if (badgeCount != null)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 5. Full Transparent Liquid Glass Navbar (5 Options, Black Filled Active Icons)
  Widget _buildTransparentNavbar(bool isFavoritesOnly, int activeTasksCount) {
    return FiloGlass(
      borderRadius: BorderRadius.circular(40),
      blur: 32.0,
      color: Colors.white.withValues(alpha: 0.72),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      border: Border.all(
        color: Colors.white.withValues(alpha: 0.9),
        width: 1.5,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 28,
          offset: const Offset(0, 10),
        ),
      ],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // 1. Home (Black filled when active)
          _buildNavIcon(
            activeIcon: Icons.home_filled,
            inactiveIcon: Icons.home_outlined,
            isActive: !isFavoritesOnly,
            onTap: () {
              if (isFavoritesOnly) {
                ref.read(fileBrowserProvider.notifier).toggleFavoritesFilter();
              }
            },
          ),

          // 2. Starred (Black filled when active)
          _buildNavIcon(
            activeIcon: Icons.star_rounded,
            inactiveIcon: Icons.star_border_rounded,
            isActive: isFavoritesOnly,
            onTap: () {
              ref.read(fileBrowserProvider.notifier).toggleFavoritesFilter();
            },
          ),

          // 3. Add to Vault (Center Action: Folders, Files, Photos/Videos, Camera Scan)
          GestureDetector(
            onTap: () async {
              HapticFeedback.mediumImpact();
              final action = await AddContentSheet.show(context);
              if (action == null) return;
              switch (action) {
                case AddContentAction.newFolder:
                  _showNewFolderDialog();
                  break;
                case AddContentAction.uploadFiles:
                  _handleUploadFile();
                  break;
                case AddContentAction.uploadMedia:
                  _handleUploadMedia();
                  break;
                case AddContentAction.takePhoto:
                  _handleTakePhoto();
                  break;
              }
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Colors.black,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),

          // 4. Transfers
          _buildNavIcon(
            activeIcon: Icons.swap_vert_rounded,
            inactiveIcon: Icons.swap_vert_rounded,
            isActive: activeTasksCount > 0,
            badgeCount: activeTasksCount > 0 ? activeTasksCount : null,
            onTap: () => TransferQueueSheet.show(context),
          ),

          // 5. Settings
          _buildNavIcon(
            activeIcon: Icons.settings_rounded,
            inactiveIcon: Icons.settings_outlined,
            isActive: false,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavIcon({
    required IconData activeIcon,
    required IconData inactiveIcon,
    required bool isActive,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              isActive ? activeIcon : inactiveIcon,
              size: 24,
              color: isActive ? Colors.black : Colors.black.withValues(alpha: 0.38),
            ),
          ),
          if (badgeCount != null)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.black,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
