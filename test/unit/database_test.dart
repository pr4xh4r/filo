import 'package:flutter_test/flutter_test.dart';
import 'package:filo/core/database/filo_database.dart';
import 'package:filo/core/database/node_model.dart';
import 'package:filo/core/database/chunk_model.dart';

void main() {
  late FiloDatabase db;

  setUp(() {
    db = FiloDatabase.openInMemory();
  });

  tearDown(() {
    db.close();
  });

  group('FiloDatabase Node Operations', () {
    test('Create folders and nested files with breadcrumb resolution', () async {
      final now = DateTime.now();

      // Root folder
      final docsFolder = FileNode(
        id: 'folder_docs',
        name: 'Documents',
        type: NodeType.folder,
        createdAt: now,
        modifiedAt: now,
      );
      await db.insertNode(docsFolder);

      // Sub-folder
      final taxFolder = FileNode(
        id: 'folder_tax',
        parentId: 'folder_docs',
        name: 'Taxes 2026',
        type: NodeType.folder,
        createdAt: now,
        modifiedAt: now,
      );
      await db.insertNode(taxFolder);

      // File inside subfolder
      final file = FileNode(
        id: 'file_w2',
        parentId: 'folder_tax',
        name: 'w2_form.pdf',
        type: NodeType.file,
        sizeBytes: 1024 * 350,
        mimeType: 'application/pdf',
        contentHash: 'hash_w2_12345',
        createdAt: now,
        modifiedAt: now,
      );
      await db.insertNode(file);

      // Test listing root nodes
      final rootNodes = await db.listNodes();
      expect(rootNodes.length, 1);
      expect(rootNodes.first.name, 'Documents');

      // Test listing children of Documents
      final docChildren = await db.listNodes(parentId: 'folder_docs');
      expect(docChildren.length, 1);
      expect(docChildren.first.name, 'Taxes 2026');

      // Test listing children of Taxes
      final taxChildren = await db.listNodes(parentId: 'folder_tax');
      expect(taxChildren.length, 1);
      expect(taxChildren.first.name, 'w2_form.pdf');

      // Test breadcrumbs for file_w2
      final trail = await db.getBreadcrumbs('file_w2');
      expect(trail.length, 3);
      expect(trail[0].name, 'Documents');
      expect(trail[1].name, 'Taxes 2026');
      expect(trail[2].name, 'w2_form.pdf');
    });

    test('Rename and move nodes', () async {
      final now = DateTime.now();
      final node = FileNode(
        id: 'node_1',
        name: 'Original.txt',
        type: NodeType.file,
        createdAt: now,
        modifiedAt: now,
      );
      await db.insertNode(node);

      await db.renameNode('node_1', 'Renamed.txt');
      var updated = await db.getNode('node_1');
      expect(updated?.name, 'Renamed.txt');

      await db.moveNode('node_1', 'target_folder');
      updated = await db.getNode('node_1');
      expect(updated?.parentId, 'target_folder');
    });

    test('Trash bin, restore, and permanent purge', () async {
      final now = DateTime.now();
      final node = FileNode(
        id: 'node_trash',
        name: 'Draft.docx',
        type: NodeType.file,
        createdAt: now,
        modifiedAt: now,
      );
      await db.insertNode(node);

      // Initially in root listing
      var active = await db.listNodes();
      expect(active.length, 1);

      // Move to trash
      await db.trashNode('node_trash');
      active = await db.listNodes();
      expect(active.length, 0); // No longer in active listing

      final trashed = await db.listTrashedNodes();
      expect(trashed.length, 1);
      expect(trashed.first.name, 'Draft.docx');

      // Restore
      await db.restoreNode('node_trash');
      active = await db.listNodes();
      expect(active.length, 1);

      // Empty trash test
      await db.trashNode('node_trash');
      await db.emptyTrash();
      final afterEmpty = await db.listTrashedNodes();
      expect(afterEmpty.length, 0);
      expect(await db.getNode('node_trash'), isNull);
    });

    test('Search and filter favorites', () async {
      final now = DateTime.now();
      final n1 = FileNode(
        id: '1',
        name: 'Passport_Scan.jpg',
        type: NodeType.file,
        mimeType: 'image/jpeg',
        isFavorite: true,
        createdAt: now,
        modifiedAt: now,
      );
      final n2 = FileNode(
        id: '2',
        name: 'Notes.txt',
        type: NodeType.file,
        mimeType: 'text/plain',
        isFavorite: false,
        createdAt: now,
        modifiedAt: now,
      );
      await db.insertNode(n1);
      await db.insertNode(n2);

      // Search by name
      final searchResults = await db.listNodes(searchQuery: 'Passport');
      expect(searchResults.length, 1);
      expect(searchResults.first.name, 'Passport_Scan.jpg');

      // Filter favorites
      final favorites = await db.listNodes(onlyFavorites: true);
      expect(favorites.length, 1);
      expect(favorites.first.id, '1');
    });
  });

  group('FiloDatabase Chunk Operations', () {
    test('Insert and query chunks for multi-part file', () async {
      const chunks = [
        FileChunk(
          id: 'chunk_1',
          nodeId: 'large_file',
          chunkIndex: 0,
          remoteMessageId: 'msg_101',
          remoteFileId: 'file_101',
          sizeBytes: 15 * 1024 * 1024,
          sha256Hash: 'hash_part_0',
          ivHex: 'aabbccddeeff001122334455',
        ),
        FileChunk(
          id: 'chunk_2',
          nodeId: 'large_file',
          chunkIndex: 1,
          remoteMessageId: 'msg_102',
          remoteFileId: 'file_102',
          sizeBytes: 8 * 1024 * 1024,
          sha256Hash: 'hash_part_1',
          ivHex: '11223344556677889900aabb',
        ),
      ];

      await db.insertChunks(chunks);

      final retrieved = await db.getChunksForNode('large_file');
      expect(retrieved.length, 2);
      expect(retrieved[0].chunkIndex, 0);
      expect(retrieved[1].chunkIndex, 1);
      expect(retrieved[0].remoteFileId, 'file_101');
    });
  });

  group('FiloDatabase Storage Usage & Cloud Snapshot', () {
    test('Calculates storage categories accurately', () async {
      final now = DateTime.now();
      await db.insertNode(FileNode(
        id: 'f1',
        name: 'photo.jpg',
        type: NodeType.file,
        sizeBytes: 2000,
        mimeType: 'image/jpeg',
        createdAt: now,
        modifiedAt: now,
      ));
      await db.insertNode(FileNode(
        id: 'f2',
        name: 'video.mp4',
        type: NodeType.file,
        sizeBytes: 8000,
        mimeType: 'video/mp4',
        createdAt: now,
        modifiedAt: now,
      ));
      await db.insertNode(FileNode(
        id: 'folder1',
        name: 'My Folder',
        type: NodeType.folder,
        createdAt: now,
        modifiedAt: now,
      ));

      final stats = await db.getStorageUsage();
      expect(stats.totalBytes, 10000);
      expect(stats.imagesBytes, 2000);
      expect(stats.videosBytes, 8000);
      expect(stats.totalFiles, 2);
      expect(stats.totalFolders, 1);
    });

    test('Full snapshot export and restore round-trip', () async {
      final now = DateTime.now();
      final node = FileNode(
        id: 'n_cloud',
        name: 'cloud_file.pdf',
        type: NodeType.file,
        sizeBytes: 5000,
        mimeType: 'application/pdf',
        createdAt: now,
        modifiedAt: now,
      );
      await db.insertNode(node);

      const chunk = FileChunk(
        id: 'c_cloud',
        nodeId: 'n_cloud',
        chunkIndex: 0,
        remoteMessageId: 'm1',
        remoteFileId: 'rf1',
        sizeBytes: 5000,
        sha256Hash: 'hash1',
        ivHex: 'iv1',
      );
      await db.insertChunks([chunk]);

      // 1. Export snapshot
      final snapshotJson = await db.exportSnapshotJson();
      expect(snapshotJson.contains('cloud_file.pdf'), true);

      // 2. Open fresh empty database simulating a new device
      final freshDb = FiloDatabase.openInMemory();
      expect(await freshDb.listNodes(), isEmpty);

      // 3. Restore snapshot on the new device
      await freshDb.restoreFromSnapshotJson(snapshotJson);

      final restoredNodes = await freshDb.listNodes();
      expect(restoredNodes.length, 1);
      expect(restoredNodes.first.name, 'cloud_file.pdf');

      final restoredChunks = await freshDb.getChunksForNode('n_cloud');
      expect(restoredChunks.length, 1);
      expect(restoredChunks.first.remoteFileId, 'rf1');

      freshDb.close();
    });
  });
}
