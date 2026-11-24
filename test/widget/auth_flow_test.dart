import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filo/core/theme/filo_theme.dart';
import 'package:filo/features/auth/presentation/screens/passphrase_setup_screen.dart';
import 'package:filo/features/auth/presentation/screens/welcome_screen.dart';

void main() {
  Widget wrapWithScope(Widget child) {
    return ProviderScope(
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

      expect(find.text('Welcome to Filo'), findsOneWidget);
      expect(find.textContaining('Unlimited private storage'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
    });
  });

  group('PassphraseSetupScreen Widget Tests', () {
    testWidgets('Passphrase input shows strength meter and enforces loss confirmation', (tester) async {
      await tester.pumpWidget(wrapWithScope(const PassphraseSetupScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Create Vault Key'), findsOneWidget);

      final submitButtonFinder = find.text('Create Vault');
      expect(submitButtonFinder, findsOneWidget);

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
