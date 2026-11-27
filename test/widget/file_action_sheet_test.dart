import 'package:filo/core/database/node_model.dart';
import 'package:filo/features/files/presentation/widgets/file_action_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FileActionSheet does not overflow on standard compact phone', (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2.0; // 360 x 800 dp screen
    tester.view.padding = const FakeViewPadding(bottom: 44, top: 32);

    final node = FileNode(
      id: 'test-node-1',
      name: '300+ Free Premium ChatGPT_ Claude Prompts final - Google Sheets.pdf',
      type: NodeType.file,
      sizeBytes: 11500000,
      mimeType: 'application/pdf',
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  FileActionSheet.show(
                    context,
                    node: node,
                    onToggleFavorite: () {},
                    onRename: () {},
                    onMove: () {},
                    onShare: () {},
                    onDownload: () {},
                    onToggleOffline: () {},
                    onManageTags: () {},
                    onChangeWorkspace: () {},
                    onDelete: () {},
                  );
                },
                child: const Text('Open Sheet'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Add to Starred'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FileActionSheet does not overflow on extreme small screen', (tester) async {
    tester.view.physicalSize = const Size(640, 960);
    tester.view.devicePixelRatio = 2.0; // 320 x 480 dp screen
    tester.view.padding = const FakeViewPadding(bottom: 48, top: 24);

    final node = FileNode(
      id: 'test-node-2',
      name: 'Very Long Document Name That Could Potentially Break Everything If Layouts Were Bad.pdf',
      type: NodeType.file,
      sizeBytes: 98765432,
      mimeType: 'application/pdf',
      createdAt: DateTime.now(),
      modifiedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  FileActionSheet.show(
                    context,
                    node: node,
                    onToggleFavorite: () {},
                    onRename: () {},
                    onMove: () {},
                    onShare: () {},
                    onDownload: () {},
                    onToggleOffline: () {},
                    onManageTags: () {},
                    onChangeWorkspace: () {},
                    onDelete: () {},
                  );
                },
                child: const Text('Open Sheet'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
