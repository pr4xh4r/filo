import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/database/transfer_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../../shared/components/filo_empty_state.dart';
import '../../../../shared/components/filo_glass.dart';
import '../../../../shared/components/filo_sheet.dart';
import '../../../../shared/components/filo_toast.dart';
import '../../../preview/presentation/screens/file_preview_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
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
///
/// Designed with CRED luxury obsidian typography and iOS 18 liquid glass materials.
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
    ref.read(fileBrowserProvider.notifier).moveNode(node.id, null);
    FiloToast.show(context, message: 'Moved to Vault Root', type: FiloToastType.success);
  }

  void _handleShareFile(FileNode node) {
    FiloToast.show(context, message: 'Sharing ${node.name}...', type: FiloToastType.info);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.watch(fileBrowserProvider);
    final notifier = ref.read(fileBrowserProvider.notifier);

    final currentFolderName = state.breadcrumbs.isNotEmpty
        ? state.breadcrumbs.last.name
        : 'vault';

    final tasks = ref.watch(transferQueueProvider);
    final activeTaskMap = <String, TransferTask>{};
    for (final t in tasks) {
      if (t.status == TransferStatus.running) {
        activeTaskMap[t.nodeId] = t;
      }
    }

    return Scaffold(
      body: FiloAmbientBackground(
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Minimalist Header
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FiloSpacing.lg,
                      vertical: FiloSpacing.xs,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (state.currentFolderId != null)
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                            onPressed: _navigateUp,
                          )
                        else
                          Text(
                            currentFolderName,
                            style: FiloTypography.editorial(
                              fontSize: 34,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -1.0,
                              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                            ),
                          ),
                        Row(
                          children: [
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
                            ),
                            IconButton(
                              icon: Icon(state.isGridView ? Icons.view_list_rounded : Icons.grid_view_rounded),
                              onPressed: () => notifier.toggleViewMode(),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded),
                              onPressed: () {
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

                  // Search Bar if Active
                  if (_isSearchActive)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: FiloSpacing.lg, vertical: 4),
                      child: FiloGlass(
                        borderRadius: BorderRadius.circular(100),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          style: FiloTypography.bodyMedium.copyWith(
                            color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'search your vault...',
                            hintStyle: FiloTypography.body.copyWith(
                              color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
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

                  // 3 Frosted Quick Stats Pills (Image 5 style) when at root & not searching
                  if (state.currentFolderId == null && !_isSearchActive)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FiloSpacing.lg,
                        vertical: FiloSpacing.xs,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildStatsPill(
                              label: 'total files',
                              value: '${state.items.length}',
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildStatsPill(
                              label: 'starred',
                              value: '${state.items.where((i) => i.isFavorite).length}',
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildStatsPill(
                              label: 'cloud',
                              value: 'telegram',
                              isDark: isDark,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Breadcrumbs Bar
                  if (!state.isMultiSelect && state.breadcrumbs.isNotEmpty)
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
                                    : 'vault is empty',
                                description: state.isFavoritesOnly
                                    ? 'Star your important files to access them quickly.'
                                    : 'save documents, photos, or videos to your encrypted telegram vault.',
                                actionLabel: state.isFavoritesOnly ? null : 'upload file',
                                onAction: state.isFavoritesOnly ? null : _handleUploadFile,
                              )
                            : RefreshIndicator(
                                onRefresh: () async {
                                  HapticFeedback.lightImpact();
                                  await notifier.loadCurrentFolder();
                                },
                                child: state.isGridView
                                    ? GridView.builder(
                                        padding: const EdgeInsets.fromLTRB(
                                          FiloSpacing.lg,
                                          FiloSpacing.sm,
                                          FiloSpacing.lg,
                                          100, // space for bottom capsule
                                        ),
                                        physics: const BouncingScrollPhysics(
                                          parent: AlwaysScrollableScrollPhysics(),
                                        ),
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
                                        padding: const EdgeInsets.fromLTRB(
                                          FiloSpacing.lg,
                                          FiloSpacing.sm,
                                          FiloSpacing.lg,
                                          100,
                                        ),
                                        physics: const BouncingScrollPhysics(
                                          parent: AlwaysScrollableScrollPhysics(),
                                        ),
                                        itemCount: state.items.length,
                                        separatorBuilder: (context, index) => const SizedBox(height: 8),
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

              // Floating Transfer Capsule
              const Positioned(
                left: FiloSpacing.md,
                right: FiloSpacing.md,
                bottom: 84,
                child: FloatingTransferCapsule(),
              ),

              // Floating Frosted Glass Bottom Navigation Capsule (Image 5 style!)
              Positioned(
                left: FiloSpacing.xl,
                right: FiloSpacing.xl,
                bottom: 18,
                child: Center(
                  child: FiloGlass(
                    borderRadius: BorderRadius.circular(100),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Files/Root Home
                        _buildNavIcon(
                          icon: Icons.folder_rounded,
                          isActive: state.currentFolderId == null && !state.isFavoritesOnly,
                          onTap: () {
                            if (state.currentFolderId != null) {
                              notifier.navigateToFolder(null);
                            }
                            if (state.isFavoritesOnly) {
                              notifier.toggleFavoritesFilter();
                            }
                          },
                          isDark: isDark,
                        ),
                        const SizedBox(width: 14),

                        // Favorites
                        _buildNavIcon(
                          icon: Icons.star_rounded,
                          isActive: state.isFavoritesOnly,
                          onTap: () => notifier.toggleFavoritesFilter(),
                          isDark: isDark,
                        ),
                        const SizedBox(width: 14),

                        // Center Glowing Add Button (Emil Kowalski press)
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.mediumImpact();
                            _showAddOptionsMenu();
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                colors: FiloColors.brandGradient,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: FiloColors.brandIndigo.withValues(alpha: 0.4),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Transfers
                        _buildNavIcon(
                          icon: Icons.swap_vert_rounded,
                          isActive: tasks.any((t) => t.status == TransferStatus.running),
                          onTap: () => TransferQueueSheet.show(context),
                          isDark: isDark,
                        ),
                        const SizedBox(width: 14),

                        // Settings
                        _buildNavIcon(
                          icon: Icons.settings_rounded,
                          isActive: false,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (context) => const SettingsScreen()),
                            );
                          },
                          isDark: isDark,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavIcon({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isActive
              ? (isDark ? FiloColors.darkSurfaceSecondary : FiloColors.primary.withValues(alpha: 0.12))
              : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 22,
          color: isActive
              ? (isDark ? FiloColors.accentOrchid : FiloColors.primary)
              : (isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary),
        ),
      ),
    );
  }

  Widget _buildStatsPill({
    required String label,
    required String value,
    required bool isDark,
  }) {
    return FiloGlass(
      borderRadius: FiloRadius.roundedLg,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: FiloTypography.title3.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: FiloTypography.caption.copyWith(
              fontSize: 10,
              color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
            ),
          ),
        ],
      ),
    );
  }

  void _showAddOptionsMenu() {
    FiloSheet.show(
      context: context,
      title: 'add to vault',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: FiloSpacing.xs, vertical: 4),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    FiloColors.brandOrchid.withValues(alpha: 0.18),
                    FiloColors.brandIndigo.withValues(alpha: 0.18),
                  ],
                ),
                borderRadius: FiloRadius.roundedMd,
              ),
              child: const Icon(Icons.upload_file_rounded, color: FiloColors.primary, size: 22),
            ),
            title: Text('upload file', style: FiloTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
            subtitle: Text('encrypt and save any photo, video, or file', style: FiloTypography.caption),
            onTap: () {
              HapticFeedback.selectionClick();
              Navigator.of(context).pop();
              _handleUploadFile();
            },
          ),
          const SizedBox(height: FiloSpacing.xs),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: FiloSpacing.xs, vertical: 4),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: FiloColors.info.withValues(alpha: 0.14),
                borderRadius: FiloRadius.roundedMd,
              ),
              child: const Icon(Icons.create_new_folder_rounded, color: FiloColors.info, size: 22),
            ),
            title: Text('new folder', style: FiloTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
            subtitle: Text('create a folder to organize your vault', style: FiloTypography.caption),
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
