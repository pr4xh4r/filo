import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/database/transfer_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../core/theme/persona_provider.dart';
import '../../../../shared/components/filo_background.dart';
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

    try {
      final nodes = await transferNotifier.pickAndUploadFiles(
        parentId: browserState.currentFolderId,
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
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (context) => Dialog(
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
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFF9F7), Color(0xFFFBF4FF)],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.isFolder ? 'Rename Folder' : 'Rename File',
                    style: FiloTypography.title3.copyWith(
                      fontWeight: FontWeight.w700,
                      color: FiloColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
                    ),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      style: const TextStyle(fontSize: 15, color: FiloColors.lightTextPrimary),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: (val) {
                        final newName = val.trim();
                        if (newName.isNotEmpty) {
                          ref.read(fileBrowserProvider.notifier).renameNode(node.id, newName);
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel', style: TextStyle(color: FiloColors.lightTextSecondary)),
                      ),
                      const SizedBox(width: 8),
                      FiloButton(
                        label: 'Save',
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMoveDialog(FileNode node) async {
    final repo = ref.read(fileRepositoryProvider);
    final folders = await repo.getFolders();
    final candidateFolders = folders.where((f) => f.id != node.id).toList();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? FiloColors.darkSurface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    'Move "${node.name}"',
                    style: FiloTypography.title3.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.cloud_outlined, color: FiloColors.primary),
                  title: Text(
                    'Vault Root',
                    style: TextStyle(
                      color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    ref.read(fileBrowserProvider.notifier).moveNode(node.id, null);
                    FiloToast.show(context, message: 'Moved to Vault Root', type: FiloToastType.success);
                  },
                ),
                const Divider(),
                if (candidateFolders.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      'No subfolders created yet',
                      style: TextStyle(
                        color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                      ),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: candidateFolders.length,
                      itemBuilder: (c, idx) {
                        final folder = candidateFolders[idx];
                        return ListTile(
                          leading: const Icon(Icons.folder_outlined, color: FiloColors.primary),
                          title: Text(
                            folder.name,
                            style: TextStyle(
                              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                            ),
                          ),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            ref.read(fileBrowserProvider.notifier).moveNode(node.id, folder.id);
                            FiloToast.show(
                              context,
                              message: 'Moved to ${folder.name}',
                              type: FiloToastType.success,
                            );
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
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
    final activeTasksCount = tasks.where((t) => t.status == TransferStatus.running).length;

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
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'cloud',
                                style: FiloTypography.handwriting(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? Colors.white
                                      : FiloColors.lightTextPrimary,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.cloud_outlined,
                                size: 24,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? FiloColors.accentCoral
                                    : FiloColors.primary,
                              ),
                            ],
                          ),
                        Row(
                          children: [
                            _buildHeaderIconButton(
                              icon: Icons.sync_rounded,
                              onTap: () async {
                                FiloToast.show(context, message: 'Syncing with Telegram...', type: FiloToastType.info);
                                try {
                                  await notifier.syncNow();
                                  if (mounted) {
                                    FiloToast.show(context, message: 'Snapshot synced & pinned to Telegram', type: FiloToastType.success);
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    FiloToast.show(context, message: 'Sync failed: $e', type: FiloToastType.error);
                                  }
                                }
                              },
                            ),
                            const SizedBox(width: 8),
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
                            hintText: 'search your vault...',
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
                            child: Text(
                              'Add Folder',
                              style: FiloTypography.caption.copyWith(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).brightness == Brightness.dark
                                    ? FiloColors.accentCoral
                                    : FiloColors.primary,
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
                  : 'your encrypted telegram vault is peaceful and ready.\ntap + below to store your first file',
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
