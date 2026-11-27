import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:filo/core/config/app_config.dart';
import 'package:filo/core/crypto/crypto_engine.dart';
import 'package:filo/core/database/filo_database.dart';
import 'package:filo/core/proxy/local_streaming_proxy.dart';
import 'package:filo/features/broadcast/domain/broadcast_service.dart';
import 'package:filo/features/files/data/file_repository.dart';
import 'package:filo/features/files/domain/workspace.dart';
import 'package:filo/features/storage/data/fake_storage_backend.dart';
import 'package:filo/features/transfer/domain/chunking_engine.dart';
import 'package:filo/features/update/domain/update_service.dart';

Future<({int statusCode, HttpHeaders headers, Uint8List body})> _sendHttpRequest({
  required String method,
  required Uri uri,
  Map<String, String>? headers,
}) async {
  final client = HttpClient();
  try {
    final request = await client.openUrl(method, uri);
    if (headers != null) {
      headers.forEach((key, value) {
        request.headers.set(key, value);
      });
    }
    final response = await request.close();
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return (
      statusCode: response.statusCode,
      headers: response.headers,
      body: builder.toBytes(),
    );
  } finally {
    client.close(force: true);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalStreamingProxy Security Hardening', () {
    late FiloDatabase db;
    late FakeStorageBackend storage;
    late FileRepository fileRepo;
    late ChunkingEngine chunkEngine;
    late Directory tempDir;
    late Uint8List masterKey;
    late String encryptedChannelId;
    late String viewableChannelId;
    late String encryptedNodeId;
    late String trashedNodeId;
    late String viewableNodeId;
    late LocalStreamingProxy proxy;
    HttpOverrides? previousHttpOverrides;

    final samplePlaintext = utf8.encode('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-FiloStreamTest');

    setUp(() async {
      previousHttpOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      db = FiloDatabase.openInMemory();
      storage = FakeStorageBackend();
      await storage.initialize();
      storage.setAuthenticated();

      fileRepo = FileRepository(database: db);
      chunkEngine = ChunkingEngine(storageBackend: storage);
      tempDir = Directory.systemTemp.createTempSync('filo_proxy_test_');
      masterKey = CryptoEngine.generateMasterKey();

      final encChannel = await storage.getOrCreateVaultChannel(
        AppConfig.getChannelTitle(isEncrypted: true),
      );
      encryptedChannelId = encChannel.channelId;

      final viewChannel = await storage.getOrCreateVaultChannel(
        AppConfig.getChannelTitle(isEncrypted: false),
      );
      viewableChannelId = viewChannel.channelId;

      // Seed default encrypted file node
      final sourceFile = File('${tempDir.path}/sample.mp4');
      await sourceFile.writeAsBytes(samplePlaintext);

      final encNode = await fileRepo.createFileNode(
        name: 'sample.mp4',
        sizeBytes: samplePlaintext.length,
        mimeType: 'video/mp4',
        workspaceId: 'personal',
      );
      encryptedNodeId = encNode.id;

      final encChunks = await chunkEngine.uploadFile(
        file: sourceFile,
        nodeId: encryptedNodeId,
        masterKey: masterKey,
        channelId: encryptedChannelId,
        isEncrypted: true,
      );
      await fileRepo.saveFileChunks(encChunks);

      // Seed trashed file node
      final trashedNode = await fileRepo.createFileNode(
        name: 'trashed.mp4',
        sizeBytes: samplePlaintext.length,
        mimeType: 'video/mp4',
        workspaceId: 'personal',
      );
      trashedNodeId = trashedNode.id;
      final trashedChunks = await chunkEngine.uploadFile(
        file: sourceFile,
        nodeId: trashedNodeId,
        masterKey: masterKey,
        channelId: encryptedChannelId,
        isEncrypted: true,
      );
      await fileRepo.saveFileChunks(trashedChunks);
      await fileRepo.moveToTrash(trashedNodeId);

      // Seed viewable workspace and file node
      await fileRepo.createWorkspace(
        const Workspace(
          id: 'viewable_ws',
          name: 'Viewable Space',
          description: 'Unencrypted Telegram media',
          icon: Icons.folder_outlined,
          isEncrypted: false,
        ),
      );
      final viewNode = await fileRepo.createFileNode(
        name: 'viewable.mp4',
        sizeBytes: samplePlaintext.length,
        mimeType: 'video/mp4',
        workspaceId: 'viewable_ws',
      );
      viewableNodeId = viewNode.id;
      final viewChunks = await chunkEngine.uploadFile(
        file: sourceFile,
        nodeId: viewableNodeId,
        masterKey: masterKey,
        channelId: viewableChannelId,
        isEncrypted: false,
      );
      await fileRepo.saveFileChunks(viewChunks);

      proxy = LocalStreamingProxy(
        fileRepository: fileRepo,
        chunkingEngine: chunkEngine,
        channelId: encryptedChannelId,
        masterKey: masterKey,
        storageBackend: storage,
      );
      await proxy.start();
    });

    tearDown(() async {
      await proxy.stop();
      db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
      HttpOverrides.global = previousHttpOverrides;
    });

    test('Uses 256-bit session token and defensively copies masterKey', () async {
      final streamUri = Uri.parse(proxy.getStreamUrl(encryptedNodeId));
      final queryToken = streamUri.queryParameters['token'];
      expect(queryToken, isNotNull);
      expect(queryToken!.length, 64); // 256-bit hex token

      final authHeaders = proxy.getAuthHeaders();
      expect(authHeaders['Authorization'], 'Bearer $queryToken');

      // Mutating caller masterKey buffer must not corrupt proxy's internal copy
      final callerCopy = Uint8List.fromList(masterKey);
      masterKey.fillRange(0, masterKey.length, 0);

      final res = await _sendHttpRequest(
        method: 'GET',
        uri: streamUri,
      );
      expect(res.statusCode, HttpStatus.ok);
      expect(res.body, Uint8List.fromList(samplePlaintext));

      // Restore for tearDown readability
      masterKey.setAll(0, callerCopy);
    });

    test('Rejects missing token with 401 Unauthorized', () async {
      final uri = Uri.parse(proxy.getStreamUrl(encryptedNodeId, includeTokenQuery: false));
      final res = await _sendHttpRequest(method: 'GET', uri: uri);
      expect(res.statusCode, HttpStatus.unauthorized);
    });

    test('Rejects wrong query token and wrong Bearer token with 401 Unauthorized', () async {
      final baseUri = Uri.parse(proxy.getStreamUrl(encryptedNodeId, includeTokenQuery: false));

      final wrongQueryRes = await _sendHttpRequest(
        method: 'GET',
        uri: baseUri.replace(queryParameters: {'token': 'deadbeef'}),
      );
      expect(wrongQueryRes.statusCode, HttpStatus.unauthorized);

      final wrongHeaderRes = await _sendHttpRequest(
        method: 'GET',
        uri: baseUri,
        headers: {'Authorization': 'Bearer wrong_token_value'},
      );
      expect(wrongHeaderRes.statusCode, HttpStatus.unauthorized);
    });

    test('Rejects invalid Host header (DNS rebinding) with 403 Forbidden', () async {
      final uri = Uri.parse(proxy.getStreamUrl(encryptedNodeId));
      final res = await _sendHttpRequest(
        method: 'GET',
        uri: uri,
        headers: {'Host': 'evil.com'},
      );
      expect(res.statusCode, HttpStatus.forbidden);
    });

    test('Rejects non-GET/HEAD methods such as POST with 405 Method Not Allowed', () async {
      final uri = Uri.parse(proxy.getStreamUrl(encryptedNodeId));
      final res = await _sendHttpRequest(method: 'POST', uri: uri);
      expect(res.statusCode, HttpStatus.methodNotAllowed);
    });

    test('Streams full decrypted bytes with ?token= query parameter and Authorization Bearer header', () async {
      // 1. Legacy ?token= query parameter
      final queryUri = Uri.parse(proxy.getStreamUrl(encryptedNodeId));
      final queryRes = await _sendHttpRequest(method: 'GET', uri: queryUri);
      expect(queryRes.statusCode, HttpStatus.ok);
      expect(queryRes.body, Uint8List.fromList(samplePlaintext));

      // 2. Preferred Authorization: Bearer header without query token
      final headerUri = Uri.parse(proxy.getStreamUrl(encryptedNodeId, includeTokenQuery: false));
      final headerRes = await _sendHttpRequest(
        method: 'GET',
        uri: headerUri,
        headers: proxy.getAuthHeaders(),
      );
      expect(headerRes.statusCode, HttpStatus.ok);
      expect(headerRes.body, Uint8List.fromList(samplePlaintext));

      // 3. HEAD returns headers with empty body
      final headRes = await _sendHttpRequest(
        method: 'HEAD',
        uri: headerUri,
        headers: proxy.getAuthHeaders(),
      );
      expect(headRes.statusCode, HttpStatus.ok);
      expect(headRes.body, isEmpty);
      expect(headRes.headers.value(HttpHeaders.acceptRangesHeader), 'bytes');
    });

    test('Supports HTTP Range requests (206 Partial Content) and rejects invalid ranges (416)', () async {
      final uri = Uri.parse(proxy.getStreamUrl(encryptedNodeId, includeTokenQuery: false));
      final res = await _sendHttpRequest(
        method: 'GET',
        uri: uri,
        headers: {
          ...proxy.getAuthHeaders(),
          HttpHeaders.rangeHeader: 'bytes=0-4',
        },
      );
      expect(res.statusCode, HttpStatus.partialContent);
      expect(res.headers.value(HttpHeaders.contentRangeHeader), 'bytes 0-4/${samplePlaintext.length}');
      expect(utf8.decode(res.body), '01234');

      // Out-of-bounds range
      final badRangeRes = await _sendHttpRequest(
        method: 'GET',
        uri: uri,
        headers: {
          ...proxy.getAuthHeaders(),
          HttpHeaders.rangeHeader: 'bytes=${samplePlaintext.length + 10}-${samplePlaintext.length + 20}',
        },
      );
      expect(badRangeRes.statusCode, HttpStatus.requestedRangeNotSatisfiable);
    });

    test('Rejects trashed nodes with 404 Not Found and path traversal nodeId with 400 Bad Request', () async {
      final trashedUri = Uri.parse(proxy.getStreamUrl(trashedNodeId, includeTokenQuery: false));
      final trashedRes = await _sendHttpRequest(
        method: 'GET',
        uri: trashedUri,
        headers: proxy.getAuthHeaders(),
      );
      expect(trashedRes.statusCode, HttpStatus.notFound);

      final traversalUri = Uri.parse('${proxy.baseUrl}/stream/..%2Fsecret');
      final traversalRes = await _sendHttpRequest(
        method: 'GET',
        uri: traversalUri,
        headers: proxy.getAuthHeaders(),
      );
      expect(traversalRes.statusCode, HttpStatus.badRequest);
    });

    test('Streams viewable (unencrypted) workspace nodes properly', () async {
      final uri = Uri.parse(proxy.getStreamUrl(viewableNodeId, includeTokenQuery: false));
      final res = await _sendHttpRequest(
        method: 'GET',
        uri: uri,
        headers: proxy.getAuthHeaders(),
      );
      expect(res.statusCode, HttpStatus.ok);
      expect(res.body, Uint8List.fromList(samplePlaintext));
    });

    test('Enforces brute-force rate limit: 10 bad token requests lock 11th with 429 Too Many Requests', () async {
      final badUri = Uri.parse('${proxy.baseUrl}/stream/$encryptedNodeId?token=bad_attempt');
      for (int i = 0; i < 10; i++) {
        final res = await _sendHttpRequest(method: 'GET', uri: badUri);
        expect(res.statusCode, HttpStatus.unauthorized);
      }

      // 11th request must be rate-limited even if a valid token is now provided
      final validUri = Uri.parse(proxy.getStreamUrl(encryptedNodeId));
      final lockedRes = await _sendHttpRequest(method: 'GET', uri: validUri);
      expect(lockedRes.statusCode, HttpStatus.tooManyRequests);
    });

    test('stop() zeroes internal masterKey, clears auth token, and shuts down server', () async {
      final runningPort = proxy.port!;
      final callerMasterKeySnapshot = Uint8List.fromList(masterKey);

      await proxy.stop();

      expect(proxy.isRunning, isFalse);
      expect(proxy.port, isNull);
      expect(proxy.baseUrl, isNull);
      expect(proxy.hasAuthToken, isFalse);
      expect(proxy.isMasterKeyZeroed, isTrue);
      // Caller's copy remains untouched thanks to defensive copy
      expect(masterKey, callerMasterKeySnapshot);
      expect(() => proxy.getStreamUrl(encryptedNodeId), throwsStateError);
      expect(() => proxy.getAuthHeaders(), throwsStateError);

      await expectLater(
        _sendHttpRequest(
          method: 'GET',
          uri: Uri.parse('http://127.0.0.1:$runningPort/stream/$encryptedNodeId'),
        ),
        throwsA(isA<SocketException>()),
      );
    });
  });

  group('BroadcastNotifier & UpdateService URL Allowlisting', () {
    const transferChannel = MethodChannel('com.filo.vault.filo/transfers');
    final recordedMethodCalls = <MethodCall>[];
    final recordedClipboardWrites = <String>[];

    setUp(() {
      recordedMethodCalls.clear();
      recordedClipboardWrites.clear();
      FlutterSecureStorage.setMockInitialValues({});

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(transferChannel, (call) async {
        recordedMethodCalls.add(call);
        return null;
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<dynamic, dynamic>?;
          if (args != null && args['text'] is String) {
            recordedClipboardWrites.add(args['text'] as String);
          }
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(transferChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('Accepts trusted HTTPS GitHub repository and release asset URLs', () {
      const trustedUrls = [
        'https://github.com/pr4xh4r/filo/releases',
        'https://github.com/pr4xh4r/filo/releases/download/v1.0.2/app.apk',
        'https://github.com/pr4xh4r/filo',
        'https://github.com/pr4xh4r',
        'https://raw.githubusercontent.com/pr4xh4r/filo/master/broadcast.json',
        'https://objects.githubusercontent.com/github-production-release-asset/123456',
        'https://github-releases.githubusercontent.com/123456/filo-v1.0.2.apk',
      ];

      for (final url in trustedUrls) {
        expect(BroadcastNotifier.isTrustedUrl(url), isTrue, reason: 'Broadcast should trust $url');
        expect(UpdateService.isTrustedUrl(url), isTrue, reason: 'UpdateService should trust $url');
      }
    });

    test('Rejects cleartext HTTP, untrusted hosts, spoofed repo paths, and dangerous schemes', () {
      const untrustedUrls = [
        'http://github.com/pr4xh4r/filo',
        'https://evil.com/malware.apk',
        'https://github.com/attacker/filo',
        'https://github.com/pr4xh4r/filo-malware/releases',
        'https://github.com/pr4xh4r/filo/../attacker/repo',
        'https://github.com.evil.com/pr4xh4r/filo',
        'https://github.com@evil.com/pr4xh4r/filo',
        'https://raw.githubusercontent.com/attacker/filo/master/broadcast.json',
        'javascript:alert(1)',
        'file:///etc/passwd',
        '',
      ];

      for (final url in untrustedUrls) {
        expect(BroadcastNotifier.isTrustedUrl(url), isFalse, reason: 'Broadcast should reject $url');
        expect(UpdateService.isTrustedUrl(url), isFalse, reason: 'UpdateService should reject $url');
      }
    });

    test('openUrl and openDownloadUrl block untrusted URLs without invoking native channel or clipboard', () async {
      await BroadcastNotifier.openUrl('https://evil.com/malware.apk');
      await UpdateService.openDownloadUrl('http://github.com/pr4xh4r/filo/releases');
      await BroadcastNotifier.openUrl('javascript:alert(1)');

      expect(recordedMethodCalls, isEmpty);
      expect(recordedClipboardWrites, isEmpty);

      await BroadcastNotifier.openUrl('https://github.com/pr4xh4r/filo/releases');
      await UpdateService.openDownloadUrl('https://github.com/pr4xh4r/filo/releases/download/v1.0.2/app.apk');

      expect(recordedMethodCalls.length, 2);
      expect(recordedMethodCalls[0].method, 'openUrl');
      expect(recordedMethodCalls[0].arguments, {'url': 'https://github.com/pr4xh4r/filo/releases'});
      expect(recordedMethodCalls[1].method, 'openUrl');
      expect(
        recordedMethodCalls[1].arguments,
        {'url': 'https://github.com/pr4xh4r/filo/releases/download/v1.0.2/app.apk'},
      );
    });

    test('UpdateService.checkForUpdate falls back to official releases URL if API returns untrusted download URL', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'tag_name': 'v9.9.9',
            'name': 'Filo v9.9.9',
            'html_url': 'https://evil.com/phish',
            'body': '- Security patch',
            'published_at': '2026-11-27T00:00:00Z',
            'assets': [
              {
                'name': 'filo.apk',
                'browser_download_url': 'http://evil.com/malware.apk',
              },
            ],
          }),
          200,
        );
      });

      final service = UpdateService(client: mockClient);
      final info = await service.checkForUpdate();

      expect(info, isNotNull);
      expect(info!.downloadUrl, 'https://github.com/pr4xh4r/filo/releases');
    });

    test('BroadcastNotifier.refresh sanitizes untrusted manifest actionUrl and update downloadUrl', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'broadcast': {
              'id': 'notice_spoof_test',
              'title': 'Notice',
              'message': 'Check release',
              'action_title': 'Click',
              'action_url': 'https://evil.com/phishing',
              'is_dismissible': true,
              'priority': 'normal',
            },
            'update': {
              'latest_version': '9.9.9',
              'title': 'Filo v9.9.9',
              'changelog': ['Fix'],
              'download_url': 'https://github.com/attacker/filo/releases/download/v9/app.apk',
              'is_mandatory': false,
            },
          }),
          200,
        );
      });

      final notifier = BroadcastNotifier(client: mockClient);
      await notifier.refresh();

      expect(notifier.state.broadcast, isNotNull);
      expect(notifier.state.broadcast!.actionUrl, isNull);
      expect(notifier.state.update, isNotNull);
      expect(notifier.state.update!.downloadUrl, 'https://github.com/pr4xh4r/filo/releases');
      notifier.dispose();
    });
  });
}
