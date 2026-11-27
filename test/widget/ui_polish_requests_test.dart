import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filo/core/database/filo_database.dart';
import 'package:filo/core/database/node_model.dart';
import 'package:filo/core/theme/filo_theme.dart';
import 'package:filo/features/auth/presentation/providers/auth_provider.dart';
import 'package:filo/features/auth/presentation/screens/app_lock_screen.dart';
import 'package:filo/features/auth/presentation/screens/passphrase_setup_screen.dart';
import 'package:filo/features/files/domain/workspace.dart';
import 'package:filo/features/files/presentation/screens/file_browser_screen.dart';
import 'package:filo/features/files/presentation/widgets/workspace_switcher_sheet.dart';
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

  group('WorkspaceSwitcherSheet UI Polish', () {
    testWidgets('Shows only lock/eye icons instead of Encrypted/Viewable/ACTIVE text blocks', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: FiloTheme.lightTheme,
          home: Scaffold(
            body: WorkspaceSwitcherSheet(
              activeWorkspaceId: 'personal',
              workspaces: const [
                Workspace(
                  id: 'personal',
                  name: 'Vault Space',
                  description: 'Encrypted storage',
                  icon: Icons.folder_outlined,
                  isEncrypted: true,
                ),
                Workspace(
                  id: 'media',
                  name: 'Public Gallery',
                  description: 'Direct Telegram storage',
                  icon: Icons.photo_library_outlined,
                  isEncrypted: false,
                ),
              ],
              onWorkspaceSelected: (_) {},
              onAddWorkspace: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vault Space'), findsOneWidget);
      expect(find.text('Public Gallery'), findsOneWidget);

      // Icons shown for encrypted vs viewable
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      // No Encrypted, Viewable, or ACTIVE badge text blocks
      expect(find.text('Encrypted'), findsNothing);
      expect(find.text('Viewable'), findsNothing);
      expect(find.text('ACTIVE'), findsNothing);
    });
  });

  group('Password Visibility Eye Toggles Across App', () {
    testWidgets('AppLockScreen unlock and recovery dialogs toggle password visibility', (tester) async {
      await tester.pumpWidget(wrapWithScope(const AppLockScreen()));
      await tester.pumpAndSettle();

      // Main unlock field starts obscured with eye toggle
      final mainFieldFinder = find.byType(TextField).first;
      expect(tester.widget<TextField>(mainFieldFinder).obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_off_outlined).first);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(mainFieldFinder).obscureText, isFalse);

      // Open Emergency Recovery dialog and test New Passphrase eye toggle
      await tester.tap(find.text('Forgot key? Use Recovery Key'));
      await tester.pumpAndSettle();

      final newPwdFieldFinder = find.widgetWithText(TextField, 'Set fresh passphrase (min 8 chars)');
      expect(tester.widget<TextField>(newPwdFieldFinder).obscureText, isTrue);

      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byIcon(Icons.visibility_off_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(newPwdFieldFinder).obscureText, isFalse);
    });

    testWidgets('PassphraseSetupScreen toggles both Choose and Confirm passphrase visibility', (tester) async {
      await tester.pumpWidget(wrapWithScope(const PassphraseSetupScreen()));
      await tester.pumpAndSettle();

      final chooseField = find.widgetWithText(TextField, 'Choose your key (min 8 chars)');
      final confirmField = find.widgetWithText(TextField, 'Confirm your key');
      expect(tester.widget<TextField>(chooseField).obscureText, isTrue);
      expect(tester.widget<TextField>(confirmField).obscureText, isTrue);

      final eyeButtons = find.byIcon(Icons.visibility_off_outlined);
      expect(eyeButtons, findsNWidgets(2));

      await tester.tap(eyeButtons.at(0));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(chooseField).obscureText, isFalse);
      expect(tester.widget<TextField>(confirmField).obscureText, isTrue);

      await tester.tap(find.byIcon(Icons.visibility_off_outlined).first);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(confirmField).obscureText, isFalse);
    });

    testWidgets('SettingsScreen Change Passphrase dialog toggles both old and new passphrase visibility', (tester) async {
      await tester.pumpWidget(wrapWithScope(const SettingsScreen()));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('Change Master Passphrase'), 200);
      await tester.tap(find.text('Change Master Passphrase'));
      await tester.pumpAndSettle();

      final currentField = find.widgetWithText(TextField, 'Current Passphrase');
      final newField = find.widgetWithText(TextField, 'New Passphrase (min 8 chars)');
      expect(tester.widget<TextField>(currentField).obscureText, isTrue);
      expect(tester.widget<TextField>(newField).obscureText, isTrue);

      final eyeButtons = find.descendant(
        of: find.byType(Dialog),
        matching: find.byIcon(Icons.visibility_off_outlined),
      );
      expect(eyeButtons, findsNWidgets(2));

      await tester.tap(eyeButtons.at(0));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(currentField).obscureText, isFalse);

      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byIcon(Icons.visibility_off_outlined),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(newField).obscureText, isFalse);
    });
  });

  group('FileBrowserScreen Header & Clickable Categories', () {
    testWidgets('Removes top transfer button and filters items when clicking categories', (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final now = DateTime.now();
      await db.insertNode(FileNode(
        id: 'p1',
        name: 'beach.jpg',
        type: NodeType.file,
        mimeType: 'image/jpeg',
        createdAt: now,
        modifiedAt: now,
      ));
      await db.insertNode(FileNode(
        id: 'v1',
        name: 'trip.mp4',
        type: NodeType.file,
        mimeType: 'video/mp4',
        createdAt: now,
        modifiedAt: now,
      ));
      await db.insertNode(FileNode(
        id: 'f1',
        name: 'ArchiveFolder',
        type: NodeType.folder,
        createdAt: now,
        modifiedAt: now,
      ));

      await tester.pumpWidget(wrapWithScope(const FileBrowserScreen()));
      await tester.pumpAndSettle();

      // Only 1 transfer icon exists (bottom navbar), NOT a duplicate top header transfer button between search and trash
      expect(find.byIcon(Icons.swap_vert_rounded), findsOneWidget);
      expect(find.byIcon(Icons.search_rounded), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

      // All 3 items visible initially
      expect(find.text('beach.jpg'), findsOneWidget);
      expect(find.text('trip.mp4'), findsOneWidget);
      expect(find.text('ArchiveFolder'), findsOneWidget);

      // Tap Photos category card
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();

      expect(find.text('beach.jpg'), findsOneWidget);
      expect(find.text('trip.mp4'), findsNothing);
      expect(find.text('ArchiveFolder'), findsNothing);
      expect(find.text('Show all'), findsOneWidget);

      // Tap Videos category card
      await tester.tap(find.text('Videos'));
      await tester.pumpAndSettle();

      expect(find.text('beach.jpg'), findsNothing);
      expect(find.text('trip.mp4'), findsOneWidget);
      expect(find.text('ArchiveFolder'), findsNothing);

      // Scroll horizontally if needed and tap Folders category card
      final categoriesScrollable = find
          .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right)
          .first;
      await tester.scrollUntilVisible(
        find.text('Folders'),
        150,
        scrollable: categoriesScrollable,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Folders'));
      await tester.pumpAndSettle();

      expect(find.text('beach.jpg'), findsNothing);
      expect(find.text('trip.mp4'), findsNothing);
      expect(find.text('ArchiveFolder'), findsOneWidget);

      // Tap Show all to restore full list
      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();

      expect(find.text('beach.jpg'), findsOneWidget);
      expect(find.text('trip.mp4'), findsOneWidget);
      expect(find.text('ArchiveFolder'), findsOneWidget);
    });
  });
}
