import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filo/core/theme/filo_theme.dart';
import 'package:filo/shared/components/filo_button.dart';
import 'package:filo/shared/components/filo_card.dart';
import 'package:filo/shared/components/filo_empty_state.dart';
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
}
