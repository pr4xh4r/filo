import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../domain/workspace.dart';

/// Modal bottom sheet for switching between Workspaces and creating new ones.
class WorkspaceSwitcherSheet extends StatelessWidget {
  final String activeWorkspaceId;
  final List<Workspace> workspaces;
  final ValueChanged<String> onWorkspaceSelected;
  final VoidCallback onAddWorkspace;

  const WorkspaceSwitcherSheet({
    super.key,
    required this.activeWorkspaceId,
    required this.workspaces,
    required this.onWorkspaceSelected,
    required this.onAddWorkspace,
  });

  static Future<void> show(
    BuildContext context, {
    required String activeWorkspaceId,
    required List<Workspace> workspaces,
    required ValueChanged<String> onWorkspaceSelected,
    required VoidCallback onAddWorkspace,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      builder: (context) => WorkspaceSwitcherSheet(
        activeWorkspaceId: activeWorkspaceId,
        workspaces: workspaces,
        onWorkspaceSelected: onWorkspaceSelected,
        onAddWorkspace: onAddWorkspace,
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
                ? const Color(0xFF161622).withValues(alpha: 0.94)
                : const Color(0xFFFFFBF9).withValues(alpha: 0.96),
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
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
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
                      'Spaces',
                      style: FiloTypography.title1.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
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
                      ),
                      child: Text(
                        'Separate Spaces',
                        style: TextStyle(
                          fontFamily: FiloTypography.fontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Workspaces list
              ...workspaces.map((workspace) {
                final isSelected = workspace.id == activeWorkspaceId;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        onWorkspaceSelected(workspace.id);
                        Navigator.of(context).pop();
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? (isDark
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.white)
                              : (isDark
                                  ? Colors.white.withValues(alpha: 0.03)
                                  : Colors.white.withValues(alpha: 0.7)),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? (isDark ? Colors.white54 : FiloColors.primary)
                                : (isDark
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.black.withValues(alpha: 0.06)),
                            width: isSelected ? 1.5 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ]
                              : [],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06))
                                    : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: Icon(
                                workspace.icon,
                                color: isSelected
                                    ? (isDark ? Colors.white : FiloColors.primary)
                                    : (isDark ? Colors.white70 : FiloColors.lightTextSecondary),
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          workspace.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontFamily: FiloTypography.fontFamily,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: workspace.isEncrypted
                                              ? (isDark ? Colors.purple.withValues(alpha: 0.2) : const Color(0xFFF3E8FF))
                                              : (isDark ? Colors.blue.withValues(alpha: 0.2) : const Color(0xFFE0F2FE)),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              workspace.isEncrypted ? Icons.lock_outline_rounded : Icons.visibility_outlined,
                                              size: 10,
                                              color: workspace.isEncrypted ? const Color(0xFF9333EA) : const Color(0xFF0284C7),
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              workspace.isEncrypted ? 'Encrypted' : 'Viewable',
                                              style: TextStyle(
                                                fontFamily: FiloTypography.fontFamily,
                                                fontSize: 9.5,
                                                fontWeight: FontWeight.w800,
                                                color: workspace.isEncrypted ? const Color(0xFF9333EA) : const Color(0xFF0284C7),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isSelected) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: isDark ? Colors.white12 : FiloColors.primary.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            'ACTIVE',
                                            style: TextStyle(
                                              fontFamily: FiloTypography.fontFamily,
                                              fontSize: 9,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: 0.4,
                                              color: isDark ? Colors.white : FiloColors.primary,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    workspace.description,
                                    style: TextStyle(
                                      fontFamily: FiloTypography.fontFamily,
                                      fontSize: 12.5,
                                      color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isSelected)
                              Icon(
                                Icons.check_circle_rounded,
                                color: isDark ? Colors.white : FiloColors.primary,
                                size: 22,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 6),

              // + Create New Workspace Button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(context).pop();
                    onAddWorkspace();
                  },
                  borderRadius: BorderRadius.circular(100),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(100),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : Colors.black.withValues(alpha: 0.12),
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add_rounded,
                          size: 19,
                          color: isDark ? Colors.white70 : FiloColors.lightTextPrimary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Create New Space',
                          style: TextStyle(
                            fontFamily: FiloTypography.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
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
    ),
  ),
);
}
}
