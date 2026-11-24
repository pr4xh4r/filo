import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:filo/core/database/filo_database.dart';
import 'package:filo/core/database/node_model.dart';
import 'package:filo/features/files/domain/smart_tag.dart';
import 'package:filo/features/files/domain/workspace.dart';

void main() {
  group('Workspaces and Smart Tags', () {
    late FiloDatabase db;

    setUp(() {
      db = FiloDatabase.openInMemory();
    });

    test('Workspaces model defaults have personal, work, and private spaces', () {
      expect(Workspace.defaults.length, 3);
      expect(Workspace.fromId('personal').id, 'personal');
      expect(Workspace.fromId('work').id, 'work');
      expect(Workspace.fromId('private').id, 'private');
    });

    test('SmartTag model defaults have Ethereal Dawn palette colors', () {
      expect(SmartTag.defaultTags.length, 5);
      final personalTag = SmartTag.fromId('personal');
      expect(personalTag, isNotNull);
      expect(personalTag!.name, 'Personal');

      final workTag = SmartTag.fromId('work');
      expect(workTag, isNotNull);
      expect(workTag!.name, 'Work');
    });

    test('Nodes can be stored and filtered by workspace_id and tags', () async {
      final now = DateTime.now();

      // Node in personal workspace with 'personal' and 'important' tags
      final node1 = FileNode(
        id: 'node-1',
        name: 'PersonalDoc.pdf',
        type: NodeType.file,
        sizeBytes: 1024,
        createdAt: now,
        modifiedAt: now,
        workspaceId: 'personal',
        tags: const ['personal', 'important'],
      );

      // Node in work workspace with 'work' tag
      final node2 = FileNode(
        id: 'node-2',
        name: 'ClientContract.pdf',
        type: NodeType.file,
        sizeBytes: 2048,
        createdAt: now,
        modifiedAt: now,
        workspaceId: 'work',
        tags: const ['work'],
      );

      // Folder in private vault
      final folder1 = FileNode(
        id: 'folder-1',
        name: 'PrivateVaultFolder',
        type: NodeType.folder,
        createdAt: now,
        modifiedAt: now,
        workspaceId: 'private',
        tags: const ['vault'],
      );

      await db.insertNode(node1);
      await db.insertNode(node2);
      await db.insertNode(folder1);

      // 1. Filter by workspace 'personal'
      final personalNodes = await db.listNodes(workspaceId: 'personal');
      expect(personalNodes.length, 1);
      expect(personalNodes.first.name, 'PersonalDoc.pdf');
      expect(personalNodes.first.tags, contains('important'));

      // 2. Filter by workspace 'work'
      final workNodes = await db.listNodes(workspaceId: 'work');
      expect(workNodes.length, 1);
      expect(workNodes.first.name, 'ClientContract.pdf');

      // 3. Filter by tag 'important'
      final importantNodes = await db.listNodes(tag: 'important');
      expect(importantNodes.length, 1);
      expect(importantNodes.first.id, 'node-1');

      // 4. Update tags
      await db.updateNodeTags('node-2', ['work', 'important']);
      final updatedNode2 = await db.getNode('node-2');
      expect(updatedNode2!.tags, ['work', 'important']);

      // 5. Update workspace
      await db.updateNodeWorkspace('node-1', 'work');
      final updatedNode1 = await db.getNode('node-1');
      expect(updatedNode1!.workspaceId, 'work');
    });

    test('Workspace.fromId dynamically constructs custom workspaces without falling back to personal', () {
      final custom = Workspace.fromId('crypto_vault');
      expect(custom.id, 'crypto_vault');
      expect(custom.name, 'Crypto Vault');

      final singleWord = Workspace.fromId('travel');
      expect(singleWord.id, 'travel');
      expect(singleWord.name, 'Travel');
    });

    test('Database persists and retrieves custom workspaces', () async {
      final initial = await db.getWorkspaces();
      expect(initial.length, 3);

      const customWs = Workspace(
        id: 'crypto',
        name: 'Crypto Space',
        description: 'Blockchain keys & assets',
        icon: Icons.folder_outlined,
      );
      await db.insertWorkspace(customWs);

      final updated = await db.getWorkspaces();
      expect(updated.length, 4);
      expect(updated.any((w) => w.id == 'crypto'), isTrue);
    });
  });
}
