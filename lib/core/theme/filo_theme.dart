import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'filo_colors.dart';
import 'filo_radius.dart';

/// Complete theme definitions (Light & Dark) for Filo.
class FiloTheme {
  FiloTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: FiloColors.primary,
      scaffoldBackgroundColor: FiloColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: FiloColors.primary,
        secondary: FiloColors.primary,
        surface: FiloColors.lightSurface,
        error: FiloColors.destructive,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: FiloColors.lightTextPrimary,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: FiloColors.lightBackground,
        foregroundColor: FiloColors.lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: FiloColors.lightTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: FiloColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: FiloRadius.roundedLg,
          side: const BorderSide(color: FiloColors.lightBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: FiloColors.lightBorder,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: FiloColors.darkSurface,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: FiloRadius.roundedMd),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      primaryColor: FiloColors.primary,
      scaffoldBackgroundColor: FiloColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: FiloColors.primary,
        secondary: FiloColors.primary,
        surface: FiloColors.darkSurface,
        error: FiloColors.destructive,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: FiloColors.darkTextPrimary,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: FiloColors.darkBackground,
        foregroundColor: FiloColors.darkTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          color: FiloColors.darkTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: FiloColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: FiloRadius.roundedLg,
          side: const BorderSide(color: FiloColors.darkBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      dividerTheme: const DividerThemeData(
        color: FiloColors.darkBorder,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: FiloColors.darkSurfaceSecondary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: FiloRadius.roundedMd),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
