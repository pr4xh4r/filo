import 'package:flutter/material.dart';

/// App theme-aligned smart tags for files and folders.
/// Curated light-theme pastel palette: sophisticated, soft, and high contrast against frosted glass.
class SmartTag {
  final String id;
  final String name;
  final Color color;
  final Color bgColor;
  final IconData icon;

  const SmartTag({
    required this.id,
    required this.name,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  static const List<SmartTag> defaultTags = [
    SmartTag(
      id: 'personal',
      name: 'Personal',
      color: Color(0xFFB8863A), // Warm Amber / Sand
      bgColor: Color(0xFFFAF5ED),
      icon: Icons.person_outline_rounded,
    ),
    SmartTag(
      id: 'work',
      name: 'Work',
      color: Color(0xFF3E825B), // Muted Sage Green
      bgColor: Color(0xFFEEF6F1),
      icon: Icons.work_outline_rounded,
    ),
    SmartTag(
      id: 'finance',
      name: 'Finance',
      color: Color(0xFF456B96), // Soft Steel Slate Blue
      bgColor: Color(0xFFEDF3F9),
      icon: Icons.account_balance_wallet_outlined,
    ),
    SmartTag(
      id: 'vault',
      name: 'Secret',
      color: Color(0xFF755C99), // Dusky Mauve / Lavender
      bgColor: Color(0xFFF4EFF9),
      icon: Icons.lock_outline_rounded,
    ),
    SmartTag(
      id: 'important',
      name: 'Important',
      color: Color(0xFFFF6B4A), // Warm Coral / Sunset (matching Filo signature illustration)
      bgColor: Color(0xFFFFF0EC),
      icon: Icons.label_important_outline_rounded,
    ),
  ];

  static SmartTag? fromId(String id) {
    try {
      return defaultTags.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }
}
