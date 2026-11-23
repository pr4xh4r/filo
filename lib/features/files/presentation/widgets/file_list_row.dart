import 'package:flutter/material.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';

/// List row presentation for files and folders.
class FileListRow extends StatelessWidget {
  final FileNode node;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMoreTap;

  const FileListRow({
    super.key,
    required this.node,
    this.isSelected = false,
    this.isSelectionMode = false,
    required this.onTap,
    required this.onLongPress,
    required this.onMoreTap,
  });

  IconData _getIconForNode() {
    if (node.isFolder) return Icons.folder_rounded;
    final mime = node.mimeType?.toLowerCase() ?? '';
    if (mime.startsWith('image/')) return Icons.image_rounded;
    if (mime.startsWith('video/')) return Icons.movie_rounded;
    if (mime.startsWith('audio/')) return Icons.audiotrack_rounded;
    if (mime.contains('pdf')) return Icons.picture_as_pdf_rounded;
    return Icons.insert_drive_file_rounded;
  }

  Color _getIconColor() {
    if (node.isFolder) return FiloColors.primary;
    final mime = node.mimeType?.toLowerCase() ?? '';
    if (mime.startsWith('image/')) return FiloColors.success;
    if (mime.startsWith('video/')) return FiloColors.info;
    if (mime.startsWith('audio/')) return FiloColors.warning;
    if (mime.contains('pdf')) return FiloColors.destructive;
    return FiloColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FiloSpacing.lg,
          vertical: FiloSpacing.md,
        ),
        color: isSelected ? FiloColors.primary.withValues(alpha: 0.08) : null,
        child: Row(
          children: [
            if (isSelectionMode) ...[
              Checkbox(
                value: isSelected,
                activeColor: FiloColors.primary,
                onChanged: (_) => onTap(),
              ),
              const SizedBox(width: FiloSpacing.sm),
            ],

            // Leading Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _getIconColor().withValues(alpha: 0.12),
                borderRadius: FiloRadius.roundedMd,
              ),
              child: Icon(
                _getIconForNode(),
                size: 24,
                color: _getIconColor(),
              ),
            ),
            const SizedBox(width: FiloSpacing.md),

            // Name and Metadata
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          node.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                            color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                          ),
                        ),
                      ),
                      if (node.isFavorite) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: FiloColors.warning,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    node.isFolder ? 'Folder' : HashUtils.formatBytes(node.sizeBytes),
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // More Options Button
            if (!isSelectionMode)
              IconButton(
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                ),
                onPressed: onMoreTap,
              ),
          ],
        ),
      ),
    );
  }
}
