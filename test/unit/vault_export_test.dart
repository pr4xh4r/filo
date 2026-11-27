import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:filo/core/config/app_config.dart';
import 'package:filo/core/crypto/crypto_engine.dart';
import 'package:filo/core/database/chunk_model.dart';
import 'package:filo/core/database/filo_database.dart';
import 'package:filo/core/database/transfer_model.dart';
import 'package:filo/features/files/data/file_repository.dart';
import 'package:filo/features/files/domain/workspace.dart';
import 'package:filo/features/storage/data/fake_storage_backend.dart';
import 'package:filo/features/transfer/data/transfer_manager.dart';
import 'package:filo/features/transfer/domain/chunking_engine.dart';
import 'package:filo/features/transfer/domain/streaming_zip_writer.dart';
import 'package:filo/features/transfer/domain/vault_export_service.dart';

class _TestExportPlatformBridge extends ExportPlatformBridge {
  final Directory workDir;
  final Directory outputDir;

  _TestExportPlatformBridge({
    required this.workDir,
    required this.outputDir,
  });

  @override
  Future<Directory> getExportWorkingDirectory() async {
    if (!await workDir.exists()) {
      await workDir.create(recursive: true);
    }
    return workDir;
  }

  @override
  Future<int?> getAvailableStorageBytes(String path) async =>
      50 * 1024 * 1024 * 1024; // 50 GB

  @override
  Future<({String displayPath, String? localShareablePath})> deliverArchive({
    required File finalizedPartFile,
    required String finalFileName,
    String? customDestinationDir,
  }) async {
    final targetBase =
        customDestinationDir != null && customDestinationDir.isNotEmpty
            ? Directory(customDestinationDir)
            : outputDir;
    if (!await targetBase.exists()) {
      await targetBase.create(recursive: true);
    }
    final target = File(p.join(targetBase.path, finalFileName));
    final moved = await finalizedPartFile.rename(target.path);
    return (displayPath: moved.path, localShareablePath: moved.path);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('filo_export_suite_');
  });

  tearDown(() {
    try {
      if (tempRoot.existsSync()) {
        tempRoot.deleteSync(recursive: true);
      }
    } catch (_) {
      // Best-effort cleanup
    }
  });

  group('StreamingZipWriter', () {
    test('Streams multiple files, empty files, and UTF-8 names to a valid ZIP',
        () async {
      final srcA = File(p.join(tempRoot.path, 'a.bin'));
      final payloadA = Uint8List.fromList(
        List<int>.generate(150 * 1024, (i) => (i * 7 + 3) % 256),
      );
      await srcA.writeAsBytes(payloadA);

      final srcB = File(p.join(tempRoot.path, 'notes.txt'));
      final payloadB = utf8.encode('Hello Filo — UTF-8 🚀 multi-GB streaming');
      await srcB.writeAsBytes(payloadB);

      final zipPartPath = p.join(tempRoot.path, 'out.zip.part');
      final e1 = await StreamingZipWriter.appendFile(
        archivePartPath: zipPartPath,
        offset: 0,
        nodeId: 'n1',
        entryName: 'Personal Space/Sub/file_a.bin',
        sourceFilePath: srcA.path,
        modifiedAt: DateTime(2026, 5, 10, 14, 30, 10),
        bufferSize: 32 * 1024,
      );
      final e2 = await StreamingZipWriter.appendFile(
        archivePartPath: zipPartPath,
        offset: e1.endOffset,
        nodeId: 'n2',
        entryName: 'Personal Space/empty.txt',
        sourceFilePath: null,
        modifiedAt: DateTime(2026, 5, 10, 14, 31, 0),
      );
      final e3 = await StreamingZipWriter.appendFile(
        archivePartPath: zipPartPath,
        offset: e2.endOffset,
        nodeId: 'n3',
        entryName: 'Work Space/café_notes.txt',
        sourceFilePath: srcB.path,
        modifiedAt: DateTime(2026, 5, 10, 14, 32, 0),
        bufferSize: 16 * 1024,
      );

      await StreamingZipWriter.finalize(
        archivePartPath: zipPartPath,
        entries: [e1, e2, e3],
        centralDirectoryOffset: e3.endOffset,
        comment: 'Filo Archive Test',
      );

      final decoder = ZipDecoder();
      final decoded = decoder.decodeBytes(await File(zipPartPath).readAsBytes());
      expect(decoded.length, 3);
      expect(decoded.findFile('Personal Space/Sub/file_a.bin')?.content, payloadA);
      expect(decoded.findFile('Personal Space/empty.txt')?.content, isEmpty);
      expect(decoded.findFile('Work Space/café_notes.txt')?.content, payloadB);
      expect(decoder.directory.zipFileComment, 'Filo Archive Test');
    });

    test('Truncates partial garbage bytes and resumes cleanly after interruption',
        () async {
      final src1 = File(p.join(tempRoot.path, 'part1.dat'));
      final data1 = utf8.encode('First completed file content');
      await src1.writeAsBytes(data1);

      final src2 = File(p.join(tempRoot.path, 'part2.dat'));
      final data2 = utf8.encode('Second file written after resume');
      await src2.writeAsBytes(data2);

      final zipPartPath = p.join(tempRoot.path, 'resumed.zip.part');
      final e1 = await StreamingZipWriter.appendFile(
        archivePartPath: zipPartPath,
        offset: 0,
        nodeId: 'n1',
        entryName: 'first.dat',
        sourceFilePath: src1.path,
        modifiedAt: DateTime(2026, 1, 1),
      );

      // Simulate sudden power loss mid-write of a second entry (trailing junk)
      final corruptRaf = await File(zipPartPath).open(mode: FileMode.append);
      await corruptRaf.writeFrom(List<int>.filled(4096, 0xAA));
      await corruptRaf.close();
      expect(File(zipPartPath).lengthSync(), e1.endOffset + 4096);

      // Resume directly from e1.endOffset
      final e2 = await StreamingZipWriter.appendFile(
        archivePartPath: zipPartPath,
        offset: e1.endOffset,
        nodeId: 'n2',
        entryName: 'second.dat',
        sourceFilePath: src2.path,
        modifiedAt: DateTime(2026, 1, 2),
      );

      await StreamingZipWriter.finalize(
        archivePartPath: zipPartPath,
        entries: [e1, e2],
        centralDirectoryOffset: e2.endOffset,
      );

      final decoded = ZipDecoder().decodeBytes(await File(zipPartPath).readAsBytes());
      expect(decoded.length, 2);
      expect(decoded.findFile('first.dat')?.content, data1);
      expect(decoded.findFile('second.dat')?.content, data2);
    });

    test('Emits PKWARE-compliant Zip64 extra fields only for fields >= limit',
        () async {
      // Case: small file sitting past the 4GB threshold (only offset >= limit)
      final smallFile = File(p.join(tempRoot.path, 'small.txt'));
      final content = utf8.encode('offset-only-zip64');
      await smallFile.writeAsBytes(content);

      final zipPath = p.join(tempRoot.path, 'zip64_offset.zip');
      final e1 = await StreamingZipWriter.appendFile(
        archivePartPath: zipPath,
        offset: 0,
        nodeId: 'n1',
        entryName: 'small.txt',
        sourceFilePath: smallFile.path,
        modifiedAt: DateTime(2026, 6, 1),
        sizeLimitForZip64: 100,
      );

      // Force second entry offset >= 100 while its size (17) < 100
      final e2 = await StreamingZipWriter.appendFile(
        archivePartPath: zipPath,
        offset: e1.endOffset,
        nodeId: 'n2',
        entryName: 'second.txt',
        sourceFilePath: smallFile.path,
        modifiedAt: DateTime(2026, 6, 1),
        sizeLimitForZip64: 100,
      );
      expect(e2.localHeaderOffset, greaterThan(40));
      expect(e2.uncompressedSize, content.length);

      // Simulate offset-only Zip64 entry with limit 40: size (17) < 40, offset > 40
      await StreamingZipWriter.finalize(
        archivePartPath: zipPath,
        entries: [e1, e2],
        centralDirectoryOffset: e2.endOffset,
        sizeLimitForZip64: 40,
      );

      final bytes = await File(zipPath).readAsBytes();
      final bd = ByteData.sublistView(bytes);

      // Verify EOCD at end has 0xFFFFFFFF sentinels for CD size/offset
      final eocdPos = bytes.length - 22;
      expect(bd.getUint32(eocdPos, Endian.little), 0x06054b50);
      expect(bd.getUint32(eocdPos + 16, Endian.little), 0xFFFFFFFF);

      // Verify Zip64 EOCD Locator immediately precedes EOCD
      final locatorPos = eocdPos - 20;
      expect(bd.getUint32(locatorPos, Endian.little), 0x07064b50);

      // Verify Zip64 EOCD immediately precedes Locator
      final z64EocdPos = locatorPos - 56;
      expect(bd.getUint32(z64EocdPos, Endian.little), 0x06064b50);
      expect(bd.getUint64(z64EocdPos + 48, Endian.little), e2.endOffset);

      // Verify entry #2 Central Directory Header extra field contains ONLY 8-byte offset
      final cd1ExtraLen = bd.getUint16(e2.endOffset + 30, Endian.little);
      final cd1NameLen = bd.getUint16(e2.endOffset + 28, Endian.little);
      expect(cd1ExtraLen, 0); // e1 offset=0 < 40, size=17 < 40
      final cd2Pos = e2.endOffset + 46 + cd1NameLen;
      expect(bd.getUint32(cd2Pos, Endian.little), 0x02014b50);
      expect(bd.getUint32(cd2Pos + 20, Endian.little), content.length);
      expect(bd.getUint32(cd2Pos + 24, Endian.little), content.length);
      expect(bd.getUint32(cd2Pos + 42, Endian.little), 0xFFFFFFFF);
      expect(bd.getUint16(cd2Pos + 30, Endian.little), 12); // 4B header + 8B offset only!
      final cd2NameLen = bd.getUint16(cd2Pos + 28, Endian.little);
      final extraPos = cd2Pos + 46 + cd2NameLen;
      expect(bd.getUint16(extraPos, Endian.little), 0x0001);
      expect(bd.getUint16(extraPos + 2, Endian.little), 8);
      expect(bd.getUint64(extraPos + 4, Endian.little), e2.localHeaderOffset);
    });
  });

  group('VaultExportService (Multi-GB Streaming, Resilience & Resume)', () {
    late FiloDatabase db;
    late FakeStorageBackend storage;
    late FileRepository fileRepo;
    late ChunkingEngine chunkEngine;
    late TransferManager transferManager;
    late _TestExportPlatformBridge bridge;
    late VaultExportService exportService;

    setUp(() async {
      db = FiloDatabase.openInMemory();
      storage = FakeStorageBackend();
      await storage.initialize();
      storage.setAuthenticated();
      fileRepo = FileRepository(database: db);
      chunkEngine = ChunkingEngine(storageBackend: storage);
      transferManager = TransferManager(
        storageBackend: storage,
        fileRepository: fileRepo,
      );
      bridge = _TestExportPlatformBridge(
        workDir: Directory(p.join(tempRoot.path, 'work')),
        outputDir: Directory(p.join(tempRoot.path, 'exports')),
      );
      exportService = VaultExportService(
        fileRepository: fileRepo,
        storageBackend: storage,
        transferManager: transferManager,
        chunkingEngine: chunkEngine,
        platformBridge: bridge,
        maxChunkRetries: 2,
      );
    });

    tearDown(() {
      transferManager.dispose();
      db.close();
    });

    test('Exports multi-workspace files with path disambiguation and key isolation',
        () async {
      final masterKey = CryptoEngine.generateMasterKey();
      final dbKey = Uint8List.fromList(masterKey);
      db.setEncryptionKey(dbKey);

      // Seed custom viewable workspace
      const viewWs = Workspace(
        id: 'media',
        name: 'Media Gallery',
        description: 'Viewable',
        icon: Icons.folder_outlined,
        isEncrypted: false,
      );
      await fileRepo.createWorkspace(viewWs);

      final encChannel = await storage
          .getOrCreateVaultChannel(AppConfig.getChannelTitle(isEncrypted: true));
      final viewChannel = await storage.getOrCreateVaultChannel(
        AppConfig.getChannelTitle(isEncrypted: false),
      );

      // 1. Personal Space -> Docs/report.txt (encrypted multi-chunk)
      final docsPersonal =
          await fileRepo.createFolder(name: 'Docs', workspaceId: 'personal');
      final f1Src = File(p.join(tempRoot.path, 'f1.txt'));
      final f1Data = Uint8List.fromList(
        List<int>.generate(90 * 1024, (i) => (i + 11) % 256),
      );
      await f1Src.writeAsBytes(f1Data);
      final n1 = await fileRepo.createFileNode(
        name: 'report.txt',
        sizeBytes: f1Data.length,
        parentId: docsPersonal.id,
        workspaceId: 'personal',
      );
      final n1Chunks = await chunkEngine.uploadFile(
        file: f1Src,
        nodeId: n1.id,
        masterKey: masterKey,
        channelId: encChannel.channelId,
        chunkSize: 32 * 1024,
        isEncrypted: true,
      );
      await fileRepo.saveFileChunks(n1Chunks);

      // 2. Work Space -> Docs/report.txt (same path name across workspace!)
      final docsWork =
          await fileRepo.createFolder(name: 'Docs', workspaceId: 'work');
      final f2Src = File(p.join(tempRoot.path, 'f2.txt'));
      final f2Data = utf8.encode('Work space report content');
      await f2Src.writeAsBytes(f2Data);
      final n2 = await fileRepo.createFileNode(
        name: 'report.txt',
        sizeBytes: f2Data.length,
        parentId: docsWork.id,
        workspaceId: 'work',
      );
      final n2Chunks = await chunkEngine.uploadFile(
        file: f2Src,
        nodeId: n2.id,
        masterKey: masterKey,
        channelId: encChannel.channelId,
        isEncrypted: true,
      );
      await fileRepo.saveFileChunks(n2Chunks);

      // 3. Same-folder duplicate filename in Personal Space -> Docs/report.txt
      final f3Src = File(p.join(tempRoot.path, 'f3.txt'));
      final f3Data = utf8.encode('Duplicate filename in same folder');
      await f3Src.writeAsBytes(f3Data);
      final n3 = await fileRepo.createFileNode(
        name: 'report.txt',
        sizeBytes: f3Data.length,
        parentId: docsPersonal.id,
        workspaceId: 'personal',
      );
      final n3Chunks = await chunkEngine.uploadFile(
        file: f3Src,
        nodeId: n3.id,
        masterKey: masterKey,
        channelId: encChannel.channelId,
        isEncrypted: true,
      );
      await fileRepo.saveFileChunks(n3Chunks);

      // 4. Viewable workspace single plain file
      final f4Src = File(p.join(tempRoot.path, 'clip.mp4'));
      final f4Data = utf8.encode('Plain video stream payload');
      await f4Src.writeAsBytes(f4Data);
      final n4 = await fileRepo.createFileNode(
        name: 'clip.mp4',
        sizeBytes: f4Data.length,
        workspaceId: 'media',
      );
      final n4Chunks = await chunkEngine.uploadFile(
        file: f4Src,
        nodeId: n4.id,
        masterKey: masterKey,
        channelId: viewChannel.channelId,
        isEncrypted: false,
      );
      await fileRepo.saveFileChunks(n4Chunks);

      // 5. Empty 0-byte file
      await fileRepo.createFileNode(
        name: 'empty.dat',
        sizeBytes: 0,
        workspaceId: 'personal',
      );

      final seenActiveTaskDuringRun = <bool>[];
      final states = <VaultExportState>[];

      // Zero caller's masterKey & DB key shortly after start to simulate lockVault()
      final result = await exportService.runExport(
        masterKey: masterKey,
        runInIsolate: false,
        onStateChanged: (s) {
          states.add(s);
          if (s.status == VaultExportStatus.running) {
            seenActiveTaskDuringRun.add(
              transferManager.currentTasks
                  .any((t) => t.status == TransferStatus.running),
            );
            // Simulate lockVault() wiping caller's key & DB key mid-export
            masterKey.fillRange(0, masterKey.length, 0);
            db.clearEncryptionKey();
          }
        },
      );

      expect(result.status, VaultExportStatus.completed);
      expect(result.completedFiles, 5);
      expect(result.failedFiles, isEmpty);
      expect(seenActiveTaskDuringRun, contains(true));
      expect(
        transferManager.currentTasks
            .where((t) => t.status == TransferStatus.running),
        isEmpty,
      );
      expect(await exportService.loadValidCheckpoint(), isNull);

      final outFile = File(result.outputDisplayPath!);
      expect(outFile.existsSync(), isTrue);

      final decoded = ZipDecoder().decodeBytes(await outFile.readAsBytes());
      expect(decoded.length, 5);
      expect(
        decoded.findFile('Personal Space/Docs/report.txt')?.content,
        f1Data,
      );
      expect(
        decoded.findFile('Personal Space/Docs/report (2).txt')?.content,
        f3Data,
      );
      expect(
        decoded.findFile('Work Space/Docs/report.txt')?.content,
        f2Data,
      );
      expect(
        decoded.findFile('Media Gallery/clip.mp4')?.content,
        f4Data,
      );
      expect(decoded.findFile('Personal Space/empty.dat')?.content, isEmpty);
    });

    test('Pauses on cancellation, persists checkpoint, and resumes cleanly',
        () async {
      final masterKey = CryptoEngine.generateMasterKey();
      final encChannel = await storage
          .getOrCreateVaultChannel(AppConfig.getChannelTitle(isEncrypted: true));

      final items = <String, Uint8List>{};
      for (final name in ['one.bin', 'two.bin', 'three.bin']) {
        final f = File(p.join(tempRoot.path, name));
        final data = utf8.encode('Payload for $name');
        await f.writeAsBytes(data);
        final node = await fileRepo.createFileNode(
          name: name,
          sizeBytes: data.length,
        );
        final chunks = await chunkEngine.uploadFile(
          file: f,
          nodeId: node.id,
          masterKey: masterKey,
          channelId: encChannel.channelId,
        );
        await fileRepo.saveFileChunks(chunks);
        items[name] = Uint8List.fromList(data);
      }

      // Cancel as soon as file #1 finishes and file #2 starts
      final pausedResult = await exportService.runExport(
        masterKey: masterKey,
        runInIsolate: false,
        onStateChanged: (s) {
          if (s.status == VaultExportStatus.running && s.completedFiles >= 1) {
            exportService.requestCancel();
          }
        },
      );

      expect(pausedResult.status, VaultExportStatus.paused);
      expect(pausedResult.completedFiles, 1);
      expect(pausedResult.resumableCheckpoint, isNotNull);

      final loadedCp = await exportService.loadValidCheckpoint();
      expect(loadedCp, isNotNull);
      expect(loadedCp!.completedFileCount, 1);

      // Resume and finish remaining files
      final resumedResult = await exportService.runExport(
        masterKey: masterKey,
        resumeCheckpoint: loadedCp,
        runInIsolate: false,
        onStateChanged: (_) {},
      );

      expect(resumedResult.status, VaultExportStatus.completed);
      expect(resumedResult.completedFiles, 3);
      expect(await exportService.loadValidCheckpoint(), isNull);

      final decoded = ZipDecoder().decodeBytes(
        await File(resumedResult.outputDisplayPath!).readAsBytes(),
      );
      expect(decoded.length, 3);
      for (final entry in items.entries) {
        expect(
          decoded.findFile('Personal Space/${entry.key}')?.content,
          entry.value,
        );
      }
    });

    test(
        'Surfaces failed files via partialNeedsAction and supports finalizing partial archive',
        () async {
      final masterKey = CryptoEngine.generateMasterKey();
      final encChannel = await storage
          .getOrCreateVaultChannel(AppConfig.getChannelTitle(isEncrypted: true));

      final goodFile = File(p.join(tempRoot.path, 'good.txt'));
      final goodBytes = utf8.encode('Healthy file');
      await goodFile.writeAsBytes(goodBytes);
      final goodNode = await fileRepo.createFileNode(
        name: 'good.txt',
        sizeBytes: goodBytes.length,
      );
      final goodChunks = await chunkEngine.uploadFile(
        file: goodFile,
        nodeId: goodNode.id,
        masterKey: masterKey,
        channelId: encChannel.channelId,
      );
      await fileRepo.saveFileChunks(goodChunks);

      // Missing remote chunk triggers failure for badNode
      final badNode = await fileRepo.createFileNode(
        name: 'missing_remote.txt',
        sizeBytes: 128,
      );
      await fileRepo.saveFileChunks([
        FileChunk(
          id: 'bad_c1',
          nodeId: badNode.id,
          chunkIndex: 0,
          remoteMessageId: 'msg_missing',
          remoteFileId: 'non_existent_remote_id',
          sizeBytes: 128,
          sha256Hash: 'abc',
          ivHex: '00',
        ),
      ]);

      final partialResult = await exportService.runExport(
        masterKey: masterKey,
        runInIsolate: false,
        onStateChanged: (_) {},
      );

      expect(partialResult.status, VaultExportStatus.partialNeedsAction);
      expect(partialResult.completedFiles, 1);
      expect(partialResult.failedFiles.length, 1);
      expect(partialResult.failedFiles.first.fileName, 'missing_remote.txt');

      final finalized = await exportService.runExport(
        masterKey: masterKey,
        resumeCheckpoint: partialResult.resumableCheckpoint,
        finalizePartialOnly: true,
        runInIsolate: false,
        onStateChanged: (_) {},
      );

      expect(finalized.status, VaultExportStatus.completed);
      expect(finalized.completedFiles, 1);
      expect(finalized.failedFiles.length, 1);

      final decoded = ZipDecoder().decodeBytes(
        await File(finalized.outputDisplayPath!).readAsBytes(),
      );
      expect(decoded.length, 1);
      expect(decoded.findFile('Personal Space/good.txt')?.content, goodBytes);
    });

    test('ChunkingEngine survives transient FLOOD_WAIT via downloadChunkToFile',
        () async {
      final masterKey = CryptoEngine.generateMasterKey();
      final viewChannel = await storage.getOrCreateVaultChannel(
        AppConfig.getChannelTitle(isEncrypted: false),
      );

      final src = File(p.join(tempRoot.path, 'video.mp4'));
      final payload = Uint8List.fromList(List<int>.generate(4096, (i) => i % 256));
      await src.writeAsBytes(payload);

      final chunks = await chunkEngine.uploadFile(
        file: src,
        nodeId: 'vid_1',
        masterKey: masterKey,
        channelId: viewChannel.channelId,
        isEncrypted: false,
      );

      storage.simulatedFloodWaitSeconds = 1;
      final dest = File(p.join(tempRoot.path, 'restored_video.mp4'));
      await chunkEngine.downloadAndDecryptFile(
        chunks: chunks,
        destinationFile: dest,
        masterKey: masterKey,
        channelId: viewChannel.channelId,
      );

      expect(await dest.readAsBytes(), payload);
    });

    test('Runs ZIP append/finalize in background Isolate and auto-pauses on repeated network drops',
        () async {
      final masterKey = CryptoEngine.generateMasterKey();
      final encChannel = await storage
          .getOrCreateVaultChannel(AppConfig.getChannelTitle(isEncrypted: true));

      final src1 = File(p.join(tempRoot.path, 'iso_1.bin'));
      final data1 = utf8.encode('Isolate file 1');
      await src1.writeAsBytes(data1);
      final n1 = await fileRepo.createFileNode(
        name: 'iso_1.bin',
        sizeBytes: data1.length,
      );
      await fileRepo.saveFileChunks(
        await chunkEngine.uploadFile(
          file: src1,
          nodeId: n1.id,
          masterKey: masterKey,
          channelId: encChannel.channelId,
        ),
      );

      // Verify runInIsolate: true succeeds cleanly
      final isoResult = await exportService.runExport(
        masterKey: masterKey,
        runInIsolate: true,
        onStateChanged: (_) {},
      );
      expect(isoResult.status, VaultExportStatus.completed);
      final isoDecoded = ZipDecoder().decodeBytes(
        await File(isoResult.outputDisplayPath!).readAsBytes(),
      );
      expect(isoDecoded.findFile('Personal Space/iso_1.bin')?.content, data1);

      // Seed 2 more files and trigger repeated network drops -> auto-pause with checkpoint
      for (final name in ['net_2.bin', 'net_3.bin']) {
        final f = File(p.join(tempRoot.path, name));
        final d = utf8.encode('Data $name');
        await f.writeAsBytes(d);
        final n = await fileRepo.createFileNode(name: name, sizeBytes: d.length);
        await fileRepo.saveFileChunks(
          await chunkEngine.uploadFile(
            file: f,
            nodeId: n.id,
            masterKey: masterKey,
            channelId: encChannel.channelId,
          ),
        );
      }

      final pausedOnNet = await exportService.runExport(
        masterKey: masterKey,
        runInIsolate: true,
        onStateChanged: (s) {
          if (s.status == VaultExportStatus.running && s.completedFiles >= 1) {
            storage.shouldFailDownload = true;
          }
        },
      );

      expect(pausedOnNet.status, VaultExportStatus.paused);
      expect(pausedOnNet.completedFiles, 1);
      expect(pausedOnNet.resumableCheckpoint, isNotNull);

      // Network recovers -> resume completes all 3 files
      storage.shouldFailDownload = false;
      final recovered = await exportService.runExport(
        masterKey: masterKey,
        resumeCheckpoint: pausedOnNet.resumableCheckpoint,
        runInIsolate: true,
        onStateChanged: (_) {},
      );
      expect(recovered.status, VaultExportStatus.completed);
      expect(recovered.completedFiles, 3);
    });
  });
}
