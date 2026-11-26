import 'dart:io';
import 'dart:typed_data';
import 'package:filo/core/cache/session_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
      testTempDir.deleteSync(recursive: true);
    } catch (_) {}
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

      // Returns null and discards if size mismatch (corrupted stream detection)
      final sizeMismatch = await cache.getCachedFile('test_node_123', expectedSize: 999);
      expect(sizeMismatch, isNull);
    });

    test('Purge wipes all session cache files completely', () async {
      final cache = SessionCacheService.instance;
      final file1 = await cache.getSessionFile('node_a', 'jpg');
      final file2 = await cache.getSessionFile('node_b', 'pdf');
      await file1.writeAsString('photo_data');
      await file2.writeAsString('pdf_data');

      expect(file1.existsSync(), isTrue);
      expect(file2.existsSync(), isTrue);

      await cache.purge();

      expect(file1.existsSync(), isFalse);
      expect(file2.existsSync(), isFalse);
      expect(await cache.getSessionCacheSizeBytes(), 0);
    });
  });
}
