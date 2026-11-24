import 'package:flutter/material.dart';

/// Centralized color tokens for Filo (Ethereal Dawn Frosted Glass Aesthetic).
///
/// Designed with luxury optical glass, warm apricot rose, champagne glow,
/// and misty arctic lavender, anchored by deep midnight ink typography (#0F172A).
class FiloColors {
  FiloColors._();

  // Primary Accent & Core Inks
  static const Color primary = Color(0xFF0F172A); // Deep Midnight Ink
  static const Color primaryHover = Color(0xFF1E293B);
  static const Color primaryMuted = Color(0xFFF1F5F9);
  static const Color primaryDarkMuted = Color(0xFF1E293B);

  // Brand backward-compatible aliases
  static const Color brandIndigo = Color(0xFF0284C7);
  static const Color accentOrchid = Color(0xFF8B5CF6);
  static const Color brandObsidian = Color(0xFF0F172A);
  static const Color brandWhite = Color(0xFFFFFFFF);

  // Ethereal Dawn Flagship Accents
  static const Color accentCoral = Color(0xFFFF6B4A); // Coral Peach
  static const Color accentLavender = Color(0xFF8B5CF6); // Soft Electric Lavender
  static const Color accentApricot = Color(0xFFFFD7CA); // Warm Apricot Rose
  static const Color accentChampagne = Color(0xFFFFF2EB); // Champagne Glow
  static const Color accentArctic = Color(0xFFE8E3FA); // Misty Arctic Lavender

  // Status & Feedback Colors
  static const Color success = Color(0xFF10B981); // Emerald
  static const Color successMuted = Color(0xFFECFDF5);
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color warningMuted = Color(0xFFFFFBEB);
  static const Color destructive = Color(0xFFEF4444); // Crimson
  static const Color destructiveMuted = Color(0xFFFEF2F2);
  static const Color info = Color(0xFF0284C7); // Sky
  static const Color infoMuted = Color(0xFFF0F9FF);

  // Light Mode Canvas & Surfaces (Ethereal Dawn)
  static const Color lightBackground = Color(0xFFFAF8FC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSecondary = Color(0xFFF8F6FC);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightBorderSubtle = Color(0xFFF1F5F9);
  static const Color lightTextPrimary = Color(0xFF0F172A); // Deep Midnight Ink
  static const Color lightTextSecondary = Color(0xFF475569); // Refined Slate
  static const Color lightTextTertiary = Color(0xFF94A3B8); // Muted Slate

  // Dark Compatibility (Kept aligned with Midnight Ink)
  static const Color darkBackground = Color(0xFF0A071A);
  static const Color darkSurface = Color(0xFF140F2E);
  static const Color darkSurfaceSecondary = Color(0xFF1E1842);
  static const Color darkBorder = Color(0xFF2E265C);
  static const Color darkBorderSubtle = Color(0xFF231C4A);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFA5A1BF);
  static const Color darkTextTertiary = Color(0xFF6C6788);

  // Optical Frosted Glass Materials
  static const Color lightOverlay = Color(0x33000000);
  static const Color darkOverlay = Color(0x66000000);
  static const Color glassLight = Color(0xB3FFFFFF); // 70% White Liquid Glass
  static const Color glassBorder = Color(0xD9FFFFFF); // 85% Specular White Highlight
  static const Color glassDark = Color(0xCC140F2E);

  // Ethereal Dawn Multi-Stop Mesh Gradients (Light Mode)
  static const List<Color> etherealDawnGradient = [
    Color(0xFFFFD7CA), // Apricot Rose (Top)
    Color(0xFFFFF2EB), // Champagne (Mid-high)
    Color(0xFFFAF8FC), // Porcelain (Center)
    Color(0xFFE8E3FA), // Arctic Lavender (Bottom)
  ];

  // Midnight Aurora Multi-Stop Mesh Gradients (Dark Mode)
  static const List<Color> etherealDarkGradient = [
    Color(0xFF1E1438), // Midnight Plum Aurora (Top)
    Color(0xFF140D2B), // Deep Obsidian Violet
    Color(0xFF0C081A), // Void Slate
    Color(0xFF06040F), // Deepest Void Slate (Bottom)
  ];

  static const List<Color> etherealDawnSubtle = [
    Color(0xFFFFF2EB),
    Color(0xFFFAF8FC),
    Color(0xFFF0ECFC),
  ];

  // Hero Card Gradient (Warm Apricot into Champagne)
  static const List<Color> heroGradient = [
    Color(0xFFFFE0D6),
    Color(0xFFFFF2EB),
    Color(0xFFF8F4FD),
  ];

  static const List<Color> heroGradientDark = [
    Color(0xFF181238),
    Color(0xFF0E0A24),
  ];

  static const List<Color> brandGradient = [
    Color(0xFFFF6B4A),
    Color(0xFF8B5CF6),
  ];
}
