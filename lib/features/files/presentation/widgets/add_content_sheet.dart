import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_typography.dart';

enum AddContentAction {
  newFolder,
  uploadFiles,
  uploadMedia,
  takePhoto,
}

/// Frosted modal bottom sheet allowing users to add folders, upload files,
/// select photos/videos, or capture directly from the camera.
class AddContentSheet extends StatelessWidget {
  final ValueChanged<AddContentAction> onActionSelected;

  const AddContentSheet({
    super.key,
    required this.onActionSelected,
  });

  static Future<AddContentAction?> show(BuildContext context) {
    return showModalBottomSheet<AddContentAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => AddContentSheet(
        onActionSelected: (action) {
          Navigator.of(context).pop(action);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF161622).withValues(alpha: 0.92)
                : const Color(0xFFFFFBF9).withValues(alpha: 0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.8),
                width: 1.5,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                blurRadius: 30,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Grab handle
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.2)
                        : Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'add to filo',
                      style: FiloTypography.editorial(
                        fontSize: 26,
                        color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.black.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: FiloColors.accentCoral,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'private storage',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white70 : FiloColors.lightTextPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'all files are encrypted directly on your device before saving',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // 1. New Folder
              _buildActionTile(
                context: context,
                icon: Icons.create_new_folder_outlined,
                title: 'New Folder',
                subtitle: 'Organize files in a subfolder',
                onTap: () => onActionSelected(AddContentAction.newFolder),
                isDark: isDark,
              ),
              const SizedBox(height: 10),

              // 2. Upload Files
              _buildActionTile(
                context: context,
                icon: Icons.file_upload_outlined,
                title: 'Upload Files',
                subtitle: 'Documents, PDFs, archives, code, audio',
                onTap: () => onActionSelected(AddContentAction.uploadFiles),
                isDark: isDark,
              ),
              const SizedBox(height: 10),

              // 3. Upload Photos & Videos
              _buildActionTile(
                context: context,
                icon: Icons.photo_library_outlined,
                title: 'Photos & Videos',
                subtitle: 'Upload original quality images & media',
                onTap: () => onActionSelected(AddContentAction.uploadMedia),
                isDark: isDark,
              ),
              const SizedBox(height: 10),

              // 4. Take Photo / Scan Document
              _buildActionTile(
                context: context,
                icon: Icons.camera_alt_outlined,
                title: 'Take Photo / Scan',
                subtitle: 'Capture directly into your private vault',
                onTap: () => onActionSelected(AddContentAction.takePhoto),
                isDark: isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: isDark ? Colors.white : FiloColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? FiloColors.darkTextTertiary
                            : FiloColors.lightTextTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
