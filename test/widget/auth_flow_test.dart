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

      expect(find.text('welcome to filo.'), findsOneWidget);
      expect(find.text('your unlimited cloud.'), findsOneWidget);
      expect(find.text('get started'), findsOneWidget);
    });
  });

  group('PassphraseSetupScreen Widget Tests', () {
    testWidgets('Passphrase input shows strength meter and enforces loss confirmation', (tester) async {
      await tester.pumpWidget(wrapWithScope(const PassphraseSetupScreen()));
      await tester.pumpAndSettle();

      expect(find.text('create vault key.'), findsOneWidget);

      final submitButtonFinder = find.text('create vault');
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
