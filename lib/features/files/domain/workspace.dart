import 'package:flutter/material.dart';
import '../../../../core/theme/filo_colors.dart';

/// Workspace model defining isolated vaults/spaces for the user.
class Workspace {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color accentColor;

  const Workspace({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.accentColor = FiloColors.primary,
  });

  static const List<Workspace> defaults = [
    Workspace(
      id: 'personal',
      name: 'Personal Space',
      description: 'Photos, personal documents & daily files',
      icon: Icons.folder_outlined,
      accentColor: FiloColors.primary,
    ),
    Workspace(
      id: 'work',
      name: 'Work Space',
      description: 'Projects, client contracts & invoices',
      icon: Icons.business_center_outlined,
      accentColor: FiloColors.primary,
    ),
    Workspace(
      id: 'private',
      name: 'Private Vault',
      description: 'Encrypted isolated sensitive storage',
      icon: Icons.lock_outline_rounded,
      accentColor: FiloColors.primary,
    ),
  ];

  static Workspace fromId(String id, [List<Workspace>? allWorkspaces]) {
    final pool = allWorkspaces ?? defaults;
    try {
      return pool.firstWhere((w) => w.id == id);
    } catch (_) {
      // Dynamic fallback for custom workspaces: never fall back to personal space!
      final cleanName = id
          .replaceAll('_', ' ')
          .replaceAll('-', ' ')
          .split(' ')
          .map((s) => s.isNotEmpty ? '${s[0].toUpperCase()}${s.substring(1)}' : '')
          .join(' ')
          .trim();
      return Workspace(
        id: id,
        name: cleanName.isNotEmpty ? cleanName : 'Custom Space',
        description: 'Personal storage space',
        icon: Icons.folder_outlined,
        accentColor: FiloColors.primary,
      );
    }
  }
}
