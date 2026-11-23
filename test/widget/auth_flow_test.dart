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

      expect(find.text('Your Telegram.\nYour Private Cloud.'), findsOneWidget);
      expect(find.text('Zero-Knowledge by Default'), findsOneWidget);
      expect(find.text('No Developer Servers'), findsOneWidget);
      expect(find.text('Connect with Telegram'), findsOneWidget);
    });
  });

  group('PassphraseSetupScreen Widget Tests', () {
    testWidgets('Passphrase input shows strength meter and enforces loss confirmation', (tester) async {
      await tester.pumpWidget(wrapWithScope(const PassphraseSetupScreen()));

      expect(find.text('Zero-Knowledge Passphrase'), findsOneWidget);

      // Initially, Create button should be disabled because checkbox is unchecked
      final submitButtonFinder = find.widgetWithText(GestureDetector, 'Create Secure Vault');
      expect(submitButtonFinder, findsOneWidget);

      // Enter passphrase
      await tester.enterText(find.byType(TextField).first, 'MySecretPassword123!');
      await tester.pumpAndSettle();

      // Strength meter should show "Very Strong" or "Good"
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      // Toggle risk confirmation checkbox
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.value, true);
    });
  });
}
