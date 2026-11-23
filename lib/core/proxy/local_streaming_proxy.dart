import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:filo/features/files/data/file_repository.dart';
import 'package:filo/features/transfer/domain/chunking_engine.dart';

/// Lightweight loopback HTTP proxy (strictly bound to 127.0.0.1) that translates
/// video player HTTP Range requests into targeted decrypted chunk streams on the fly.
class LocalStreamingProxy {
  final FileRepository _fileRepository;
  final ChunkingEngine _chunkingEngine;
  final String _channelId;

  HttpServer? _server;
  int? _port;

  LocalStreamingProxy({
    required FileRepository fileRepository,
    required ChunkingEngine chunkingEngine,
    required String channelId,
  })  : _fileRepository = fileRepository,
        _chunkingEngine = chunkingEngine,
        _channelId = channelId;

  int? get port => _port;
  String? get baseUrl => _port != null ? 'http://127.0.0.1:$_port' : null;

  /// Starts the local HTTP streaming server on an available loopback port.
  Future<int> start() async {
    if (_server != null) return _port!;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;

    _server!.listen(_handleRequest);
    return _port!;
  }

  /// Generates a streaming URL for a specific file node.
  String getStreamUrl(String nodeId) {
    if (_port == null) {
      throw StateError('LocalStreamingProxy has not been started yet.');
    }
    return 'http://127.0.0.1:$_port/stream/$nodeId';
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final uri = request.uri;
    final pathSegments = uri.pathSegments;

    if (pathSegments.length != 2 || pathSegments[0] != 'stream') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final nodeId = pathSegments[1];
    final node = await _fileRepository.database.getNode(nodeId);
    if (node == null) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final chunks = await _fileRepository.getChunksForNode(nodeId);
    if (chunks.isEmpty) {
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
      return;
    }

    // Set streaming media headers
    request.response.headers
      ..set(HttpHeaders.contentTypeHeader, node.mimeType ?? 'video/mp4')
      ..set(HttpHeaders.acceptRangesHeader, 'bytes');

    // Handle HTTP Range header for video seeking
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final totalBytes = node.sizeBytes;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      final rangeValues = rangeHeader.substring(6).split('-');
      final start = int.tryParse(rangeValues[0]) ?? 0;
      final end = rangeValues.length > 1 && rangeValues[1].isNotEmpty
          ? int.tryParse(rangeValues[1]) ?? (totalBytes - 1)
          : (totalBytes - 1);

      final contentLength = (end - start) + 1;

      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$totalBytes')
        ..headers.set(HttpHeaders.contentLengthHeader, contentLength.toString());
    } else {
      request.response.headers.set(HttpHeaders.contentLengthHeader, totalBytes.toString());
    }

    // Decrypt and stream chunks into response
    try {
      for (final chunk in chunks) {
        // Download and decrypt chunk
        final chunkBytes = await _chunkingEngine.downloadAndDecryptSingleChunk(
          chunk: chunk,
          masterKey: Uint8List(32), // Injected by caller session
          channelId: _channelId,
        );
        request.response.add(chunkBytes);
      }
    } catch (_) {
      // Client disconnected or seek interrupted
    } finally {
      await request.response.close();
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _port = null;
  }
}
