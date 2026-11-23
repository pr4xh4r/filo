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

  // Primary Accent Brand Colors
  static const Color primary = Color(0xFF5E6CE7); // Electric Indigo
  static const Color primaryHover = Color(0xFF4C59DB);
  static const Color primaryMuted = Color(0xFFEEF0FC);
  static const Color primaryDarkMuted = Color(0xFF18153A);
  static const Color accentOrchid = Color(0xFFC645F9);

  // Status & Feedback Colors
  static const Color success = Color(0xFF10B981); // Emerald
  static const Color successMuted = Color(0xFFECFDF5);
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color warningMuted = Color(0xFFFFFBEB);
  static const Color destructive = Color(0xFFEF4444); // Crimson
  static const Color destructiveMuted = Color(0xFFFEF2F2);
  static const Color info = Color(0xFF0EA5E9); // Sky
  static const Color infoMuted = Color(0xFFF0F9FF);

  // Light Mode (Soft Dreamlike Ambient Mesh & Milk Glass)
  static const Color lightBackground = Color(0xFFF6F8FC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSecondary = Color(0xFFEEF2F9);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightBorderSubtle = Color(0xFFEDF2F7);
  static const Color lightTextPrimary = Color(0xFF0D0425);
  static const Color lightTextSecondary = Color(0xFF64748B);
  static const Color lightTextTertiary = Color(0xFF94A3B8);

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

