import 'package:flutter/material.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../shared/components/filo_card.dart';
import '../../../../shared/components/filo_progress_ring.dart';

/// Grid card presentation for files and folders.
class FileGridCard extends StatelessWidget {
  final FileNode node;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isTransferring;
  final double? transferProgress;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMoreTap;

  const FileGridCard({
    super.key,
    required this.node,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.isTransferring = false,
    this.transferProgress,
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
    if (mime.contains('zip') || mime.contains('tar')) return Icons.archive_rounded;
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

    return FiloCard(
      onTap: onTap,
      onLongPress: onLongPress,
      padding: const EdgeInsets.all(FiloSpacing.md),
      borderColor: isSelected ? FiloColors.primary : null,
      backgroundColor: isSelected
          ? FiloColors.primary.withValues(alpha: 0.08)
          : null,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon Container
              Expanded(
                child: Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isTransferring
                          ? FiloColors.primary.withValues(alpha: 0.15)
                          : _getIconColor().withValues(alpha: 0.12),
                      borderRadius: FiloRadius.roundedLg,
                    ),
                    child: isTransferring
                        ? Center(
                            child: FiloProgressRing(
                              value: (transferProgress != null && transferProgress! > 0)
                                  ? transferProgress
                                  : null,
                              size: 28,
                              strokeWidth: 2.8,
                              color: FiloColors.primary,
                            ),
                          )
                        : Icon(
                            _getIconForNode(),
                            size: 32,
                            color: _getIconColor(),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: FiloSpacing.sm),

              // File Name
              Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 2),

              // Subtitle (Size or Folder item count or live transfer progress)
              Text(
                isTransferring
                    ? 'Transferring ${(transferProgress != null ? (transferProgress! * 100).toInt() : 0)}%'
                    : (node.isFolder ? 'Folder' : HashUtils.formatBytes(node.sizeBytes)),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isTransferring ? FontWeight.w600 : FontWeight.normal,
                  color: isTransferring
                      ? FiloColors.primary
                      : (isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary),
                ),
              ),
            ],
          ),

          // Favorite badge
          if (node.isFavorite)
            const Positioned(
              top: 0,
              left: 0,
              child: Icon(
                Icons.star_rounded,
                size: 16,
                color: FiloColors.warning,
              ),
            ),

          // Context menu button or selection checkbox
          Positioned(
            top: -4,
            right: -4,
            child: isSelectionMode
                ? Checkbox(
                    value: isSelected,
                    activeColor: FiloColors.primary,
                    onChanged: (_) => onTap(),
                  )
                : IconButton(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 18,
                      color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                    ),
                    onPressed: onMoreTap,
                  ),
          ),
        ],
      ),
    );
  }
}
