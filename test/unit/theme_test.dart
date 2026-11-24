import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filo/core/theme/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeModeNotifier', () {
    test('Default mode is light', () {
      final notifier = ThemeModeNotifier();
      expect(notifier.state, ThemeMode.light);
    });

    test('Switches between light and dark theme mode', () {
      final notifier = ThemeModeNotifier();
      notifier.setThemeMode(ThemeMode.dark);
      expect(notifier.state, ThemeMode.dark);

      notifier.setThemeMode(ThemeMode.light);
      expect(notifier.state, ThemeMode.light);
    });

    test('Toggles theme mode', () {
      final notifier = ThemeModeNotifier();
      expect(notifier.state, ThemeMode.light);
      notifier.toggleTheme();
      expect(notifier.state, ThemeMode.dark);
      notifier.toggleTheme();
      expect(notifier.state, ThemeMode.light);
    });
  });
}
