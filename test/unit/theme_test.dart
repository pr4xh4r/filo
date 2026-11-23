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

    test('Locks to light theme mode', () {
      final notifier = ThemeModeNotifier();
      notifier.setThemeMode(ThemeMode.dark);
      expect(notifier.state, ThemeMode.light);

      notifier.setThemeMode(ThemeMode.system);
      expect(notifier.state, ThemeMode.light);
    });
  });
}
