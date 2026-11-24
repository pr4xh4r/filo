import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'filo_colors.dart';
import 'filo_radius.dart';
import 'filo_typography.dart';

/// Complete theme definitions for Filo with Ethereal Dawn frosted-glass aesthetics.
class FiloTheme {
  FiloTheme._();

  static const _cupertinoTransitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
    },
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      pageTransitionsTheme: _cupertinoTransitions,
      primaryColor: FiloColors.primary,
      scaffoldBackgroundColor: FiloColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: FiloColors.primary,
        secondary: FiloColors.accentCoral,
        surface: FiloColors.lightSurface,
        error: FiloColors.destructive,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: FiloColors.lightTextPrimary,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: FiloColors.lightTextPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: FiloColors.lightTextPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white.withValues(alpha: 0.75),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: FiloRadius.roundedXl,
          side: BorderSide(color: Colors.white.withValues(alpha: 0.85), width: 1.2),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        fillColor: Colors.transparent,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: FiloTypography.body.copyWith(color: FiloColors.lightTextTertiary),
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
      dividerTheme: const DividerThemeData(
        color: FiloColors.lightBorder,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: FiloColors.primary,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: FiloRadius.roundedMd),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: FiloRadius.roundedXl,
          side: const BorderSide(color: FiloColors.lightBorder, width: 0.8),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16),
        textColor: FiloColors.lightTextPrimary,
        iconColor: FiloColors.lightTextSecondary,
      ),
    );
  }

  static ThemeData get darkTheme => lightTheme; // App is pure luxury light theme
}
