import 'package:flutter/material.dart';

/// Centralized color tokens for Filo.
///
/// Designed with CRED luxury obsidian aesthetic and iOS 18 liquid glass materials.
/// Palette inspired by:
/// - `#0D0425` Deep Midnight Obsidian
/// - `#5E6CE7` Electric Indigo / Periwinkle
/// - `#C645F9` Vibrant Neon Orchid
/// - `#FFFFFF` Pure Crisp White
class FiloColors {
  FiloColors._();

  // Flagship Brand Palette (from design spec)
  static const Color brandObsidian = Color(0xFF0D0425);
  static const Color brandIndigo = Color(0xFF5E6CE7);
  static const Color brandOrchid = Color(0xFFC645F9);
  static const Color brandWhite = Color(0xFFFFFFFF);

  // Primary Accent Brand Colors (CRED & Apple Monochrome Luxury)
  static const Color primary = Color(0xFF111111); // Deep Obsidian Black
  static const Color primaryHover = Color(0xFF222222);
  static const Color primaryMuted = Color(0xFFF4F4F6);
  static const Color primaryDarkMuted = Color(0xFF18181C);
  static const Color accentOrchid = Color(0xFF111111);

  // Status & Feedback Colors
  static const Color success = Color(0xFF111111); // Monochrome Black
  static const Color successMuted = Color(0xFFF4F4F6);
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color warningMuted = Color(0xFFFFFBEB);
  static const Color destructive = Color(0xFFEF4444); // Crimson
  static const Color destructiveMuted = Color(0xFFFEF2F2);
  static const Color info = Color(0xFF111111); // Monochrome Black
  static const Color infoMuted = Color(0xFFF4F4F6);

  // Light Mode (Soft Dreamlike Ambient Mesh & Milk Glass)
  static const Color lightBackground = Color(0xFFF8F9FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSecondary = Color(0xFFF2F2F7);
  static const Color lightBorder = Color(0xFFE5E5EA);
  static const Color lightBorderSubtle = Color(0xFFEFEFF4);
  static const Color lightTextPrimary = Color(0xFF000000);
  static const Color lightTextSecondary = Color(0xFF3C3C43);
  static const Color lightTextTertiary = Color(0xFF8E8E93);

  // Dark Mode (CRED Obsidian Canvas with Subtle Jewel Undertones)
  static const Color darkBackground = Color(0xFF070414);
  static const Color darkSurface = Color(0xFF0F0B26);
  static const Color darkSurfaceSecondary = Color(0xFF191438);
  static const Color darkBorder = Color(0xFF28204E);
  static const Color darkBorderSubtle = Color(0xFF1E1740);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFA5A1BF);
  static const Color darkTextTertiary = Color(0xFF6C6788);

  // Liquid Glass Material Gradients & Overlays
  static const Color lightOverlay = Color(0x66000000);
  static const Color darkOverlay = Color(0x99000000);
  static const Color glassLight = Color(0xD9FFFFFF);
  static const Color glassDark = Color(0xCC0F0B26);

  // Ambient Gradient Stops
  static const List<Color> brandGradient = [
    Color(0xFFC645F9),
    Color(0xFF5E6CE7),
  ];

  // Deep Obsidian / Titanium Diamond Gradient (CRED & Apple Monochrome Luxury)
  static const List<Color> heroGradient = [
    Color(0xFF0F0F12), // Deep Obsidian
    Color(0xFF18181D), // Midnight Graphite
    Color(0xFF222228), // Sleek Titanium
  ];

  static const List<Color> heroGradientDark = [
    Color(0xFF0A0A0C),
    Color(0xFF141418),
  ];

  static const List<Color> darkMeshGradient = [
    Color(0xFF070414),
    Color(0xFF0D0425),
    Color(0xFF140B33),
  ];

  static const List<Color> lightMeshGradient = [
    Color(0xFFF8F5FF),
    Color(0xFFEDF2FF),
    Color(0xFFF4F8FE),
  ];
}

