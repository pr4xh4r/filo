import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filo/core/database/filo_database.dart';
import 'package:filo/core/database/node_model.dart';
import 'package:filo/core/theme/filo_theme.dart';
import 'package:filo/features/auth/presentation/providers/auth_provider.dart';
import 'package:filo/features/preview/presentation/screens/file_preview_screen.dart';

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

  group('FilePreviewScreen Swipe Gallery Tests', () {
    final now = DateTime.now();
    final photo1 = FileNode(
      id: 'photo_1',
      name: 'Sunset_Beach.jpg',
      type: NodeType.file,
      mimeType: 'image/jpeg',
      sizeBytes: 1024 * 500,
      createdAt: now,
      modifiedAt: now,
    );

    final photo2 = FileNode(
      id: 'photo_2',
      name: 'Mountain_Hike.png',
      type: NodeType.file,
      mimeType: 'image/png',
      sizeBytes: 1024 * 800,
      createdAt: now,
      modifiedAt: now,
    );

    final video1 = FileNode(
      id: 'video_1',
      name: 'Drone_Flight.mp4',
      type: NodeType.file,
      mimeType: 'video/mp4',
      sizeBytes: 1024 * 1024 * 12,
      createdAt: now,
      modifiedAt: now,
    );

    testWidgets('Renders single file preview without PageView counter', (tester) async {
      await tester.pumpWidget(wrapWithScope(FilePreviewScreen(node: photo1)));
      await tester.pump();

      expect(find.text('Sunset_Beach.jpg'), findsOneWidget);
      expect(find.text('1 of 1'), findsNothing);
    });

    testWidgets('Renders swipe gallery with counter and responds to swipe', (tester) async {
      final mediaList = [photo1, photo2, video1];

      await tester.pumpWidget(wrapWithScope(
        FilePreviewScreen(
          node: photo1,
          siblingNodes: mediaList,
          initialIndex: 0,
        ),
      ));
      await tester.pump();

      // Verify first item and counter
      expect(find.text('Sunset_Beach.jpg'), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);

      // Swipe left to move to next item
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      // Verify second item and updated counter
      expect(find.text('Mountain_Hike.png'), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget);

      // Swipe left again to move to video
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('Drone_Flight.mp4'), findsOneWidget);
      expect(find.text('3 of 3'), findsOneWidget);

      // Swipe right to return to previous item
      await tester.drag(find.byType(PageView), const Offset(500, 0));
      await tester.pumpAndSettle();

      expect(find.text('Mountain_Hike.png'), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget);
    });

    testWidgets('Opens directly at initialIndex when specified', (tester) async {
      final mediaList = [photo1, photo2, video1];

      await tester.pumpWidget(wrapWithScope(
        FilePreviewScreen(
          node: photo2,
          siblingNodes: mediaList,
          initialIndex: 1,
        ),
      ));
      await tester.pump();

      expect(find.text('Mountain_Hike.png'), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget);
    });
  });
}
