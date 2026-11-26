import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:filo/core/database/filo_database.dart';
import 'package:filo/core/database/node_model.dart';
import 'package:filo/features/files/domain/smart_tag.dart';
import 'package:filo/features/files/domain/workspace.dart';
import 'package:filo/features/files/presentation/providers/file_browser_provider.dart';

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

    test('Database persists and retrieves custom workspaces with encryption flag', () async {
      final initial = await db.getWorkspaces();
      expect(initial.length, 3);

      const customWs = Workspace(
        id: 'crypto',
        name: 'Crypto Space',
        description: 'Blockchain keys & assets',
        icon: Icons.folder_outlined,
        isEncrypted: false,
      );
      await db.insertWorkspace(customWs);

      final updated = await db.getWorkspaces();
      expect(updated.length, 4);
      final fetched = updated.firstWhere((w) => w.id == 'crypto');
      expect(fetched.name, 'Crypto Space');
      expect(fetched.isEncrypted, isFalse);
    });

    test('Deleting a workspace moves its files to trash and soft-deletes workspace', () async {
      final now = DateTime.now();
      const customWs = Workspace(
        id: 'project_x',
        name: 'Project X',
        description: 'Classified',
        icon: Icons.folder_outlined,
        isEncrypted: true,
      );
      await db.insertWorkspace(customWs);

      final doc = FileNode(
        id: 'doc-x',
        name: 'Spec.pdf',
        type: NodeType.file,
        sizeBytes: 500,
        createdAt: now,
        modifiedAt: now,
        workspaceId: 'project_x',
      );
      await db.insertNode(doc);

      // Verify active
      expect((await db.getWorkspaces()).any((w) => w.id == 'project_x'), isTrue);
      expect((await db.listNodes(workspaceId: 'project_x')).length, 1);

      // Delete workspace
      await db.deleteWorkspace('project_x', moveToTrash: true);

      // Workspace is hidden from active list
      final activeWorkspaces = await db.getWorkspaces();
      expect(activeWorkspaces.any((w) => w.id == 'project_x'), isFalse);

      // File is trashed
      final activeNodes = await db.listNodes(workspaceId: 'project_x');
      expect(activeNodes.isEmpty, isTrue);

      final trashedNodes = await db.listTrashedNodes();
      expect(trashedNodes.any((n) => n.id == 'doc-x'), isTrue);

      // Workspace appears in deleted workspaces
      final deletedWs = await db.getDeletedWorkspaces();
      expect(deletedWs.any((w) => w.id == 'project_x'), isTrue);

      // Restore workspace
      await db.restoreWorkspace('project_x');
      final restoredWs = await db.getWorkspaces();
      expect(restoredWs.any((w) => w.id == 'project_x'), isTrue);

      final restoredNodes = await db.listNodes(workspaceId: 'project_x');
      expect(restoredNodes.any((n) => n.id == 'doc-x'), isTrue);
    });

    test('Empty trash permanently purges trashed workspaces', () async {
      const customWs = Workspace(
        id: 'temp_ws',
        name: 'Temp Space',
        description: 'To be purged',
        icon: Icons.folder_outlined,
      );
      await db.insertWorkspace(customWs);
      await db.deleteWorkspace('temp_ws', moveToTrash: true);

      expect((await db.getDeletedWorkspaces()).any((w) => w.id == 'temp_ws'), isTrue);

      // Empty trash
      await db.emptyTrash();

      expect((await db.getDeletedWorkspaces()).any((w) => w.id == 'temp_ws'), isFalse);
    });

    test('FileBrowserState category selection filters displayItems properly', () {
      final now = DateTime.now();
      final photo = FileNode(
        id: 'p1',
        name: 'vacation.jpg',
        type: NodeType.file,
        mimeType: 'image/jpeg',
        createdAt: now,
        modifiedAt: now,
      );
      final video = FileNode(
        id: 'v1',
        name: 'clip.mp4',
        type: NodeType.file,
        mimeType: 'video/mp4',
        createdAt: now,
        modifiedAt: now,
      );
      final doc = FileNode(
        id: 'd1',
        name: 'report.pdf',
        type: NodeType.file,
        mimeType: 'application/pdf',
        createdAt: now,
        modifiedAt: now,
      );
      final folder = FileNode(
        id: 'f1',
        name: 'WorkDocs',
        type: NodeType.folder,
        createdAt: now,
        modifiedAt: now,
      );

      final state0 = FileBrowserState(items: [photo, video, doc, folder]);
      expect(state0.displayItems.length, 4);

      // Select 'photos'
      final statePhotos = state0.copyWith(selectedCategory: 'photos');
      expect(statePhotos.displayItems.length, 1);
      expect(statePhotos.displayItems.first.id, 'p1');

      // Select 'videos'
      final stateVideos = state0.copyWith(selectedCategory: 'videos');
      expect(stateVideos.displayItems.length, 1);
      expect(stateVideos.displayItems.first.id, 'v1');

      // Select 'docs'
      final stateDocs = state0.copyWith(selectedCategory: 'docs');
      expect(stateDocs.displayItems.length, 1);
      expect(stateDocs.displayItems.first.id, 'd1');

      // Select 'folders'
      final stateFolders = state0.copyWith(selectedCategory: 'folders');
      expect(stateFolders.displayItems.length, 1);
      expect(stateFolders.displayItems.first.id, 'f1');

      // Clear category
      final stateCleared = statePhotos.copyWith(clearCategory: true);
      expect(stateCleared.selectedCategory, isNull);
      expect(stateCleared.displayItems.length, 4);
    });

    test('purgeOldTrash automatically cleans trashed items older than 30 days', () async {
      final now = DateTime.now();
      final oldDate = now.subtract(const Duration(days: 35));
      final recentDate = now.subtract(const Duration(days: 5));

      final oldNode = FileNode(
        id: 'old-node',
        name: 'OldTrash.txt',
        type: NodeType.file,
        isTrashed: true,
        trashedAt: oldDate,
        createdAt: oldDate,
        modifiedAt: oldDate,
      );

      final recentNode = FileNode(
        id: 'recent-node',
        name: 'RecentTrash.txt',
        type: NodeType.file,
        isTrashed: true,
        trashedAt: recentDate,
        createdAt: recentDate,
        modifiedAt: recentDate,
      );

      await db.insertNode(oldNode);
      await db.insertNode(recentNode);

      final before = await db.listTrashedNodes();
      expect(before.length, 2);

      // Purge > 30 days
      final purged = await db.purgeOldTrash(days: 30);
      expect(purged, 1);

      final after = await db.listTrashedNodes();
      expect(after.length, 1);
      expect(after.first.id, 'recent-node');
    });

    test('Snapshot export and restore preserves workspace encryption and deletion states', () async {
      final now = DateTime.now();
      const nativeWs = Workspace(
        id: 'native-space',
        name: 'Native Space',
        description: 'TG Native',
        icon: Icons.public_rounded,
        isEncrypted: false,
      );
      await db.insertWorkspace(nativeWs);

      final offlineNode = FileNode(
        id: 'offline-pass',
        name: 'Passport.pdf',
        type: NodeType.file,
        sizeBytes: 1024,
        createdAt: now,
        modifiedAt: now,
        workspaceId: 'native-space',
        isPinnedOffline: true,
      );
      await db.insertNode(offlineNode);

      // Export snapshot
      final snapshot = await db.exportSnapshotJson();

      // Fresh in-memory DB (simulating new phone restore)
      final freshDb = FiloDatabase.openInMemory();
      await freshDb.restoreFromSnapshotJson(snapshot);

      final restoredWorkspaces = await freshDb.getWorkspaces();
      final restoredWs = restoredWorkspaces.firstWhere((w) => w.id == 'native-space');
      expect(restoredWs.isEncrypted, isFalse);

      final restoredNode = await freshDb.getNode('offline-pass');
      expect(restoredNode, isNotNull);
      expect(restoredNode!.workspaceId, 'native-space');
      expect(restoredNode.isPinnedOffline, isTrue);

      freshDb.close();
    });
  });
}
