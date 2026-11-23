import 'package:flutter/material.dart';

/// Centralized color tokens for Filo.
///
/// Principles:
/// - Restrained palette: neutral grays with a single sophisticated accent (Filo Electric Indigo / Blue).
/// - Semantic naming: surface, background, border, text, status colors.
/// - Minimum contrast: 4.5:1 on all text layers.
/// - Platform adaptive translucency support.
class FiloColors {
  FiloColors._();

  // Primary Accent Brand Colors
  static const Color primary = Color(0xFF3366FF); // Crisp Royal Indigo
  static const Color primaryHover = Color(0xFF254EDB);
  static const Color primaryMuted = Color(0xFFEBF1FF);
  static const Color primaryDarkMuted = Color(0xFF1E294B);

  // Status & Feedback Colors
  static const Color success = Color(0xFF10B981); // Emerald
  static const Color successMuted = Color(0xFFECFDF5);
  static const Color warning = Color(0xFFF59E0B); // Amber
  static const Color warningMuted = Color(0xFFFFFBEB);
  static const Color destructive = Color(0xFFEF4444); // Crimson
  static const Color destructiveMuted = Color(0xFFFEF2F2);
  static const Color info = Color(0xFF0EA5E9); // Sky
  static const Color infoMuted = Color(0xFFF0F9FF);

  // Light Mode Neutrals
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceSecondary = Color(0xFFF1F5F9);
  static const Color lightBorder = Color(0xFFE2E8F0);
  static const Color lightBorderSubtle = Color(0xFFF1F5F9);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF64748B);
  static const Color lightTextTertiary = Color(0xFF94A3B8);

  // Dark Mode Neutrals
  static const Color darkBackground = Color(0xFF0B0F19);
  static const Color darkSurface = Color(0xFF131B2E);
  static const Color darkSurfaceSecondary = Color(0xFF1E293B);
  static const Color darkBorder = Color(0xFF26334D);
  static const Color darkBorderSubtle = Color(0xFF1B2438);
  static const Color darkTextPrimary = Color(0xFFF8FAFC);
  static const Color darkTextSecondary = Color(0xFF94A3B8);
  static const Color darkTextTertiary = Color(0xFF64748B);

  // Overlays & Translucency
  static const Color lightOverlay = Color(0x66000000);
  static const Color darkOverlay = Color(0x99000000);
  static const Color glassLight = Color(0xCCFFFFFF);
  static const Color glassDark = Color(0xCC131B2E);
}
