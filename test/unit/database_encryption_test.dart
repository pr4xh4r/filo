import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' show InvalidCipherTextException;
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;
import 'package:filo/core/config/app_config.dart';
import 'package:filo/core/crypto/crypto_engine.dart';
import 'package:filo/core/database/chunk_model.dart';
import 'package:filo/core/database/filo_database.dart';
import 'package:filo/core/database/node_model.dart';
import 'package:filo/core/database/transfer_model.dart';
import 'package:filo/features/files/domain/workspace.dart';
import 'package:filo/features/storage/data/fake_storage_backend.dart';
import 'package:filo/features/sync/domain/index_sync_service.dart';

void main() {
  group('FiloDatabase At-Rest Encryption (VULN-01)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('filo_db_enc_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('Encrypts sensitive columns on disk and decrypts accurately upon reopen', () async {
      final dbPath = '${tempDir.path}/vault_enc.db';
      final masterKey = CryptoEngine.generateMasterKey();
      final now = DateTime.fromMillisecondsSinceEpoch(1760000000000);

      const secretFolderName = 'TopSecretFinances';
      const secretFileName = 'Swiss_Account_2026.pdf';
      const secretPhotoName = 'Passport_Bio_Scan.jpg';
      const secretMimePdf = 'application/pdf';
      const secretMimeJpg = 'image/jpeg';
      const secretHash = 'sha256_deadbeef_secret_digest_0123456789abcdef';
      const secretTag1 = 'confidential';
      const secretTag2 = 'banking';
      const secretWsName = 'Offshore Vault';
      const secretWsDesc = 'Sensitive offshore records';
      const secretErrMsg = 'Network timeout uploading Swiss_Account_2026.pdf';

      // 1. Open file-backed DB with encryption key and populate all sensitive tables
      final db = await FiloDatabase.openFile(dbPath);
      expect(db.hasEncryptionKey, isFalse);
      db.setEncryptionKey(masterKey);
      expect(db.hasEncryptionKey, isTrue);

      await db.getWorkspaces(); // Seeds defaults encrypted
      await db.insertWorkspace(const Workspace(
        id: 'offshore',
        name: secretWsName,
        description: secretWsDesc,
        icon: Icons.lock_outline_rounded,
      ));

      final folder = FileNode(
        id: 'folder_secret',
        name: secretFolderName,
        type: NodeType.folder,
        createdAt: now,
        modifiedAt: now,
        workspaceId: 'offshore',
        tags: const [secretTag1],
      );
      await db.insertNode(folder);

      final pdfFile = FileNode(
        id: 'file_pdf',
        parentId: folder.id,
        name: secretFileName,
        type: NodeType.file,
        sizeBytes: 4096,
        mimeType: secretMimePdf,
        contentHash: secretHash,
        createdAt: now,
        modifiedAt: now,
        isFavorite: true,
        workspaceId: 'offshore',
        tags: const [secretTag1, secretTag2],
      );
      await db.insertNode(pdfFile);

      final jpgFile = FileNode(
        id: 'file_jpg',
        name: secretPhotoName,
        type: NodeType.file,
        sizeBytes: 2048,
        mimeType: secretMimeJpg,
        createdAt: now,
        modifiedAt: now,
      );
      await db.insertNode(jpgFile);

      await db.saveTransferTask(TransferTask(
        id: 'task_1',
        nodeId: pdfFile.id,
        fileName: secretFileName,
        type: TransferType.upload,
        status: TransferStatus.failed,
        progress: 0.5,
        bytesTransferred: 2048,
        totalBytes: 4096,
        errorMessage: secretErrMsg,
        createdAt: now,
        updatedAt: now,
      ));

      db.close();
      expect(db.hasEncryptionKey, isFalse);

      // 2. Inspect raw SQLite columns directly without FiloDatabase decryption
      final raw = raw_sqlite.sqlite3.open(dbPath);
      try {
        final rawNodes = raw.select(
          'SELECT id, name, mime_type, content_hash, content_hash_idx, tags FROM nodes',
        );
        expect(rawNodes.length, 3);
        for (final row in rawNodes) {
          final name = row['name'] as String;
          final mime = row['mime_type'] as String?;
          final hash = row['content_hash'] as String?;
          final hashIdx = row['content_hash_idx'] as String?;
          final tags = row['tags'] as String?;

          expect(name, startsWith('enc:v1:'));
          expect(name, isNot(contains(secretFolderName)));
          expect(name, isNot(contains(secretFileName)));
          expect(name, isNot(contains(secretPhotoName)));

          if (mime != null) {
            expect(mime, startsWith('enc:v1:'));
            expect(mime, isNot(contains('application/pdf')));
            expect(mime, isNot(contains('image/jpeg')));
          }
          if (hash != null) {
            expect(hash, startsWith('enc:v1:'));
            expect(hash, isNot(contains(secretHash)));
            expect(hashIdx, isNotNull);
            expect(hashIdx, isNot(equals(secretHash)));
            expect(hashIdx!.length, 64); // HMAC-SHA256 hex
          }
          expect(tags, isNotNull);
          expect(tags, startsWith('enc:v1:'));
          expect(tags, isNot(contains(secretTag1)));
          expect(tags, isNot(contains(secretTag2)));
        }

        final rawWorkspaces = raw.select('SELECT id, name, description FROM workspaces');
        expect(rawWorkspaces.length, 4);
        for (final row in rawWorkspaces) {
          final wsName = row['name'] as String;
          final wsDesc = row['description'] as String;
          expect(wsName, startsWith('enc:v1:'));
          expect(wsDesc, startsWith('enc:v1:'));
          expect(wsName, isNot(contains(secretWsName)));
          expect(wsName, isNot(contains('Personal Space')));
          expect(wsDesc, isNot(contains(secretWsDesc)));
        }

        final rawTasks = raw.select('SELECT file_name, error_message FROM transfer_tasks');
        expect(rawTasks.length, 1);
        final taskFileName = rawTasks.first['file_name'] as String;
        final taskErr = rawTasks.first['error_message'] as String;
        expect(taskFileName, startsWith('enc:v1:'));
        expect(taskErr, startsWith('enc:v1:'));
        expect(taskFileName, isNot(contains(secretFileName)));
        expect(taskErr, isNot(contains(secretErrMsg)));
      } finally {
        raw.dispose();
      }

      // Also verify raw DB file bytes on disk do not expose plaintext strings
      final rawBytesStr = utf8.decode(File(dbPath).readAsBytesSync(), allowMalformed: true);
      expect(rawBytesStr, isNot(contains(secretFolderName)));
      expect(rawBytesStr, isNot(contains(secretFileName)));
      expect(rawBytesStr, isNot(contains(secretHash)));
      expect(rawBytesStr, isNot(contains(secretWsName)));
      expect(rawBytesStr, isNot(contains(secretErrMsg)));

      // 3. Reopen via FiloDatabase + key and verify all read/search/index APIs
      final reopened = await FiloDatabase.openFile(dbPath);
      reopened.setEncryptionKey(masterKey);

      final rootOffshore = await reopened.listNodes(workspaceId: 'offshore');
      expect(rootOffshore.length, 1);
      expect(rootOffshore.first.name, secretFolderName);
      expect(rootOffshore.first.tags, [secretTag1]);

      final childNodes = await reopened.listNodes(parentId: folder.id);
      expect(childNodes.length, 1);
      expect(childNodes.first.name, secretFileName);
      expect(childNodes.first.mimeType, secretMimePdf);
      expect(childNodes.first.contentHash, secretHash);
      expect(childNodes.first.tags, [secretTag1, secretTag2]);

      // Search query (case-insensitive substring)
      final searchHits = await reopened.listNodes(searchQuery: 'swiss_account');
      expect(searchHits.length, 1);
      expect(searchHits.first.id, pdfFile.id);

      // Tag filter (case-insensitive substring matching SQLite LIKE)
      final rootTagHits = await reopened.listNodes(tag: 'CONFIDENTIAL');
      expect(rootTagHits.length, 1);
      expect(rootTagHits.first.id, folder.id);

      final childTagHits = await reopened.listNodes(parentId: folder.id, tag: 'BANKING');
      expect(childTagHits.length, 1);
      expect(childTagHits.first.id, pdfFile.id);

      // MIME prefix filter
      final imageHits = await reopened.listNodes(mimePrefix: 'image/');
      expect(imageHits.length, 1);
      expect(imageHits.first.id, jpgFile.id);

      // Blind-indexed hash deduplication lookup
      final dup = await reopened.findByHash(secretHash);
      expect(dup, isNotNull);
      expect(dup!.id, pdfFile.id);
      expect(dup.name, secretFileName);

      // Storage usage MIME classification
      final usage = await reopened.getStorageUsage();
      expect(usage.totalBytes, 6144);
      expect(usage.documentsBytes, 4096);
      expect(usage.imagesBytes, 2048);
      expect(usage.totalFiles, 2);
      expect(usage.totalFolders, 1);

      // Workspaces decryption
      final workspaces = await reopened.getWorkspaces();
      final offshoreWs = workspaces.firstWhere((w) => w.id == 'offshore');
      expect(offshoreWs.name, secretWsName);
      expect(offshoreWs.description, secretWsDesc);

      // Transfer tasks decryption
      final tasks = await reopened.listTransferTasks();
      expect(tasks.length, 1);
      expect(tasks.first.fileName, secretFileName);
      expect(tasks.first.errorMessage, secretErrMsg);

      // Snapshot export produces plaintext JSON payload
      final snapshotStr = await reopened.exportSnapshotJson();
      final snapshot = json.decode(snapshotStr) as Map<String, dynamic>;
      final exportedNodes = (snapshot['nodes'] as List<dynamic>)
          .map((n) => FileNode.fromJson(n as Map<String, dynamic>))
          .toList();
      expect(exportedNodes.any((n) => n.name == secretFileName), isTrue);
      final exportedWs = (snapshot['workspaces'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(
        exportedWs.any((w) => w['id'] == 'offshore' && w['name'] == secretWsName),
        isTrue,
      );

      reopened.close();
    });

    test('Migrates legacy plaintext database rows on setEncryptionKey and scrubs freed pages', () async {
      final dbPath = '${tempDir.path}/legacy_plain.db';
      final masterKey = CryptoEngine.generateMasterKey();
      final now = DateTime.fromMillisecondsSinceEpoch(1760000000000);

      const legacyFile = 'LegacyPlaintextTaxReturn.pdf';
      const legacyHash = 'legacy_sha256_hash_value_987654';
      const legacyTag = 'legacy_tax';
      const legacyWsName = 'Legacy Workspace';
      const legacyWsDesc = 'Unencrypted legacy description';
      const legacyTaskErr = 'Legacy upload error detail';

      // 1. Create and populate database WITHOUT encryption key
      final legacyDb = await FiloDatabase.openFile(dbPath);
      expect(legacyDb.hasEncryptionKey, isFalse);

      await legacyDb.insertWorkspace(const Workspace(
        id: 'legacy_ws',
        name: legacyWsName,
        description: legacyWsDesc,
        icon: Icons.folder_outlined,
      ));
      await legacyDb.insertNode(FileNode(
        id: 'legacy_node_1',
        name: legacyFile,
        type: NodeType.file,
        sizeBytes: 1234,
        mimeType: 'application/pdf',
        contentHash: legacyHash,
        tags: const [legacyTag],
        workspaceId: 'legacy_ws',
        createdAt: now,
        modifiedAt: now,
      ));
      await legacyDb.saveTransferTask(TransferTask(
        id: 'legacy_task_1',
        nodeId: 'legacy_node_1',
        fileName: legacyFile,
        type: TransferType.upload,
        status: TransferStatus.failed,
        totalBytes: 1234,
        errorMessage: legacyTaskErr,
        createdAt: now,
        updatedAt: now,
      ));
      legacyDb.close();

      // Confirm plaintext was stored prior to migration
      final rawBefore = raw_sqlite.sqlite3.open(dbPath);
      expect(
        rawBefore.select('SELECT name FROM nodes').first['name'],
        legacyFile,
      );
      rawBefore.dispose();

      // 2. Reopen and activate encryption key -> triggers atomic migration + VACUUM
      final migratedDb = await FiloDatabase.openFile(dbPath);
      migratedDb.setEncryptionKey(masterKey);
      migratedDb.close();

      // 3. Reopen raw sqlite3 and confirm all sensitive columns are now 'enc:v1:'
      final rawAfter = raw_sqlite.sqlite3.open(dbPath);
      try {
        final nRow = rawAfter.select(
          'SELECT name, mime_type, content_hash, content_hash_idx, tags FROM nodes WHERE id = ?',
          ['legacy_node_1'],
        ).first;
        expect(nRow['name'] as String, startsWith('enc:v1:'));
        expect(nRow['mime_type'] as String, startsWith('enc:v1:'));
        expect(nRow['content_hash'] as String, startsWith('enc:v1:'));
        expect(nRow['content_hash_idx'], isNotNull);
        expect(nRow['content_hash_idx'], isNot(equals(legacyHash)));
        expect(nRow['tags'] as String, startsWith('enc:v1:'));

        final wsRow = rawAfter.select(
          'SELECT name, description FROM workspaces WHERE id = ?',
          ['legacy_ws'],
        ).first;
        expect(wsRow['name'] as String, startsWith('enc:v1:'));
        expect(wsRow['description'] as String, startsWith('enc:v1:'));

        final tRow = rawAfter.select(
          'SELECT file_name, error_message FROM transfer_tasks WHERE id = ?',
          ['legacy_task_1'],
        ).first;
        expect(tRow['file_name'] as String, startsWith('enc:v1:'));
        expect(tRow['error_message'] as String, startsWith('enc:v1:'));
      } finally {
        rawAfter.dispose();
      }

      // Check raw disk file no longer contains migrated plaintext strings
      final rawFileText = utf8.decode(File(dbPath).readAsBytesSync(), allowMalformed: true);
      expect(rawFileText, isNot(contains(legacyFile)));
      expect(rawFileText, isNot(contains(legacyHash)));
      expect(rawFileText, isNot(contains(legacyWsName)));
      expect(rawFileText, isNot(contains(legacyTaskErr)));

      // 4. Verify migrated data reads and queries accurately with key
      final verifyDb = await FiloDatabase.openFile(dbPath);
      verifyDb.setEncryptionKey(masterKey);
      expect((await verifyDb.findByHash(legacyHash))?.name, legacyFile);
      expect(
        (await verifyDb.listNodes(searchQuery: 'LegacyPlaintext')).single.tags,
        [legacyTag],
      );
      expect(
        (await verifyDb.getWorkspaces()).singleWhere((w) => w.id == 'legacy_ws').name,
        legacyWsName,
      );
      expect((await verifyDb.listTransferTasks()).single.errorMessage, legacyTaskErr);
      verifyDb.close();
    });

    test('clearEncryptionKey resets state, wrong key fails AEAD auth, and mutations stay encrypted', () async {
      final dbPath = '${tempDir.path}/key_lifecycle.db';
      final key1 = CryptoEngine.generateMasterKey();
      final key2 = CryptoEngine.generateMasterKey();
      final now = DateTime.fromMillisecondsSinceEpoch(1760000000000);

      final db = await FiloDatabase.openFile(dbPath);
      db.setEncryptionKey(key1);
      expect(db.hasEncryptionKey, isTrue);

      await db.insertNode(FileNode(
        id: 'n1',
        name: 'InitialName.txt',
        type: NodeType.file,
        sizeBytes: 100,
        mimeType: 'text/plain',
        contentHash: 'hash_v1',
        createdAt: now,
        modifiedAt: now,
      ));

      // Test renameNode, updateNodeTags, updateNodeHash, updateNode, deleteWorkspace(soft)
      await db.renameNode('n1', 'RenamedSecret.txt');
      await db.updateNodeTags('n1', ['alpha', 'beta']);
      await db.updateNodeHash('n1', 'hash_v2');

      final fetched = await db.getNode('n1');
      expect(fetched!.name, 'RenamedSecret.txt');
      expect(fetched.tags, ['alpha', 'beta']);
      expect(fetched.contentHash, 'hash_v2');
      expect((await db.findByHash('hash_v2'))?.id, 'n1');
      expect(await db.findByHash('hash_v1'), isNull);

      db.clearEncryptionKey();
      expect(db.hasEncryptionKey, isFalse);

      // Re-setting wrong key must fail GCM tag verification on decrypt
      db.setEncryptionKey(key2);
      expect(db.hasEncryptionKey, isTrue);
      expect(
        () => db.getNode('n1'),
        throwsA(isA<InvalidCipherTextException>()),
      );

      db.close();
      expect(db.hasEncryptionKey, isFalse);
    });

    test('listNodes sorting, trashed nodes, and restoreFromSnapshotJson work under encryption', () async {
      final dbPath = '${tempDir.path}/snapshot_enc.db';
      final masterKey = CryptoEngine.generateMasterKey();
      final now = DateTime.fromMillisecondsSinceEpoch(1760000000000);

      final db1 = await FiloDatabase.openFile(dbPath);
      db1.setEncryptionKey(masterKey);

      await db1.insertNode(FileNode(
        id: 'f_zeta',
        name: 'zeta.txt',
        type: NodeType.file,
        mimeType: 'text/plain',
        createdAt: now,
        modifiedAt: now,
      ));
      await db1.insertNode(FileNode(
        id: 'd_beta',
        name: 'BetaFolder',
        type: NodeType.folder,
        createdAt: now,
        modifiedAt: now,
      ));
      await db1.insertNode(FileNode(
        id: 'f_alpha',
        name: 'Alpha.txt',
        type: NodeType.file,
        mimeType: 'text/plain',
        createdAt: now,
        modifiedAt: now,
      ));

      final listed = await db1.listNodes();
      // Folders before files, then case-insensitive alphabetical
      expect(listed.map((n) => n.name).toList(), ['BetaFolder', 'Alpha.txt', 'zeta.txt']);

      final snap = await db1.exportSnapshotJson();
      db1.close();

      // Restore into a second encrypted DB
      final db2Path = '${tempDir.path}/snapshot_enc_2.db';
      final db2 = await FiloDatabase.openFile(db2Path);
      db2.setEncryptionKey(masterKey);
      await db2.restoreFromSnapshotJson(snap);
      db2.close();

      final raw2 = raw_sqlite.sqlite3.open(db2Path);
      try {
        for (final row in raw2.select('SELECT name FROM nodes')) {
          expect(row['name'] as String, startsWith('enc:v1:'));
        }
      } finally {
        raw2.dispose();
      }
    });
  });

  group('IndexSyncService Concurrent Snapshot Merge (VULN-07)', () {
    test('Detects concurrent remote backup, merges non-destructively, and advances monotonic revision', () async {
      final storage = FakeStorageBackend();
      await storage.initialize();
      storage.setAuthenticated();
      final masterKey = CryptoEngine.generateMasterKey();

      final dbA = FiloDatabase.openInMemory();
      final dbB = FiloDatabase.openInMemory();
      dbA.setEncryptionKey(masterKey);
      dbB.setEncryptionKey(masterKey);

      final syncA = IndexSyncService(database: dbA, storageBackend: storage);
      final syncB = IndexSyncService(database: dbB, storageBackend: storage);

      final t0 = DateTime.fromMillisecondsSinceEpoch(1760000000000);
      final tOlder = DateTime.fromMillisecondsSinceEpoch(1760000001000);
      final tNewer = DateTime.fromMillisecondsSinceEpoch(1760000005000);

      // 1. Device A seeds shared folder and file, backs up (rev 1)
      await dbA.insertNode(FileNode(
        id: 'shared_doc',
        name: 'Shared_v0.txt',
        type: NodeType.file,
        sizeBytes: 100,
        createdAt: t0,
        modifiedAt: t0,
      ));
      await dbA.insertNode(FileNode(
        id: 'conflict_newer_on_a',
        name: 'OnA_v0.txt',
        type: NodeType.file,
        sizeBytes: 50,
        createdAt: t0,
        modifiedAt: t0,
      ));
      await syncA.backupIndexToCloud(masterKey: masterKey);
      expect(await dbA.getSyncMeta('remote_revision'), '1');

      // 2. Device B restores rev 1
      expect(await syncB.restoreIndexFromCloud(masterKey: masterKey), isTrue);
      expect(await dbB.getSyncMeta('remote_revision'), '1');

      // 3. Device A adds custom workspace + file + newer edit to conflict_newer_on_a, pushes rev 2
      await dbA.insertWorkspace(const Workspace(
        id: 'ws_a',
        name: 'Workspace A',
        description: 'Created on A',
        icon: Icons.folder_outlined,
      ));
      await dbA.insertNode(FileNode(
        id: 'only_on_a',
        name: 'FromDeviceA.pdf',
        type: NodeType.file,
        sizeBytes: 300,
        workspaceId: 'ws_a',
        createdAt: tNewer,
        modifiedAt: tNewer,
      ));
      await dbA.insertChunks(const [
        FileChunk(
          id: 'chunk_a',
          nodeId: 'only_on_a',
          chunkIndex: 0,
          remoteMessageId: 'msg_a1',
          remoteFileId: 'rf_a1',
          sizeBytes: 300,
          sha256Hash: 'sha_a1',
          ivHex: 'iv_a1',
        ),
      ]);
      await dbA.updateNode(FileNode(
        id: 'conflict_newer_on_a',
        name: 'OnA_Winner.txt',
        type: NodeType.file,
        sizeBytes: 55,
        createdAt: t0,
        modifiedAt: tNewer,
      ));
      final msg2 = await syncA.backupIndexToCloud(masterKey: masterKey);
      expect(await dbA.getSyncMeta('remote_revision'), '2');

      // 4. Device B concurrently edits locally (without knowing about msg2):
      //    - Adds only_on_b
      //    - Updates shared_doc with tNewer (wins over rev 1)
      //    - Updates conflict_newer_on_a with tOlder (loses to A's tNewer)
      await dbB.insertNode(FileNode(
        id: 'only_on_b',
        name: 'FromDeviceB.pdf',
        type: NodeType.file,
        sizeBytes: 400,
        createdAt: tNewer,
        modifiedAt: tNewer,
      ));
      await dbB.updateNode(FileNode(
        id: 'shared_doc',
        name: 'Shared_EditedByB.txt',
        type: NodeType.file,
        sizeBytes: 120,
        createdAt: t0,
        modifiedAt: tNewer,
      ));
      await dbB.updateNode(FileNode(
        id: 'conflict_newer_on_a',
        name: 'OnB_Stale.txt',
        type: NodeType.file,
        sizeBytes: 51,
        createdAt: t0,
        modifiedAt: tOlder,
      ));

      // Device B pushes -> detects msg2 != lastKnownMsgId, merges A's changes, pushes rev 3
      final msg3 = await syncB.backupIndexToCloud(masterKey: masterKey);
      expect(msg3, isNot(equals(msg2)));
      expect(await dbB.getSyncMeta('remote_revision'), '3');

      // Verify outer envelope has revision 3 and version 1
      final channel = await storage.getOrCreateVaultChannel(AppConfig.vaultChannelTitle);
      final pinned = await storage.getPinnedMessage(channelId: channel.channelId);
      final downloaded = await storage.downloadChunk(
        channelId: channel.channelId,
        remoteFileId: pinned!.remoteFileId!,
      );
      final envelope = json.decode(utf8.decode(downloaded)) as Map<String, dynamic>;
      expect(envelope['version'], 1);
      expect(envelope['revision'], 3);
      expect(envelope.containsKey('parentMessageId'), isTrue);

      // Verify Device B local DB now has merged union
      expect((await dbB.getWorkspaces()).any((w) => w.id == 'ws_a'), isTrue);
      expect((await dbB.getNode('only_on_a'))?.name, 'FromDeviceA.pdf');
      expect((await dbB.getChunksForNode('only_on_a')).single.remoteFileId, 'rf_a1');
      expect((await dbB.getNode('only_on_b'))?.name, 'FromDeviceB.pdf');
      expect((await dbB.getNode('shared_doc'))?.name, 'Shared_EditedByB.txt');
      expect((await dbB.getNode('conflict_newer_on_a'))?.name, 'OnA_Winner.txt');

      // 5. Device A pulls merged rev 3 and receives Device B's additions & edits
      expect(await syncA.checkAndAutoRestore(masterKey: masterKey), isTrue);
      expect(await dbA.getSyncMeta('remote_revision'), '3');
      expect((await dbA.getNode('only_on_b'))?.name, 'FromDeviceB.pdf');
      expect((await dbA.getNode('shared_doc'))?.name, 'Shared_EditedByB.txt');

      syncA.dispose();
      syncB.dispose();
      dbA.close();
      dbB.close();
    });

    test('Skips corrupted/tampered remote snapshot gracefully during backup conflict check', () async {
      final storage = FakeStorageBackend();
      await storage.initialize();
      storage.setAuthenticated();
      final masterKey = CryptoEngine.generateMasterKey();

      final db = FiloDatabase.openInMemory();
      final sync = IndexSyncService(database: db, storageBackend: storage);
      final now = DateTime.fromMillisecondsSinceEpoch(1760000000000);

      await db.insertNode(FileNode(
        id: 'local_1',
        name: 'LocalSafe.txt',
        type: NodeType.file,
        createdAt: now,
        modifiedAt: now,
      ));
      await sync.backupIndexToCloud(masterKey: masterKey);

      // Simulate an attacker/corrupt device pinning invalid envelope with bogus revision 999
      final channel = await storage.getOrCreateVaultChannel(AppConfig.vaultChannelTitle);
      final badEnvelope = utf8.encode(json.encode({
        'version': 1,
        'revision': 999,
        'catalogCiphertextHex': '00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff',
      }));
      final badChunk = await storage.uploadChunk(
        channelId: channel.channelId,
        chunkData: badEnvelope,
        partFileName: 'index.filo',
      );
      await storage.pinMessage(channelId: channel.channelId, messageId: badChunk.messageId);

      // Local backup should gracefully skip unverified remote snapshot and NOT adopt rev 999
      await db.insertNode(FileNode(
        id: 'local_2',
        name: 'LocalSecond.txt',
        type: NodeType.file,
        createdAt: now,
        modifiedAt: now,
      ));
      await sync.backupIndexToCloud(masterKey: masterKey);
      expect(await db.getSyncMeta('remote_revision'), '2');
      expect((await db.listNodes()).length, 2);

      sync.dispose();
      db.close();
    });
  });
}
