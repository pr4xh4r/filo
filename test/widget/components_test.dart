import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filo/core/theme/filo_theme.dart';
import 'package:filo/features/auth/domain/country_code.dart';
import 'package:filo/features/auth/presentation/widgets/country_picker_sheet.dart';
import 'package:filo/features/auth/presentation/widgets/ios_verification_code_input.dart';
import 'package:filo/shared/components/filo_button.dart';
import 'package:filo/shared/components/filo_card.dart';
import 'package:filo/shared/components/filo_empty_state.dart';
import 'package:filo/shared/components/filo_logo_badge.dart';
import 'package:filo/shared/components/filo_progress_ring.dart';

void main() {
  Widget wrapWithTheme(Widget child) {
    return MaterialApp(
      theme: FiloTheme.lightTheme,
      darkTheme: FiloTheme.darkTheme,
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('FiloButton Widget Tests', () {
    testWidgets('Renders label and responds to tap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        wrapWithTheme(
          FiloButton(
            label: 'Submit Action',
            onPressed: () => tapped = true,
          ),
        ),
      );

      expect(find.text('Submit Action'), findsOneWidget);
      await tester.tap(find.text('Submit Action'));
      expect(tapped, true);
    });

    testWidgets('Displays spinner when isLoading is true and ignores tap', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        wrapWithTheme(
          FiloButton(
            label: 'Saving',
            isLoading: true,
            onPressed: () => tapped = true,
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(FiloButton));
      expect(tapped, false);
    });
  });

  group('FiloCard Widget Tests', () {
    testWidgets('Displays child and triggers onTap callback', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        wrapWithTheme(
          FiloCard(
            onTap: () => tapped = true,
            child: const Text('Card Content'),
          ),
        ),
      );

      expect(find.text('Card Content'), findsOneWidget);
      await tester.tap(find.text('Card Content'));
      expect(tapped, true);
    });
  });

  group('FiloEmptyState Widget Tests', () {
    testWidgets('Renders title, description, and action button', (tester) async {
      bool actionTriggered = false;

      await tester.pumpWidget(
        wrapWithTheme(
          FiloEmptyState(
            icon: Icons.folder_open_rounded,
            title: 'Empty Directory',
            description: 'No files uploaded yet',
            actionLabel: 'Add File',
            onAction: () => actionTriggered = true,
          ),
        ),
      );

      expect(find.text('Empty Directory'), findsOneWidget);
      expect(find.text('No files uploaded yet'), findsOneWidget);
      expect(find.text('Add File'), findsOneWidget);

      await tester.tap(find.text('Add File'));
      expect(actionTriggered, true);
    });
  });

  group('FiloProgressRing Widget Tests', () {
    testWidgets('Renders determinate progress', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const FiloProgressRing(value: 0.65),
        ),
      );

      final progressIndicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(progressIndicator.value, 0.65);
    });
  });

  group('FiloLogoBadge Widget Tests', () {
    testWidgets('Renders emblem with specified size', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const FiloLogoBadge(size: 96),
        ),
      );

      expect(find.byType(FiloLogoBadge), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });

  group('IosVerificationCodeInput Widget Tests', () {
    testWidgets('Renders 5 squircle boxes and triggers onCompleted', (tester) async {
      final controller = TextEditingController();
      String completedCode = '';

      await tester.pumpWidget(
        wrapWithTheme(
          IosVerificationCodeInput(
            length: 5,
            controller: controller,
            onCompleted: (val) => completedCode = val,
          ),
        ),
      );

      expect(find.byType(IosVerificationCodeInput), findsOneWidget);

      // Enter 5 digits
      controller.text = '12345';
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(completedCode, '12345');
    });

    testWidgets('Renders 6 squircle boxes and triggers onCompleted for 6 digits', (tester) async {
      final controller = TextEditingController();
      String completedCode = '';

      await tester.pumpWidget(
        wrapWithTheme(
          IosVerificationCodeInput(
            length: 6,
            controller: controller,
            onCompleted: (val) => completedCode = val,
          ),
        ),
      );

      expect(find.byType(IosVerificationCodeInput), findsOneWidget);

      controller.text = '123456';
      await tester.pumpAndSettle();

      expect(find.text('1'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(completedCode, '123456');
    });
  });

  group('CountryPickerSheet Widget Tests', () {
    testWidgets('Renders countries and filters by search query', (tester) async {
      CountryCode? selected;

      await tester.pumpWidget(
        wrapWithTheme(
          CountryPickerSheet(
            selectedCountry: CountryCode.defaultCountry,
            onSelect: (c) => selected = c,
          ),
        ),
      );

      expect(find.text('India'), findsOneWidget);
      expect(find.text('United States'), findsOneWidget);

      // Search for Germany
      await tester.enterText(find.byType(TextField), 'Germany');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(InkWell, 'Germany'), findsOneWidget);
      expect(find.text('India'), findsNothing);

      // Tap Germany
      await tester.tap(find.widgetWithText(InkWell, 'Germany'));
      expect(selected?.code, 'DE');
      expect(selected?.dialCode, '+49');
    });
  });
}
