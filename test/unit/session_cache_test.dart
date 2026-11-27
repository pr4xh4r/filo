import 'dart:io';
import 'dart:typed_data';
import 'package:filo/core/cache/session_cache_service.dart';
import 'package:filo/core/database/filo_database.dart';
import 'package:filo/features/files/data/file_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory testTempDir;

  setUp(() {
    testTempDir = Directory.systemTemp.createTempSync('session_cache_test_');
    SessionCacheService.instance.setOverrideDirectory(testTempDir);
  });

  tearDown(() {
    SessionCacheService.instance.setOverrideDirectory(null);
    try {
      if (testTempDir.existsSync()) {
        testTempDir.deleteSync(recursive: true);
      }
    } catch (_) {
      // Best-effort temp cleanup
    }
  });

  group('SessionCacheService Unit Tests', () {
    test('Stores and retrieves cached session file with size validation', () async {
      final cache = SessionCacheService.instance;
      final file = await cache.getSessionFile('test_node_123', 'mp4');

      expect(file.path.contains('session_test_node_123.mp4'), isTrue);

      // Initially null because file does not exist on disk
      final missing = await cache.getCachedFile('test_node_123');
      expect(missing, isNull);

      // Write mock content
      final content = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      await file.writeAsBytes(content);

      // Successfully retrieves valid file
      final hit = await cache.getCachedFile('test_node_123', expectedSize: 8);
      expect(hit, isNotNull);
      expect(hit!.existsSync(), isTrue);
      expect(hit.lengthSync(), 8);

      // Returns null and securely discards if size mismatch (corrupted stream detection)
      final sizeMismatch = await cache.getCachedFile('test_node_123', expectedSize: 999);
      expect(sizeMismatch, isNull);
      expect(file.existsSync(), isFalse);
    });

    test('Purge wipes all session cache files and nested directories completely', () async {
      final cache = SessionCacheService.instance;
      final file1 = await cache.getSessionFile('node_a', 'jpg');
      final file2 = await cache.getSessionFile('node_b', 'pdf');
      final subDir = Directory(p.join(testTempDir.path, 'nested_dir'))..createSync();
      final nestedFile = File(p.join(subDir.path, 'secret.bin'));
      await file1.writeAsString('photo_data');
      await file2.writeAsString('pdf_data');
      await nestedFile.writeAsString('nested_secret');

      expect(file1.existsSync(), isTrue);
      expect(file2.existsSync(), isTrue);
      expect(nestedFile.existsSync(), isTrue);

      await cache.purge();

      expect(file1.existsSync(), isFalse);
      expect(file2.existsSync(), isFalse);
      expect(nestedFile.existsSync(), isFalse);
      expect(subDir.existsSync(), isFalse);
      expect(await cache.getSessionCacheSizeBytes(), 0);
    });

    test('secureDeleteFile and secureDeleteFileSync erase multi-chunk and empty files', () async {
      // Multi-chunk (> 64 KB) file to exercise chunked zeroing loop
      final largeFile = File(p.join(testTempDir.path, 'large_secret.bin'));
      final payload = Uint8List.fromList(List<int>.generate(150 * 1024, (i) => (i % 251) + 1));
      await largeFile.writeAsBytes(payload, flush: true);
      expect(largeFile.existsSync(), isTrue);

      await SessionCacheService.secureDeleteFile(largeFile);
      expect(largeFile.existsSync(), isFalse);

      // Synchronous deletion on non-empty and missing files
      final syncFile = File(p.join(testTempDir.path, 'sync_secret.txt'));
      syncFile.writeAsStringSync('top-secret-sync-content');
      expect(syncFile.existsSync(), isTrue);

      SessionCacheService.secureDeleteFileSync(syncFile);
      expect(syncFile.existsSync(), isFalse);

      // Should not throw on non-existent files
      await SessionCacheService.secureDeleteFile(largeFile);
      SessionCacheService.secureDeleteFileSync(syncFile);
    });

    test('secureDeleteDirectory recursively erases files and subdirectories', () async {
      final targetDir = Directory(p.join(testTempDir.path, 'offline_vault_test'))..createSync();
      final subDir = Directory(p.join(targetDir.path, 'sub'))..createSync();
      final fileA = File(p.join(targetDir.path, 'a.bin'))..writeAsBytesSync([10, 20, 30]);
      final fileB = File(p.join(subDir.path, 'b.bin'))..writeAsBytesSync(List<int>.filled(80 * 1024, 42));

      expect(targetDir.existsSync(), isTrue);
      expect(fileA.existsSync(), isTrue);
      expect(fileB.existsSync(), isTrue);

      await SessionCacheService.secureDeleteDirectory(targetDir);

      expect(fileA.existsSync(), isFalse);
      expect(fileB.existsSync(), isFalse);
      expect(subDir.existsSync(), isFalse);
      expect(targetDir.existsSync(), isFalse);

      // Should not throw on non-existent directory
      await SessionCacheService.secureDeleteDirectory(targetDir);
    });

    test('evictLruIfNeeded securely removes oldest files beyond maxCacheFiles', () async {
      final cache = SessionCacheService.instance;
      final created = <File>[];
      final baseTime = DateTime(2026, 1, 1);

      for (int i = 0; i < SessionCacheService.maxCacheFiles + 3; i++) {
        final f = await cache.getSessionFile('lru_$i', 'bin');
        await f.writeAsBytes([1, 2, 3, 4]);
        f.setLastModifiedSync(baseTime.add(Duration(minutes: i)));
        created.add(f);
      }

      await cache.evictLruIfNeeded();

      expect(created[0].existsSync(), isFalse);
      expect(created[1].existsSync(), isFalse);
      expect(created[2].existsSync(), isFalse);
      expect(created[3].existsSync(), isTrue);
      expect(created.last.existsSync(), isTrue);
    });
  });

  group('FileRepository Path Traversal Sanitization Tests (VULN-09)', () {
    late FiloDatabase db;
    late FileRepository repo;

    setUp(() {
      db = FiloDatabase.openInMemory();
      repo = FileRepository(database: db);
    });

    tearDown(() {
      db.close();
    });

    test('createFileNode sanitizes traversal paths before DB insertion', () async {
      final created = await repo.createFileNode(
        name: '../../etc/passwd',
        sizeBytes: 128,
      );
      expect(created.name, 'passwd');

      final persisted = await db.getNode(created.id);
      expect(persisted, isNotNull);
      expect(persisted!.name, 'passwd');

      final dotOnly = await repo.createFileNode(
        name: '../../..',
        sizeBytes: 64,
      );
      expect(dotOnly.name, 'unnamed_file');
    });

    test('createFolder sanitizes traversal paths and preserves normal names', () async {
      final sanitized = await repo.createFolder(name: '../secret/folder');
      expect(sanitized.name, 'folder');

      final persisted = await db.getNode(sanitized.id);
      expect(persisted, isNotNull);
      expect(persisted!.name, 'folder');

      final normal = await repo.createFolder(name: '  My Folder  ');
      expect(normal.name, 'My Folder');
    });

    test('renameNode sanitizes traversal paths before DB update', () async {
      final node = await repo.createFileNode(
        name: 'Tax_Return_2025.pdf',
        sizeBytes: 512,
      );
      expect(node.name, 'Tax_Return_2025.pdf');

      await repo.renameNode(node.id, '../../evil');
      final renamed = await db.getNode(node.id);
      expect(renamed, isNotNull);
      expect(renamed!.name, 'evil');
    });
  });
}
