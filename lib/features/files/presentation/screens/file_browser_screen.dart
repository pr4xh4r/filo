import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/theme_provider.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../../shared/components/filo_empty_state.dart';
import '../../../../shared/components/filo_sheet.dart';
import '../../../../shared/components/filo_toast.dart';
import '../../../preview/presentation/screens/file_preview_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../../../core/database/transfer_model.dart';
import '../../../transfer/presentation/providers/transfer_provider.dart';
import '../../../transfer/presentation/screens/transfer_queue_sheet.dart';
import '../../../transfer/presentation/widgets/floating_transfer_capsule.dart';
import '../providers/file_browser_provider.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/create_folder_dialog.dart';
import '../widgets/file_action_sheet.dart';
import '../widgets/file_grid_card.dart';
import '../widgets/file_list_row.dart';
import 'trash_screen.dart';

/// Primary file manager interface.
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

    await transferNotifier.pickAndUploadFile(
      parentId: browserState.currentFolderId,
      onTaskCreated: (node) {
        // Immediately reload current folder so the item appears with real-time transfer progress!
        if (mounted) {
          ref.read(fileBrowserProvider.notifier).loadCurrentFolder();
        }
      },
    );
    if (mounted) {
      ref.read(fileBrowserProvider.notifier).loadCurrentFolder();
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
      onDelete: () {
        notifier.moveToTrash(node.id);
        FiloToast.show(context, message: '${node.name} moved to Trash', type: FiloToastType.info);
      },
    );
  }

  void _handleDownloadFile(FileNode node) async {
    FiloToast.show(context, message: 'Downloading ${node.name}...', type: FiloToastType.info);
    try {
      await ref.read(transferQueueProvider.notifier).downloadFileToDevice(node);
      if (mounted) {
        FiloToast.show(context, message: 'Saved ${node.name} to device Downloads', type: FiloToastType.success);
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
      builder: (context) => AlertDialog(
        title: const Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FiloButton(
            label: 'Rename',
            size: FiloButtonSize.small,
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                ref.read(fileBrowserProvider.notifier).renameNode(node.id, newName);
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }

  void _showMoveDialog(FileNode node) {
    // Moves to root folder as default target
    ref.read(fileBrowserProvider.notifier).moveNode(node.id, null);
    FiloToast.show(context, message: 'Moved to Vault Root', type: FiloToastType.success);
  }

  void _handleShareFile(FileNode node) async {
    FiloToast.show(context, message: 'Decrypting file for sharing...', type: FiloToastType.info);
    await ref.read(transferQueueProvider.notifier).shareDecryptedCopy(node);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fileBrowserProvider);
    final notifier = ref.read(fileBrowserProvider.notifier);
    final isDark = ref.watch(isDarkProvider);
    final currentFolderName = state.breadcrumbs.isNotEmpty
        ? state.breadcrumbs.last.name
        : 'Vault';

    // Auto-refresh folder list in real time whenever any transfer starts, progresses, or finishes
    ref.listen<List<TransferTask>>(transferQueueProvider, (prev, next) {
      final prevRunning = prev?.where((t) => t.status == TransferStatus.running).length ?? 0;
      final nextRunning = next.where((t) => t.status == TransferStatus.running).length;
      final prevCompleted = prev?.where((t) => t.status == TransferStatus.completed).length ?? 0;
      final nextCompleted = next.where((t) => t.status == TransferStatus.completed).length;

      if (nextCompleted > prevCompleted || (prevRunning > 0 && nextRunning == 0) || ((prev?.length ?? 0) != next.length)) {
        ref.read(fileBrowserProvider.notifier).loadCurrentFolder();
      }
    });

    final tasks = ref.watch(transferQueueProvider);
    final activeTaskMap = <String, TransferTask>{};
    for (final t in tasks) {
      if (t.status == TransferStatus.running) {
        activeTaskMap[t.nodeId] = t;
      }
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: isDark
            ? FiloColors.darkBackground.withValues(alpha: 0.82)
            : FiloColors.lightBackground.withValues(alpha: 0.85),
        elevation: 0,
        scrolledUnderElevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: _isSearchActive
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search files & folders...',
                  border: InputBorder.none,
                ),
                onChanged: (val) => notifier.setSearchQuery(val),
              )
            : Text(
                state.isMultiSelect
                    ? '${state.selectedIds.length} selected'
                    : currentFolderName,
              ),
        actions: [
          if (state.isMultiSelect) ...[
            IconButton(
              icon: const Icon(Icons.select_all_rounded),
              onPressed: () => notifier.selectAll(),
              tooltip: 'Select All',
            ),
            IconButton(
              icon: const Icon(Icons.delete_rounded),
              color: FiloColors.destructive,
              onPressed: () => notifier.deleteSelected(),
              tooltip: 'Delete Selected',
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => notifier.clearSelection(),
              tooltip: 'Cancel',
            ),
          ] else ...[
            IconButton(
              icon: Icon(_isSearchActive ? Icons.close_rounded : Icons.search_rounded),
              onPressed: () {
                setState(() {
                  _isSearchActive = !_isSearchActive;
                  if (!_isSearchActive) {
                    _searchController.clear();
                    notifier.setSearchQuery(null);
                  }
                });
              },
            ),
            IconButton(
              icon: Icon(
                state.isFavoritesOnly ? Icons.star_rounded : Icons.star_border_rounded,
                color: state.isFavoritesOnly ? FiloColors.warning : null,
              ),
              onPressed: () => notifier.toggleFavoritesFilter(),
              tooltip: 'Favorites Filter',
            ),
            IconButton(
              icon: Icon(state.isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded),
              onPressed: () => notifier.toggleViewMode(),
              tooltip: 'Toggle View Mode',
            ),
            IconButton(
              icon: const Icon(Icons.swap_vert_rounded),
              onPressed: () => TransferQueueSheet.show(context),
              tooltip: 'Transfers',
            ),
            PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'trash') {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const TrashScreen()),
                  );
                } else if (val == 'settings') {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => const SettingsScreen()),
                  );
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'trash',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline_rounded, size: 20),
                      SizedBox(width: 8),
                      Text('Trash'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings_outlined, size: 20),
                      SizedBox(width: 8),
                      Text('Settings'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
          // Breadcrumbs Bar
          if (!state.isMultiSelect)
            BreadcrumbBar(
              breadcrumbs: state.breadcrumbs,
              onNavigate: (folderId) => notifier.navigateToFolder(folderId),
            ),

          // Content Area
          Expanded(
            child: state.isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(FiloColors.primary),
                    ),
                  )
                : state.items.isEmpty
                    ? FiloEmptyState(
                        icon: state.isFavoritesOnly
                            ? Icons.star_border_rounded
                            : Icons.cloud_queue_rounded,
                        title: state.isFavoritesOnly
                            ? 'No Starred Files'
                            : 'This Folder is Empty',
                        description: state.isFavoritesOnly
                            ? 'Star your important files to access them quickly.'
                            : 'Upload documents, photos, or videos to your encrypted Telegram vault.',
                        actionLabel: state.isFavoritesOnly ? null : 'Upload File',
                        onAction: state.isFavoritesOnly ? null : _handleUploadFile,
                      )
                    : RefreshIndicator(
                        onRefresh: () async {
                          HapticFeedback.lightImpact();
                          await notifier.loadCurrentFolder();
                        },
                        child: state.isGridView
                            ? GridView.builder(
                                padding: const EdgeInsets.all(FiloSpacing.lg),
                                physics: const AlwaysScrollableScrollPhysics(),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: FiloSpacing.md,
                                  crossAxisSpacing: FiloSpacing.md,
                                  childAspectRatio: 0.88,
                                ),
                                itemCount: state.items.length,
                                itemBuilder: (context, index) {
                                  final item = state.items[index];
                                  final activeTask = activeTaskMap[item.id];
                                  return FileGridCard(
                                    node: item,
                                    isSelected: state.selectedIds.contains(item.id),
                                    isSelectionMode: state.isMultiSelect,
                                    isTransferring: activeTask != null,
                                    transferProgress: activeTask?.progress,
                                    onTap: () => _handleFileTap(item),
                                    onLongPress: () {
                                      HapticFeedback.mediumImpact();
                                      notifier.toggleSelect(item.id);
                                    },
                                    onMoreTap: () => _showFileActions(item),
                                  );
                                },
                              )
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: state.items.length,
                                separatorBuilder: (context, index) => Divider(
                                  color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
                                  height: 1,
                                ),
                                itemBuilder: (context, index) {
                                  final item = state.items[index];
                                  final activeTask = activeTaskMap[item.id];
                                  return FileListRow(
                                    node: item,
                                    isSelected: state.selectedIds.contains(item.id),
                                    isSelectionMode: state.isMultiSelect,
                                    isTransferring: activeTask != null,
                                    transferProgress: activeTask?.progress,
                                    onTap: () => _handleFileTap(item),
                                    onLongPress: () {
                                      HapticFeedback.mediumImpact();
                                      notifier.toggleSelect(item.id);
                                    },
                                    onMoreTap: () => _showFileActions(item),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
      const Positioned(
        left: FiloSpacing.md,
        right: FiloSpacing.md,
        bottom: FiloSpacing.lg,
        child: FloatingTransferCapsule(),
      ),
    ],
  ),
  floatingActionButton: state.isMultiSelect
          ? null
          : Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                boxShadow: [
                  BoxShadow(
                    color: FiloColors.primary.withValues(alpha: 0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: FloatingActionButton.extended(
                backgroundColor: FiloColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                highlightElevation: 0,
                onPressed: () {
                  HapticFeedback.lightImpact();
                  _showAddOptionsMenu();
                },
                icon: const Icon(Icons.add_rounded, size: 24),
                label: const Text(
                  'Add',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: -0.2),
                ),
              ),
            ),
    );
  }

  void _showAddOptionsMenu() {
    FiloSheet.show(
      context: context,
      title: 'Add to Vault',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: FiloSpacing.xs, vertical: 2),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: FiloColors.primary.withValues(alpha: 0.12),
                borderRadius: FiloRadius.roundedMd,
              ),
              child: const Icon(Icons.upload_file_rounded, color: FiloColors.primary, size: 22),
            ),
            title: const Text('Upload File', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            subtitle: const Text('Encrypt and upload any document or media', style: TextStyle(fontSize: 13)),
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop();
              _handleUploadFile();
            },
          ),
          const SizedBox(height: FiloSpacing.xs),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: FiloSpacing.xs, vertical: 2),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: FiloColors.info.withValues(alpha: 0.12),
                borderRadius: FiloRadius.roundedMd,
              ),
              child: const Icon(Icons.create_new_folder_rounded, color: FiloColors.info, size: 22),
            ),
            title: const Text('Create New Folder', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            subtitle: const Text('Organize your files into virtual folders', style: TextStyle(fontSize: 13)),
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop();
              _showNewFolderDialog();
            },
          ),
        ],
      ),
    );
  }
}
