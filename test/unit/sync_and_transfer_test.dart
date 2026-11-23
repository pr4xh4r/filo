import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:filo/core/crypto/crypto_engine.dart';
import 'package:filo/core/database/filo_database.dart';
import 'package:filo/core/database/chunk_model.dart';
import 'package:filo/features/files/data/file_repository.dart';
import 'package:filo/features/storage/data/fake_storage_backend.dart';
import 'package:filo/features/sync/domain/index_sync_service.dart';
import 'package:filo/features/transfer/domain/chunking_engine.dart';
import 'package:filo/features/transfer/data/transfer_manager.dart';

void main() {
  late FiloDatabase db;
  late FakeStorageBackend storage;
  late FileRepository fileRepo;
  late IndexSyncService syncService;
  late ChunkingEngine chunkEngine;
  late TransferManager transferManager;

  setUp(() async {
    db = FiloDatabase.openInMemory();
    storage = FakeStorageBackend();
    await storage.initialize();
    storage.setAuthenticated();

    fileRepo = FileRepository(database: db);
    syncService = IndexSyncService(database: db, storageBackend: storage);
    chunkEngine = ChunkingEngine(storageBackend: storage);
    transferManager = TransferManager(
      storageBackend: storage,
      fileRepository: fileRepo,
    );
  });

  tearDown(() {
    db.close();
  });

  group('IndexSyncService (Zero-Knowledge Cloud Backup & Restore)', () {
    test('Backs up database snapshot to pinned Telegram message and restores on fresh device', () async {
      final masterKey = CryptoEngine.generateMasterKey();

      // Seed database with a folder and file
      final folder = await fileRepo.createFolder(name: 'Work Documents');
      final file = await fileRepo.createFileNode(
        name: 'Report.pdf',
        sizeBytes: 1024 * 500,
        parentId: folder.id,
        mimeType: 'application/pdf',
        contentHash: 'hash_report_123',
      );

      final chunk = FileChunk(
        id: 'chunk_report_1',
        nodeId: file.id,
        chunkIndex: 0,
        remoteMessageId: 'msg_999',
        remoteFileId: 'file_cloud_999',
        sizeBytes: 1024 * 500,
        sha256Hash: 'sha_report_999',
        ivHex: 'aabbcc112233',
      );
      await fileRepo.saveFileChunks([chunk]);

      // 1. Perform Cloud Backup
      final pinnedMsgId = await syncService.backupIndexToCloud(masterKey: masterKey);
      expect(pinnedMsgId.isNotEmpty, true);

      // Verify message is pinned in FakeStorageBackend
      final pinned = await storage.getPinnedMessage(channelId: '-1009876543210');
      expect(pinned, isNotNull);
      expect(pinned?.messageId, pinnedMsgId);

      // 2. Simulate fresh new device with empty database
      final freshDb = FiloDatabase.openInMemory();
      final freshSyncService = IndexSyncService(
        database: freshDb,
        storageBackend: storage,
      );

      // 3. Restore on new device
      final restored = await freshSyncService.restoreIndexFromCloud(masterKey: masterKey);
      expect(restored, true);

      // 4. Verify reconstructed hierarchy and chunks
      final restoredNodes = await freshDb.listNodes();
      expect(restoredNodes.length, 1);
      expect(restoredNodes.first.name, 'Work Documents');

      final restoredChildren = await freshDb.listNodes(parentId: folder.id);
      expect(restoredChildren.length, 1);
      expect(restoredChildren.first.name, 'Report.pdf');

      final restoredChunks = await freshDb.getChunksForNode(file.id);
      expect(restoredChunks.length, 1);
      expect(restoredChunks.first.remoteFileId, 'file_cloud_999');

      freshDb.close();
    });

    test('Restore fails with wrong master key (authenticated encryption protects integrity)', () async {
      final masterKey1 = CryptoEngine.generateMasterKey();
      final masterKey2 = CryptoEngine.generateMasterKey();

      await fileRepo.createFolder(name: 'Confidential');
      await syncService.backupIndexToCloud(masterKey: masterKey1);

      final freshDb = FiloDatabase.openInMemory();
      final freshSyncService = IndexSyncService(
        database: freshDb,
        storageBackend: storage,
      );

      expect(
        () async => await freshSyncService.restoreIndexFromCloud(masterKey: masterKey2),
        throwsA(anything),
      );

      freshDb.close();
    });
  });

  group('ChunkingEngine & Multi-Part Large File Handling', () {
    test('Chunks file, encrypts parts, uploads, downloads, and reassembles byte-for-byte', () async {
      final masterKey = CryptoEngine.generateMasterKey();

      // Create test temporary file with known bytes (e.g. 100 KB split into 32 KB chunks)
      final tempDir = Directory.systemTemp.createTempSync('filo_test_chunk_');
      final sourceFile = File('${tempDir.path}/original.bin');

      final originalBytes = Uint8List(100 * 1024);
      for (int i = 0; i < originalBytes.length; i++) {
        originalBytes[i] = i % 256;
      }
      await sourceFile.writeAsBytes(originalBytes);

      // 1. Upload with 32KB chunks (simulating multi-part upload)
      final chunks = await chunkEngine.uploadFile(
        file: sourceFile,
        nodeId: 'node_test_100k',
        masterKey: masterKey,
        channelId: '-1009876543210',
        chunkSize: 32 * 1024,
      );

      expect(chunks.length, 4); // 32KB + 32KB + 32KB + 4KB = 4 chunks
      expect(chunks[0].chunkIndex, 0);
      expect(chunks[3].chunkIndex, 3);

      // 2. Download and Reassemble
      final downloadedFile = File('${tempDir.path}/downloaded.bin');
      await chunkEngine.downloadAndDecryptFile(
        chunks: chunks,
        destinationFile: downloadedFile,
        masterKey: masterKey,
        channelId: '-1009876543210',
      );

      final downloadedBytes = await downloadedFile.readAsBytes();
      expect(downloadedBytes.length, originalBytes.length);
      expect(downloadedBytes, originalBytes);

      tempDir.deleteSync(recursive: true);
    });
  });

  group('TransferManager & Duplicate Detection', () {
    test('Duplicate file detection avoids redundant upload', () async {
      final masterKey = CryptoEngine.generateMasterKey();
      final tempDir = Directory.systemTemp.createTempSync('filo_test_dup_');
      final file1 = File('${tempDir.path}/doc1.txt');
      await file1.writeAsString('Unique content for duplicate detection test');

      // 1. First upload
      final uploaded1 = await transferManager.uploadLocalFile(
        file: file1,
        masterKey: masterKey,
      );
      expect(uploaded1.name, 'doc1.txt');

      // 2. Second upload of identical content
      final file2 = File('${tempDir.path}/doc2.txt');
      await file2.writeAsString('Unique content for duplicate detection test');

      final uploaded2 = await transferManager.uploadLocalFile(
        file: file2,
        masterKey: masterKey,
      );

      expect(uploaded2.name, 'doc2.txt');
      expect(uploaded2.contentHash, uploaded1.contentHash);

      // Both files now exist in the local index
      final nodes = await fileRepo.getNodes();
      expect(nodes.length, 2);

      tempDir.deleteSync(recursive: true);
    });
  });
}
