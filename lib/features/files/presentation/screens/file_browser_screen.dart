import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/database/transfer_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../../shared/components/filo_glass.dart';
import '../../../../shared/components/filo_toast.dart';
import '../../../preview/presentation/screens/file_preview_screen.dart';
import '../../../settings/presentation/screens/settings_screen.dart';
import '../../../transfer/presentation/providers/transfer_provider.dart';
import '../../../transfer/presentation/screens/transfer_queue_sheet.dart';
import '../providers/file_browser_provider.dart';
import '../widgets/breadcrumb_bar.dart';
import '../widgets/create_folder_dialog.dart';
import '../widgets/file_action_sheet.dart';
import '../widgets/file_grid_card.dart';
import '../widgets/file_list_row.dart';
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
    final state = ref.watch(fileBrowserProvider);
    final notifier = ref.read(fileBrowserProvider.notifier);

    final tasks = ref.watch(transferQueueProvider);
    final activeTasksCount = tasks.where((t) => t.status == TransferStatus.running).length;

    return Scaffold(
      backgroundColor: FiloColors.lightBackground,
      body: SafeArea(
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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'cloud',
                                style: FiloTypography.handwriting(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w700,
                                  color: FiloColors.lightTextPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.cloud_outlined,
                                size: 24,
                                color: FiloColors.primary,
                              ),
                            ],
                          ),
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
                            const SizedBox(width: 8),
                            _buildHeaderIconButton(
                              icon: Icons.notifications_none_rounded,
                              onTap: () => TransferQueueSheet.show(context),
                              badgeCount: activeTasksCount > 0 ? activeTasksCount : null,
                            ),
                            const SizedBox(width: 8),
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

                // Search Bar if Active
                if (_isSearchActive)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: FiloSpacing.xl, vertical: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          style: FiloTypography.bodyMedium.copyWith(
                            color: FiloColors.lightTextPrimary,
                          ),
                          decoration: InputDecoration(
                            filled: false,
                            fillColor: Colors.transparent,
                            hintText: 'search your vault...',
                            hintStyle: FiloTypography.body.copyWith(
                              color: FiloColors.lightTextTertiary,
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
                              color: FiloColors.lightTextPrimary,
                            ),
                          ),
                          GestureDetector(
                            onTap: _showNewFolderDialog,
                            child: Text(
                              'Add Folder',
                              style: FiloTypography.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: FiloColors.primary,
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
                            count: '${state.items.where((i) => i.name.toLowerCase().endsWith('.jpg') || i.name.toLowerCase().endsWith('.png')).length} files',
                          ),
                          const SizedBox(width: 12),
                          _buildCategoryCard(
                            title: 'Videos',
                            icon: Icons.videocam_outlined,
                            count: '${state.items.where((i) => i.name.toLowerCase().endsWith('.mp4')).length} files',
                          ),
                          const SizedBox(width: 12),
                          _buildCategoryCard(
                            title: 'Docs',
                            icon: Icons.description_outlined,
                            count: '${state.items.where((i) => i.name.toLowerCase().endsWith('.pdf') || i.name.toLowerCase().endsWith('.txt')).length} files',
                          ),
                          const SizedBox(width: 12),
                          _buildCategoryCard(
                            title: 'Audio',
                            icon: Icons.headphones_outlined,
                            count: '${state.items.where((i) => i.name.toLowerCase().endsWith('.mp3')).length} files',
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
                            color: FiloColors.lightTextPrimary,
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
    );
  }

  // Unique Artistic Empty State (Clean space/cloud theme, NO button block)
  Widget _buildUniqueEmptySpace(bool isFavoritesOnly) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: FiloColors.primary.withValues(alpha: 0.06),
              border: Border.all(
                color: FiloColors.primary.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
            child: Icon(
              isFavoritesOnly ? Icons.star_border_rounded : Icons.cloud_queue_rounded,
              size: 38,
              color: FiloColors.primary,
            ),
          ),
          const SizedBox(height: FiloSpacing.md),
          Text(
            isFavoritesOnly ? 'no starred files' : 'empty space',
            style: FiloTypography.title2.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: FiloColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              isFavoritesOnly
                  ? 'star your favorite files to view them here.'
                  : 'your encrypted telegram vault is quiet and ready.\ntap + below to store files.',
              textAlign: TextAlign.center,
              style: FiloTypography.body.copyWith(
                color: FiloColors.lightTextSecondary,
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
    return Container(
      width: 125,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
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
                style: const TextStyle(
                  fontFamily: FiloTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: FiloColors.lightTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            count,
            style: const TextStyle(
              fontFamily: FiloTypography.fontFamily,
              fontSize: 12,
              color: FiloColors.lightTextTertiary,
            ),
          ),
        ],
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
            width: 40,
            height: 40,
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
              size: 19,
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
                  color: FiloColors.accentOrchid,
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

          // 3. Upload (Center Action)
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              _handleUploadFile();
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
                  color: FiloColors.accentOrchid,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
