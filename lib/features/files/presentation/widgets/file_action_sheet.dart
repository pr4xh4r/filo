import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_sheet.dart';

/// Bottom action sheet for single file/folder management matching Ethereal Dawn design.
class FileActionSheet extends StatelessWidget {
  final FileNode node;
  final VoidCallback onToggleFavorite;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onShare;
  final VoidCallback? onDownload;
  final VoidCallback? onToggleOffline;
  final VoidCallback? onManageTags;
  final VoidCallback? onChangeWorkspace;
  final VoidCallback onDelete;

  const FileActionSheet({
    super.key,
    required this.node,
    required this.onToggleFavorite,
    required this.onRename,
    required this.onMove,
    required this.onShare,
    this.onDownload,
    this.onToggleOffline,
    this.onManageTags,
    this.onChangeWorkspace,
    required this.onDelete,
  });

  static Future<void> show(
    BuildContext context, {
    required FileNode node,
    required VoidCallback onToggleFavorite,
    required VoidCallback onRename,
    required VoidCallback onMove,
    required VoidCallback onShare,
    VoidCallback? onDownload,
    VoidCallback? onToggleOffline,
    VoidCallback? onManageTags,
    VoidCallback? onChangeWorkspace,
    required VoidCallback onDelete,
  }) {
    final subtitle = node.isFolder
        ? 'Folder'
        : '${HashUtils.formatBytes(node.sizeBytes)}${node.mimeType != null ? " • ${node.mimeType!.split('/').last.toUpperCase()}" : ""}';

    return FiloSheet.show(
      context: context,
      title: node.name,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Text(
          subtitle,
          style: const TextStyle(
            fontFamily: FiloTypography.fontFamily,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: FiloColors.lightTextSecondary,
          ),
        ),
      ),
      child: FileActionSheet(
        node: node,
        onToggleFavorite: onToggleFavorite,
        onRename: onRename,
        onMove: onMove,
        onShare: onShare,
        onDownload: onDownload,
        onToggleOffline: onToggleOffline,
        onManageTags: onManageTags,
        onChangeWorkspace: onChangeWorkspace,
        onDelete: onDelete,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Star / Favorite
        _buildActionTile(
          context: context,
          icon: node.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
          iconColor: node.isFavorite ? FiloColors.accentCoral : FiloColors.primary,
          title: node.isFavorite ? 'Remove from Starred' : 'Add to Starred',
          onTap: () {
            Navigator.of(context).pop();
            onToggleFavorite();
          },
        ),

        // Rename
        _buildActionTile(
          context: context,
          icon: Icons.edit_outlined,
          iconColor: FiloColors.primary,
          title: node.isFolder ? 'Rename Folder' : 'Rename File',
          onTap: () {
            Navigator.of(context).pop();
            onRename();
          },
        ),

        // Move to Folder
        _buildActionTile(
          context: context,
          icon: Icons.drive_file_move_outlined,
          iconColor: FiloColors.primary,
          title: 'Move to Folder',
          onTap: () {
            Navigator.of(context).pop();
            onMove();
          },
        ),

        // Manage Smart Tags
        if (onManageTags != null)
          _buildActionTile(
            context: context,
            icon: Icons.label_outline_rounded,
            iconColor: FiloColors.primary,
            title: 'Smart Tags',
            onTap: () {
              Navigator.of(context).pop();
              onManageTags!();
            },
          ),

        // Move to Workspace / Space
        if (onChangeWorkspace != null)
          _buildActionTile(
            context: context,
            icon: Icons.workspaces_outline,
            iconColor: FiloColors.primary,
            title: 'Move to Space',
            onTap: () {
              Navigator.of(context).pop();
              onChangeWorkspace!();
            },
          ),

        // Share (Files only)
        if (node.isFile)
          _buildActionTile(
            context: context,
            icon: Icons.share_outlined,
            iconColor: FiloColors.primary,
            title: 'Share Decrypted Copy',
            onTap: () {
              Navigator.of(context).pop();
              onShare();
            },
          ),

        // Keep Offline / Remove Offline (Files only)
        if (node.isFile && onToggleOffline != null)
          _buildActionTile(
            context: context,
            icon: node.isPinnedOffline ? Icons.arrow_circle_down_rounded : Icons.arrow_circle_down_outlined,
            iconColor: node.isPinnedOffline ? Colors.black : FiloColors.primary,
            title: node.isPinnedOffline ? 'Remove from Offline' : 'Keep Offline (Save Pass/Doc)',
            onTap: () {
              Navigator.of(context).pop();
              onToggleOffline!();
            },
          ),

        // Download to Device (Files only)
        if (node.isFile && onDownload != null)
          _buildActionTile(
            context: context,
            icon: Icons.file_download_outlined,
            iconColor: FiloColors.primary,
            title: 'Save to Downloads',
            onTap: () {
              Navigator.of(context).pop();
              onDownload!();
            },
          ),

        // Delete to Trash
        _buildActionTile(
          context: context,
          icon: Icons.delete_outline_rounded,
          iconColor: FiloColors.destructive,
          title: node.isFolder ? 'Delete Folder' : 'Move to Trash',
          isDestructive: true,
          onTap: () {
            Navigator.of(context).pop();
            onDelete();
          },
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
            if (isDestructive) {
              HapticFeedback.mediumImpact();
            } else {
              HapticFeedback.selectionClick();
            }
            onTap();
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
                    color: isDestructive
                        ? FiloColors.destructive.withValues(alpha: 0.12)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.04)),
                    borderRadius: FiloRadius.roundedMd,
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontFamily: FiloTypography.fontFamily,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: isDestructive
                          ? FiloColors.destructive
                          : (isDark ? Colors.white : FiloColors.lightTextPrimary),
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
  }
}
