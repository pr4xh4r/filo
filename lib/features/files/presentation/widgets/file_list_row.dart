import 'package:flutter/material.dart';
import '../../../../core/crypto/hash_utils.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../shared/components/filo_progress_ring.dart';
import '../../domain/smart_tag.dart';

/// List row presentation for files and folders.
class FileListRow extends StatelessWidget {
  final FileNode node;
  final bool isSelected;
  final bool isSelectionMode;
  final bool isTransferring;
  final double? transferProgress;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMoreTap;

  const FileListRow({
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
    return Icons.insert_drive_file_rounded;
  }

  Color _getIconColor() {
    return Colors.black;
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
                color: isTransferring
                    ? FiloColors.primary.withValues(alpha: 0.15)
                    : _getIconColor().withValues(alpha: 0.12),
                borderRadius: FiloRadius.roundedMd,
              ),
              child: isTransferring
                  ? Center(
                      child: FiloProgressRing(
                        value: (transferProgress != null && transferProgress! > 0)
                            ? transferProgress
                            : null,
                        size: 24,
                        strokeWidth: 2.5,
                        color: FiloColors.primary,
                      ),
                    )
                  : Icon(
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
                          color: FiloColors.accentCoral,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        isTransferring
                            ? 'Transferring ${(transferProgress != null ? (transferProgress! * 100).toInt() : 0)}% • ${HashUtils.formatBytes(node.sizeBytes)}'
                            : (node.isFolder ? 'Folder' : HashUtils.formatBytes(node.sizeBytes)),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isTransferring ? FontWeight.w600 : FontWeight.normal,
                          color: isTransferring
                              ? FiloColors.primary
                              : (isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary),
                        ),
                      ),
                      if (node.tags.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        ...node.tags.take(3).map((tId) {
                          final tag = SmartTag.fromId(tId);
                          if (tag == null) return const SizedBox.shrink();
                          return Container(
                            margin: const EdgeInsets.only(right: 5),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isDark ? tag.color.withValues(alpha: 0.15) : tag.bgColor,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: tag.color.withValues(alpha: isDark ? 0.3 : 0.4),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: tag.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  tag.name,
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    color: tag.color,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
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
