import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../shared/components/filo_sheet.dart';

/// Bottom action sheet for single file/folder management matching Ethereal Dawn design.
class FileActionSheet extends StatelessWidget {
  final FileNode node;
  final VoidCallback onToggleFavorite;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onShare;
  final VoidCallback? onDownload;
  final VoidCallback onDelete;

  const FileActionSheet({
    super.key,
    required this.node,
    required this.onToggleFavorite,
    required this.onRename,
    required this.onMove,
    required this.onShare,
    this.onDownload,
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
          icon: node.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
          iconColor: const Color(0xFFFFB300),
          title: node.isFavorite ? 'Remove from Starred' : 'Add to Starred',
          onTap: () {
            Navigator.of(context).pop();
            onToggleFavorite();
          },
        ),

        // Rename
        _buildActionTile(
          icon: Icons.edit_outlined,
          iconColor: FiloColors.primary,
          title: 'Rename',
          onTap: () {
            Navigator.of(context).pop();
            onRename();
          },
        ),

        // Move
        _buildActionTile(
          icon: Icons.drive_file_move_outlined,
          iconColor: const Color(0xFF5E5CE6),
          title: 'Move to Folder',
          onTap: () {
            Navigator.of(context).pop();
            onMove();
          },
        ),

        // Share (Files only)
        if (node.isFile)
          _buildActionTile(
            icon: Icons.share_outlined,
            iconColor: const Color(0xFF34C759),
            title: 'Share Decrypted Copy',
            onTap: () {
              Navigator.of(context).pop();
              onShare();
            },
          ),

        // Download to Device (Files only)
        if (node.isFile && onDownload != null)
          _buildActionTile(
            icon: Icons.download_outlined,
            iconColor: const Color(0xFF007AFF),
            title: 'Save to Downloads',
            onTap: () {
              Navigator.of(context).pop();
              onDownload!();
            },
          ),

        // Delete to Trash
        _buildActionTile(
          icon: Icons.delete_outline_rounded,
          iconColor: FiloColors.destructive,
          title: 'Move to Trash',
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
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withValues(alpha: 0.72),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: FiloRadius.roundedMd,
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.3,
                      color: isDestructive
                          ? FiloColors.destructive
                          : FiloColors.lightTextPrimary,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Colors.black.withValues(alpha: 0.2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
