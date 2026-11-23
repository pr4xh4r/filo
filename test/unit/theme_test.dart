import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filo/core/theme/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('ThemeModeNotifier', () {
    test('Default mode is system', () {
      final notifier = ThemeModeNotifier();
      expect(notifier.state, ThemeMode.system);
    });

    test('Can switch to light mode and persist', () async {
      const storage = FlutterSecureStorage();
      final notifier = ThemeModeNotifier(storage: storage);
      await notifier.setThemeMode(ThemeMode.light);
      expect(notifier.state, ThemeMode.light);
      expect(await storage.read(key: 'filo_theme_mode_preference'), 'light');
    });

    test('Can switch to dark mode and persist', () async {
      const storage = FlutterSecureStorage();
      final notifier = ThemeModeNotifier(storage: storage);
      await notifier.setThemeMode(ThemeMode.dark);
      expect(notifier.state, ThemeMode.dark);
      expect(await storage.read(key: 'filo_theme_mode_preference'), 'dark');
    });

    test('Can switch back to system mode', () async {
      const storage = FlutterSecureStorage();
      final notifier = ThemeModeNotifier(storage: storage);
      await notifier.setThemeMode(ThemeMode.dark);
      await notifier.setThemeMode(ThemeMode.system);
      expect(notifier.state, ThemeMode.system);
      expect(await storage.read(key: 'filo_theme_mode_preference'), 'system');
    });
  });
}
