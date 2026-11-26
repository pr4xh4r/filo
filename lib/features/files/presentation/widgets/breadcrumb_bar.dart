import 'package:flutter/material.dart';
import '../../../../core/database/node_model.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_spacing.dart';

/// Horizontal breadcrumbs path indicator for virtual folder navigation.
class BreadcrumbBar extends StatelessWidget {
  final List<FileNode> breadcrumbs;
  final void Function(String? folderId) onNavigate;

  const BreadcrumbBar({
    super.key,
    required this.breadcrumbs,
    required this.onNavigate,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: FiloSpacing.lg,
        vertical: FiloSpacing.xs,
      ),
      child: Row(
        children: [
          // Root item
          GestureDetector(
            onTap: () => onNavigate(null),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_rounded,
                  size: 18,
                  color: breadcrumbs.isEmpty
                      ? FiloColors.primary
                      : (isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary),
                ),
                const SizedBox(width: 4),
                Text(
                  'Space',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: breadcrumbs.isEmpty ? FontWeight.w600 : FontWeight.w500,
                    color: breadcrumbs.isEmpty
                        ? FiloColors.primary
                        : (isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary),
                  ),
                ),
              ],
            ),
          ),

          // Breadcrumb trail
          for (int i = 0; i < breadcrumbs.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 16,
                color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
              ),
            ),
            GestureDetector(
              onTap: () => onNavigate(breadcrumbs[i].id),
              child: Text(
                breadcrumbs[i].name,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: i == breadcrumbs.length - 1 ? FontWeight.w600 : FontWeight.w500,
                  color: i == breadcrumbs.length - 1
                      ? FiloColors.primary
                      : (isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
