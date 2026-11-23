import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages application-wide theme mode (System, Light, Dark)
/// with persistent secure storage backing.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final FlutterSecureStorage _storage;
  static const _keyThemeMode = 'filo_theme_mode_preference';
  bool _isInitialized = false;

  ThemeModeNotifier({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(),
        super(ThemeMode.system) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final saved = await _storage.read(key: _keyThemeMode);
      if (!_isInitialized) {
        if (saved == 'light') {
          state = ThemeMode.light;
        } else if (saved == 'dark') {
          state = ThemeMode.dark;
        } else {
          state = ThemeMode.system;
        }
        _isInitialized = true;
      }
    } catch (_) {
      if (!_isInitialized) {
        state = ThemeMode.system;
        _isInitialized = true;
      }
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _isInitialized = true;
    state = mode;
    String val = 'system';
    if (mode == ThemeMode.light) val = 'light';
    if (mode == ThemeMode.dark) val = 'dark';
    try {
      await _storage.write(key: _keyThemeMode, value: val);
    } catch (_) {}
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

/// Returns true when the active theme resolves to dark mode,
/// taking into account system dispatcher changes.
final isDarkProvider = Provider<bool>((ref) {
  final mode = ref.watch(themeModeProvider);
  if (mode == ThemeMode.dark) return true;
  if (mode == ThemeMode.light) return false;
  return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
});
