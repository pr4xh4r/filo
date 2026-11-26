import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filo/core/database/filo_database.dart';
import 'package:filo/core/theme/filo_theme.dart';
import 'package:filo/features/auth/presentation/providers/auth_provider.dart';
import 'package:filo/features/auth/presentation/screens/onboarding_cloud_choice_screen.dart';
import 'package:filo/features/auth/presentation/screens/passphrase_setup_screen.dart';
import 'package:filo/features/auth/presentation/screens/telegram_login_screen.dart';
import 'package:filo/features/auth/presentation/screens/welcome_screen.dart';
import 'package:filo/features/settings/presentation/screens/settings_screen.dart';

void main() {
  late FiloDatabase db;

  setUp(() {
    db = FiloDatabase.openInMemory();
  });

  tearDown(() {
    db.close();
  });

  Widget wrapWithScope(Widget child) {
    return ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        theme: FiloTheme.lightTheme,
        home: child,
      ),
    );
  }

  group('WelcomeScreen Widget Tests', () {
    testWidgets('Renders zero-knowledge commitment and connect button', (tester) async {
      await tester.pumpWidget(wrapWithScope(const WelcomeScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('Welcome to'), findsOneWidget);
      expect(find.text('filo'), findsOneWidget);
      expect(find.textContaining('Unlimited private storage'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets('Tapping Get Started navigates directly to TelegramLoginScreen', (tester) async {
      await tester.pumpWidget(wrapWithScope(const WelcomeScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Get Started'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));

      // Second page bypassed: goes directly to Telegram Login Screen
      expect(find.byType(TelegramLoginScreen), findsOneWidget);
      expect(find.text('Connect Telegram'), findsOneWidget);
    });
  });

  group('SettingsScreen Telegram Storage Guide Tests', () {
    testWidgets('Shows Telegram Cloud Guide tile and opens informative sheet', (tester) async {
      await tester.pumpWidget(wrapWithScope(const SettingsScreen()));
      await tester.pumpAndSettle();

      final guideTileFinder = find.text('Telegram Cloud Guide');
      expect(guideTileFinder, findsOneWidget);

      await tester.tap(guideTileFinder);
      await tester.pumpAndSettle();

      expect(find.text('Telegram Storage Guide'), findsOneWidget);
      expect(find.text('Encrypted'), findsOneWidget);
      expect(find.text('Unlimited'), findsOneWidget);
      expect(find.textContaining('This data is encrypted and will only be decrypted by Filo'), findsOneWidget);
      expect(find.text('Viewable'), findsOneWidget);
      expect(find.text('2 GB / 4 GB'), findsOneWidget);
      expect(find.textContaining('Standard limit is 2 GB per file; Telegram Premium unlocks 4 GB'), findsOneWidget);
    });
  });

  group('OnboardingCloudChoiceScreen Widget Tests', () {
    testWidgets('Renders Telegram guidance overview', (tester) async {
      await tester.pumpWidget(wrapWithScope(const OnboardingCloudChoiceScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Connect Telegram'), findsNWidgets(2));
      expect(find.text('Telegram Cloud Storage'), findsOneWidget);
      expect(find.text('Encrypted'), findsOneWidget);
      expect(find.text('Viewable Anywhere'), findsOneWidget);
      expect(find.textContaining('This data is encrypted and will only be decrypted by Filo'), findsOneWidget);
      expect(find.textContaining('Up to 2 GB per file'), findsOneWidget);
      expect(find.textContaining('Pairing a second device?'), findsOneWidget);
    });
  });

  group('PassphraseSetupScreen Widget Tests', () {
    testWidgets('Passphrase input shows strength meter and recovery options', (tester) async {
      await tester.pumpWidget(wrapWithScope(const PassphraseSetupScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Create Passphrase'), findsOneWidget);

      final submitButtonFinder = find.text('Create Space');
      expect(submitButtonFinder, findsOneWidget);

      // Verify prominent restore and pair options are visible
      expect(find.text('Already have a space?'), findsOneWidget);
      expect(find.text('Pair with token'), findsOneWidget);

      // Enter passphrase
      await tester.enterText(find.byType(TextField).first, 'MySecretPassword123!');
      await tester.pumpAndSettle();

      // Strength meter should show LinearProgressIndicator
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Toggle risk confirmation switch
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      final switchWidget = tester.widget<Switch>(find.byType(Switch));
      expect(switchWidget.value, true);
    });
  });
}
