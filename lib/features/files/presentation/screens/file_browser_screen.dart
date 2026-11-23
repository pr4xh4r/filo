import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/database/transfer_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/diamond_pattern_painter.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../../shared/components/filo_empty_state.dart';
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
/// Designed to match Screen 2 of the reference design:
/// - "Hello Alex / It's Thursday, 04 June" header with notification bell & scanner icons
/// - Radiant sunset/violet hero card with diamond pattern & eye toggle
/// - 4 Quick action squircles: [ Upload ] [ Download ] [ Sync ] [ + Folder ]
/// - Vault categories horizontal carousel
/// - "Recent files / Today" transaction-style list
/// - Floating liquid glass bottom capsule navigation bar with active squircle badge
class FileBrowserScreen extends ConsumerStatefulWidget {
  const FileBrowserScreen({super.key});

  @override
  ConsumerState<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends ConsumerState<FileBrowserScreen> {
  bool _isSearchActive = false;
  bool _showStats = true;
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

    final tasks = ref.watch(transferQueueProvider);
    final activeTasksCount = tasks.where((t) => t.status == TransferStatus.running).length;

    final now = DateTime.now();
    final dateString = "It's ${DateFormat('EEEE, dd MMMM').format(now)}";

    return Scaffold(
      backgroundColor: isDark ? FiloColors.darkBackground : FiloColors.lightBackground,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                // 1. Top Header Bar (Screen 2: Hello Alex + Date + Actions)
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (state.currentFolderId != null)
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                            onPressed: _navigateUp,
                          )
                        else
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hello Member',
                                style: FiloTypography.title2.copyWith(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 24,
                                  color: isDark
                                      ? FiloColors.darkTextPrimary
                                      : FiloColors.lightTextPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dateString,
                                style: FiloTypography.subheadline.copyWith(
                                  color: isDark
                                      ? FiloColors.darkTextTertiary
                                      : FiloColors.lightTextTertiary,
                                  fontSize: 13,
                                ),
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
                              isDark: isDark,
                            ),
                            const SizedBox(width: 8),
                            _buildHeaderIconButton(
                              icon: Icons.notifications_none_rounded,
                              onTap: () => TransferQueueSheet.show(context),
                              isDark: isDark,
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
                              isDark: isDark,
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
                          color: isDark ? FiloColors.darkSurfaceSecondary : Colors.white,
                          borderRadius: BorderRadius.circular(100),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.1)
                                : Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
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
                  ),

                // 2. Hero Card: Available Storage & 4 Quick Action Squircles
                if (state.currentFolderId == null && !_isSearchActive)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FiloSpacing.xl,
                        vertical: FiloSpacing.sm,
                      ),
                      child: _buildHeroCard(state, isDark),
                    ),
                  ),

                // 3. Vault Categories Carousel (Screen 2: My Accounts Balance)
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
                            'Vault Categories',
                            style: FiloTypography.title3.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                            ),
                          ),
                          GestureDetector(
                            onTap: _showNewFolderDialog,
                            child: Text(
                              'Add Folder',
                              style: FiloTypography.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark ? FiloColors.accentOrchid : FiloColors.primary,
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
                          _buildCategoryCard('Photos', '📸', '${state.items.where((i) => i.name.toLowerCase().endsWith('.jpg') || i.name.toLowerCase().endsWith('.png')).length} files', isDark),
                          const SizedBox(width: 12),
                          _buildCategoryCard('Videos', '🎬', '${state.items.where((i) => i.name.toLowerCase().endsWith('.mp4')).length} files', isDark),
                          const SizedBox(width: 12),
                          _buildCategoryCard('Docs', '📄', '${state.items.where((i) => i.name.toLowerCase().endsWith('.pdf') || i.name.toLowerCase().endsWith('.txt')).length} files', isDark),
                          const SizedBox(width: 12),
                          _buildCategoryCard('Encrypted', '🔒', 'Telegram Cloud', isDark),
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

                // 4. Recent Files Section Header (Screen 2: Transactions / Today)
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
                            color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
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

                // 5. Files List / Grid / Empty State
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
                      child: FiloEmptyState(
                        icon: state.isFavoritesOnly
                            ? Icons.star_border_rounded
                            : Icons.cloud_queue_rounded,
                        title: state.isFavoritesOnly
                            ? 'No Starred Files'
                            : 'vault is empty',
                        description: state.isFavoritesOnly
                            ? 'Star your important files to access them quickly.'
                            : 'save documents, photos, or videos to your encrypted telegram vault.',
                        actionLabel: 'upload file',
                        onAction: _handleUploadFile,
                      ),
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

            // 6. Floating Liquid Glass Bottom Capsule Bar (Screen 2 / Image 5 style)
            Positioned(
              left: 20,
              right: 20,
              bottom: 24,
              child: _buildFloatingNavbar(isDark, activeTasksCount),
            ),
          ],
        ),
      ),
    );
  }

  // HERO CARD: Available Storage + 4 Quick Actions (Screen 2 style)
  Widget _buildHeroCard(FileBrowserState state, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? FiloColors.darkSurfaceSecondary : Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Top Gradient Section
          Container(
            padding: const EdgeInsets.all(FiloSpacing.lg),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark ? FiloColors.heroGradientDark : FiloColors.heroGradient,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
            ),
            child: DiamondPatternOverlay(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(28),
                topRight: Radius.circular(28),
              ),
              opacity: isDark ? 0.12 : 0.18,
              spacing: 20.0,
              diamondSize: 8.0,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Available Storage',
                        style: TextStyle(
                          fontFamily: FiloTypography.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => setState(() => _showStats = !_showStats),
                        child: Icon(
                          _showStats ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _showStats ? 'Unlimited' : '••••••••',
                        style: const TextStyle(
                          fontFamily: FiloTypography.fontFamily,
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '+100% ↗',
                              style: TextStyle(
                                fontFamily: FiloTypography.fontFamily,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF34D399),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 4 Quick Actions Row: [ Upload ] [ Download ] [ Sync ] [ + Folder ]
          Padding(
            padding: const EdgeInsets.symmetric(vertical: FiloSpacing.md, horizontal: FiloSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildQuickActionItem(
                  icon: Icons.file_upload_outlined,
                  label: 'Upload',
                  onTap: _handleUploadFile,
                  isDark: isDark,
                ),
                _buildQuickActionItem(
                  icon: Icons.file_download_outlined,
                  label: 'Download',
                  onTap: () => TransferQueueSheet.show(context),
                  isDark: isDark,
                ),
                _buildQuickActionItem(
                  icon: Icons.sync_alt_rounded,
                  label: 'Sync',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    ref.read(fileBrowserProvider.notifier).loadCurrentFolder();
                    FiloToast.show(context, message: 'Vault synced with Telegram', type: FiloToastType.success);
                  },
                  isDark: isDark,
                ),
                _buildQuickActionItem(
                  icon: Icons.create_new_folder_outlined,
                  label: 'Folder',
                  onTap: _showNewFolderDialog,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: FiloTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(String title, String emoji, String count, bool isDark) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? FiloColors.darkSurfaceSecondary : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
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
          const SizedBox(height: 6),
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

  Widget _buildHeaderIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool isDark,
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
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
              ),
            ),
            child: Icon(
              icon,
              size: 19,
              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
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

  // 6. Floating Liquid Glass Bottom Capsule Navigation Bar
  Widget _buildFloatingNavbar(bool isDark, int activeTasksCount) {
    return FiloGlass(
      borderRadius: BorderRadius.circular(40),
      blur: 28.0,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      border: Border.all(
        color: isDark ? Colors.white.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.8),
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.1),
          blurRadius: 30,
          offset: const Offset(0, 10),
        ),
      ],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 1. Vault / Home (Active Solid Squircle)
          _buildNavPill(
            icon: Icons.home_filled,
            isActive: true,
            onTap: () {},
            isDark: isDark,
          ),

          // 2. Starred / Favorites
          _buildNavPill(
            icon: Icons.bookmark_border_rounded,
            isActive: false,
            onTap: () {
              ref.read(fileBrowserProvider.notifier).toggleFavoritesFilter();
            },
            isDark: isDark,
          ),

          // 3. Center Glowing Plus Button
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              _handleUploadFile();
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark ? FiloColors.heroGradientDark : FiloColors.heroGradient,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: FiloColors.accentOrchid.withValues(alpha: 0.4),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
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

          // 4. Transfers / Activity
          _buildNavPill(
            icon: Icons.swap_vert_rounded,
            isActive: false,
            badgeCount: activeTasksCount > 0 ? activeTasksCount : null,
            onTap: () => TransferQueueSheet.show(context),
            isDark: isDark,
          ),

          // 5. Settings / Menu
          _buildNavPill(
            icon: Icons.tune_rounded,
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
    );
  }

  Widget _buildNavPill({
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
    required bool isDark,
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
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isActive
                  ? (isDark ? Colors.white : Colors.black)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isActive
                  ? (isDark ? Colors.black : Colors.white)
                  : (isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary),
            ),
          ),
          if (badgeCount != null)
            Positioned(
              top: 2,
              right: 2,
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
