import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../core/theme/persona_provider.dart';
import '../../../../shared/components/filo_background.dart';
import '../../../../shared/components/filo_sheet.dart';
import '../../../../shared/components/filo_toast.dart';
import '../../domain/workspace.dart';
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
  List<Workspace> _trashedWorkspaces = [];

  @override
  void initState() {
    super.initState();
    _loadTrash();
  }

  Future<void> _loadTrash() async {
    setState(() => _isLoading = true);
    final repo = ref.read(fileRepositoryProvider);
    try {
      await repo.purgeOldTrash(days: 30);
    } catch (_) {}
    final list = await repo.getTrashedNodes();
    final spaces = await repo.getDeletedWorkspaces();
    if (mounted) {
      setState(() {
        _trashedNodes = list;
        _trashedWorkspaces = spaces;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleRestore(String id, String name) async {
    HapticFeedback.lightImpact();
    await ref.read(fileBrowserProvider.notifier).restoreFromTrash(id);
    if (!mounted) return;
    FiloToast.show(context, message: '$name restored', type: FiloToastType.success);
    await _loadTrash();
  }

  Future<void> _handleRestoreWorkspace(Workspace ws) async {
    HapticFeedback.lightImpact();
    await ref.read(fileBrowserProvider.notifier).restoreWorkspace(ws.id);
    if (!mounted) return;
    FiloToast.show(
      context,
      message: 'Restored space "${ws.name}" and all its files',
      type: FiloToastType.success,
    );
    await _loadTrash();
  }

  Future<void> _handleEmptyTrash() async {
    final totalItems = _trashedNodes.length + _trashedWorkspaces.length;
    HapticFeedback.mediumImpact();
    final confirm = await FiloSheet.show<bool>(
      context: context,
      title: 'Empty Trash',
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: FiloColors.destructive.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          '$totalItems ${totalItems == 1 ? "item" : "items"}',
          style: const TextStyle(
            fontFamily: FiloTypography.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: FiloColors.destructive,
          ),
        ),
      ),
      child: Builder(
        builder: (ctx) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark
                      ? FiloColors.destructive.withValues(alpha: 0.12)
                      : const Color(0xFFFFF2EF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: FiloColors.destructive.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: FiloColors.destructive.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.delete_forever_rounded,
                        color: FiloColors.destructive,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Permanent Deletion',
                            style: TextStyle(
                              fontFamily: FiloTypography.fontFamily,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'All items in trash will be permanently purged from your space. This action cannot be undone.',
                            style: TextStyle(
                              fontFamily: FiloTypography.fontFamily,
                              fontSize: 12,
                              height: 1.35,
                              color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontFamily: FiloTypography.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Material(
                      color: FiloColors.destructive,
                      borderRadius: BorderRadius.circular(100),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(100),
                        onTap: () {
                          HapticFeedback.heavyImpact();
                          Navigator.of(ctx).pop(true);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          alignment: Alignment.center,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.delete_forever_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Delete Forever',
                                style: TextStyle(
                                  fontFamily: FiloTypography.fontFamily,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    if (confirm == true) {
      await ref.read(fileBrowserProvider.notifier).emptyTrash();
      if (!mounted) return;
      FiloToast.show(context, message: 'Trash emptied', type: FiloToastType.info);
      await _loadTrash();
    }
  }

  IconData _getFileIcon(FileNode item) {
    if (item.isFolder) return Icons.folder_outlined;
    final mime = item.mimeType?.toLowerCase() ?? '';
    final name = item.name.toLowerCase();

    if (mime.startsWith('image/') || name.endsWith('.jpg') || name.endsWith('.png') || name.endsWith('.jpeg') || name.endsWith('.webp')) {
      return Icons.photo_outlined;
    }
    if (mime.startsWith('video/') || name.endsWith('.mp4') || name.endsWith('.mov') || name.endsWith('.mkv')) {
      return Icons.videocam_outlined;
    }
    if (mime.contains('pdf') || name.endsWith('.pdf')) {
      return Icons.picture_as_pdf_outlined;
    }
    if (mime.startsWith('audio/') || name.endsWith('.mp3') || name.endsWith('.m4a') || name.endsWith('.wav')) {
      return Icons.headphones_outlined;
    }
    if (mime.contains('text') || name.endsWith('.txt') || name.endsWith('.md')) {
      return Icons.description_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF16122E) : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.06),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 14,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          'Trash',
          style: FiloTypography.title2.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 22,
            fontFamily: FiloTypography.fontFamily,
            color: isDark ? Colors.white : FiloColors.lightTextPrimary,
          ),
        ),
        actions: [
          if (_trashedNodes.isNotEmpty || _trashedWorkspaces.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Material(
                color: FiloColors.destructive.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(100),
                child: InkWell(
                  borderRadius: BorderRadius.circular(100),
                  onTap: _handleEmptyTrash,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: FiloColors.destructive.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.delete_sweep_outlined,
                          size: 16,
                          color: FiloColors.destructive,
                        ),
                        SizedBox(width: 6),
                        Text(
                          'Empty Trash',
                          style: TextStyle(
                            fontFamily: FiloTypography.fontFamily,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: FiloColors.destructive,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: FiloBackground(
        child: Column(
          children: [
            // Floating 30-Day Policy Card
            Container(
              margin: const EdgeInsets.fromLTRB(FiloSpacing.xl, 4, FiloSpacing.xl, 12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: (isDark ? const Color(0xFF222234) : Colors.white).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: FiloColors.info.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.info_outline_rounded,
                      size: 17,
                      color: FiloColors.info,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Items in Trash are permanently deleted after 30 days.',
                      style: TextStyle(
                        fontFamily: FiloTypography.fontFamily,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(FiloColors.primary),
                      ),
                    )
                  : (_trashedNodes.isEmpty && _trashedWorkspaces.isEmpty)
                      ? Center(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FiloIllustrationView(
                                  assetName: FiloIllustrations.trash,
                                  maxHeight: MediaQuery.of(context).orientation == Orientation.landscape ? 110 : 220,
                                  maxWidth: MediaQuery.of(context).orientation == Orientation.landscape ? 140 : 260,
                                ),
                                const SizedBox(height: FiloSpacing.md),
                                Text(
                                  'Trash Is Empty',
                                  style: TextStyle(
                                    fontFamily: FiloTypography.fontFamily,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700,
                                    color: isDark
                                        ? FiloColors.darkTextPrimary
                                        : FiloColors.lightTextPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Items moved to trash will appear here.',
                                  style: TextStyle(
                                    fontFamily: FiloTypography.fontFamily,
                                    fontSize: 13,
                                    color: isDark
                                        ? FiloColors.darkTextSecondary
                                        : FiloColors.lightTextSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(
                            FiloSpacing.xl,
                            0,
                            FiloSpacing.xl,
                            FiloSpacing.xxl,
                          ),
                          children: [
                            if (_trashedWorkspaces.isNotEmpty) ...[
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
                                child: Text(
                                  'DELETED SPACES',
                                  style: FiloTypography.caption.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10.5,
                                    letterSpacing: 0.5,
                                    color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                                  ),
                                ),
                              ),
                              ..._trashedWorkspaces.map((ws) => _buildTrashedWorkspaceCard(ws, isDark)),
                              const SizedBox(height: 12),
                            ],
                            if (_trashedNodes.isNotEmpty && _trashedWorkspaces.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 8),
                                child: Text(
                                  'DELETED FILES',
                                  style: FiloTypography.caption.copyWith(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10.5,
                                    letterSpacing: 0.5,
                                    color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                                  ),
                                ),
                              ),
                            ..._trashedNodes.map((item) => _buildTrashedNodeRow(item, isDark)),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrashedWorkspaceCard(Workspace ws, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: (isDark ? const Color(0xFF222234) : Colors.white).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.workspaces_outlined,
                  size: 22,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            ws.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: FiloTypography.fontFamily,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            ws.isEncrypted ? 'Encrypted' : 'Viewable',
                            style: TextStyle(
                              fontFamily: FiloTypography.fontFamily,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Space & files in trash',
                      style: TextStyle(
                        fontFamily: FiloTypography.fontFamily,
                        fontSize: 12,
                        color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Material(
                color: isDark ? Colors.white12 : Colors.black,
                borderRadius: BorderRadius.circular(100),
                child: InkWell(
                  borderRadius: BorderRadius.circular(100),
                  onTap: () => _handleRestoreWorkspace(ws),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.undo_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 4),
                        Text(
                          'Restore Space',
                          style: TextStyle(
                            fontFamily: FiloTypography.fontFamily,
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                          ),
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

  Widget _buildTrashedNodeRow(FileNode item, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: (isDark ? const Color(0xFF222234) : Colors.white).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: item.isFolder
                      ? FiloColors.accentCoral.withValues(alpha: 0.12)
                      : FiloColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _getFileIcon(item),
                  color: item.isFolder ? FiloColors.accentCoral : FiloColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: FiloTypography.fontFamily,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.isFolder
                          ? 'Folder'
                          : HashUtils.formatBytes(item.sizeBytes),
                      style: TextStyle(
                        fontFamily: FiloTypography.fontFamily,
                        fontSize: 12,
                        color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              // Restore Pill Button
              Material(
                color: (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.04)),
                borderRadius: BorderRadius.circular(100),
                child: InkWell(
                  borderRadius: BorderRadius.circular(100),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _handleRestore(item.id, item.name);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.undo_rounded,
                          size: 15,
                          color: isDark ? Colors.white70 : FiloColors.lightTextPrimary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Restore',
                          style: TextStyle(
                            fontFamily: FiloTypography.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white70 : FiloColors.lightTextPrimary,
                          ),
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
}
