import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../../shared/components/filo_empty_state.dart';
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

    await transferNotifier.pickAndUploadFile(parentId: browserState.currentFolderId);
    ref.read(fileBrowserProvider.notifier).loadCurrentFolder();
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
      onDelete: () {
        notifier.moveToTrash(node.id);
        FiloToast.show(context, message: '${node.name} moved to Trash', type: FiloToastType.info);
      },
    );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentFolderName = state.breadcrumbs.isNotEmpty
        ? state.breadcrumbs.last.name
        : 'Vault';

    return Scaffold(
      appBar: AppBar(
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
      body: Column(
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
                    : state.isGridView
                        ? GridView.builder(
                            padding: const EdgeInsets.all(FiloSpacing.lg),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: FiloSpacing.md,
                              crossAxisSpacing: FiloSpacing.md,
                              childAspectRatio: 0.88,
                            ),
                            itemCount: state.items.length,
                            itemBuilder: (context, index) {
                              final item = state.items[index];
                              return FileGridCard(
                                node: item,
                                isSelected: state.selectedIds.contains(item.id),
                                isSelectionMode: state.isMultiSelect,
                                onTap: () => _handleFileTap(item),
                                onLongPress: () => notifier.toggleSelect(item.id),
                                onMoreTap: () => _showFileActions(item),
                              );
                            },
                          )
                        : ListView.separated(
                            itemCount: state.items.length,
                            separatorBuilder: (context, index) => Divider(
                              color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
                              height: 1,
                            ),
                            itemBuilder: (context, index) {
                              final item = state.items[index];
                              return FileListRow(
                                node: item,
                                isSelected: state.selectedIds.contains(item.id),
                                isSelectionMode: state.isMultiSelect,
                                onTap: () => _handleFileTap(item),
                                onLongPress: () => notifier.toggleSelect(item.id),
                                onMoreTap: () => _showFileActions(item),
                              );
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: state.isMultiSelect
          ? null
          : FloatingActionButton(
              backgroundColor: FiloColors.primary,
              foregroundColor: Colors.white,
              onPressed: () {
                _showAddOptionsMenu();
              },
              child: const Icon(Icons.add_rounded, size: 28),
            ),
    );
  }

  void _showAddOptionsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file_rounded, color: FiloColors.primary),
              title: const Text('Upload File'),
              onTap: () {
                Navigator.of(context).pop();
                _handleUploadFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_rounded, color: FiloColors.info),
              title: const Text('Create New Folder'),
              onTap: () {
                Navigator.of(context).pop();
                _showNewFolderDialog();
              },
            ),
          ],
        ),
      ),
    );
  }
}
