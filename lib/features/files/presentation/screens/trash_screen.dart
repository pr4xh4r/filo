import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/persona_provider.dart';
import '../../../../shared/components/filo_background.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../../shared/components/filo_toast.dart';
import '../providers/file_browser_provider.dart';

/// Trash management interface with 30-day auto-purge policy and one-tap restore.
class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  bool _isLoading = true;
  List<FileNode> _trashedNodes = [];

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  Future<void> _loadTrash() async {
    setState(() => _isLoading = true);
    final repo = ref.read(fileRepositoryProvider);
    final list = await repo.getTrashedNodes();
    setState(() {
      _trashedNodes = list;
      _isLoading = false;
    });
  }

  Future<void> _handleRestore(String id, String name) async {
    final repo = ref.read(fileRepositoryProvider);
    await repo.restoreFromTrash(id);
    FiloToast.show(context, message: '$name restored', type: FiloToastType.success);
    await _loadTrash();
    ref.read(fileBrowserProvider.notifier).loadCurrentFolder();
  }

  Future<void> _handleEmptyTrash() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty Trash?'),
        content: const Text('All items in the trash will be permanently deleted. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FiloButton(
            label: 'Delete Forever',
            variant: FiloButtonVariant.destructive,
            size: FiloButtonSize.small,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final repo = ref.read(fileRepositoryProvider);
      await repo.emptyTrash();
      FiloToast.show(context, message: 'Trash emptied', type: FiloToastType.info);
      await _loadTrash();
      ref.read(fileBrowserProvider.notifier).loadCurrentFolder();
    }
  }

  @override
  Widget build(BuildContext context) {
    final persona = ref.watch(personaProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          if (_trashedNodes.isNotEmpty)
            TextButton(
              onPressed: _handleEmptyTrash,
              child: const Text(
                'Empty Trash',
                style: TextStyle(color: FiloColors.destructive),
              ),
            ),
        ],
      ),
      body: FiloBackground(
        child: Column(
          children: [
            // 30-Day Policy Banner
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: FiloSpacing.lg,
                vertical: FiloSpacing.md,
              ),
              color: (Theme.of(context).brightness == Brightness.dark
                      ? FiloColors.darkSurface
                      : Colors.white)
                  .withValues(alpha: 0.6),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 20,
                    color: FiloColors.info,
                  ),
                  const SizedBox(width: FiloSpacing.md),
                  Expanded(
                    child: Text(
                      'Items in Trash are permanently deleted after 30 days.',
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? FiloColors.darkTextPrimary
                            : FiloColors.lightTextPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _trashedNodes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FiloIllustrationView(
                                assetName: FiloIllustrations.trash(persona),
                                maxHeight: 220,
                                maxWidth: 260,
                              ),
                              const SizedBox(height: FiloSpacing.lg),
                              Text(
                                'trash is empty',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? FiloColors.darkTextPrimary
                                      : FiloColors.lightTextPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'items moved to trash will appear here',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Theme.of(context).brightness == Brightness.dark
                                      ? FiloColors.darkTextSecondary
                                      : FiloColors.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                    : ListView.separated(
                        itemCount: _trashedNodes.length,
                        separatorBuilder: (context, index) => const Divider(
                          color: FiloColors.lightBorder,
                          height: 1,
                        ),
                        itemBuilder: (context, index) {
                          final item = _trashedNodes[index];
                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: FiloColors.destructive.withValues(alpha: 0.1),
                                borderRadius: FiloRadius.roundedMd,
                              ),
                              child: const Icon(
                                Icons.delete_outline_rounded,
                                color: FiloColors.destructive,
                              ),
                            ),
                            title: Text(
                              item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              item.isFolder ? 'Folder' : HashUtils.formatBytes(item.sizeBytes),
                              style: const TextStyle(fontSize: 13),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.restore_from_trash_rounded),
                              tooltip: 'Restore',
                              onPressed: () => _handleRestore(item.id, item.name),
                            ),
                          );
                        },
                      ),
            ),
          ],
        ),
      ),
    );
  }
}
