import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../shared/components/filo_sheet.dart';

/// Bottom action sheet for single file/folder management.
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
    return FiloSheet.show(
      context: context,
      title: node.name,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Star / Favorite
        _buildActionTile(
          icon: node.isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
          iconColor: FiloColors.warning,
          title: node.isFavorite ? 'Remove from Favorites' : 'Add to Favorites',
          onTap: () {
            Navigator.of(context).pop();
            onToggleFavorite();
          },
          isDark: isDark,
        ),

        // Rename
        _buildActionTile(
          icon: Icons.edit_rounded,
          iconColor: FiloColors.primary,
          title: 'Rename',
          onTap: () {
            Navigator.of(context).pop();
            onRename();
          },
          isDark: isDark,
        ),

        // Move
        _buildActionTile(
          icon: Icons.drive_file_move_rounded,
          iconColor: FiloColors.info,
          title: 'Move to Folder',
          onTap: () {
            Navigator.of(context).pop();
            onMove();
          },
          isDark: isDark,
        ),

        // Share (Files only)
        if (node.isFile)
          _buildActionTile(
            icon: Icons.share_rounded,
            iconColor: FiloColors.success,
            title: 'Share Decrypted Copy',
            onTap: () {
              Navigator.of(context).pop();
              onShare();
            },
            isDark: isDark,
          ),

        // Download to Device (Files only)
        if (node.isFile && onDownload != null)
          _buildActionTile(
            icon: Icons.download_rounded,
            iconColor: FiloColors.info,
            title: 'Download to Device',
            onTap: () {
              Navigator.of(context).pop();
              onDownload!();
            },
            isDark: isDark,
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
          isDark: isDark,
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required VoidCallback onTap,
    required bool isDark,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: FiloRadius.roundedMd,
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: isDestructive
              ? FiloColors.destructive
              : (isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: FiloSpacing.xs, vertical: 2),
      onTap: () {
        if (isDestructive) {
          HapticFeedback.mediumImpact();
        } else {
          HapticFeedback.selectionClick();
        }
        onTap();
      },
    );
  }
}
