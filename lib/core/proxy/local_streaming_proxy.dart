import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:filo/core/crypto/crypto_engine.dart';
import 'package:filo/core/crypto/hash_utils.dart';
import 'package:filo/features/files/data/file_repository.dart';
import 'package:filo/features/transfer/domain/chunking_engine.dart';

/// Lightweight authenticated loopback HTTP proxy (strictly bound to 127.0.0.1) that translates
/// video player HTTP Range requests into targeted decrypted chunk streams on the fly.
/// Includes per-session cryptographic token validation to prevent unauthorized local process access.
class LocalStreamingProxy {
  final FileRepository _fileRepository;
  final ChunkingEngine _chunkingEngine;
  final String _channelId;
  final Uint8List _masterKey;

  HttpServer? _server;
  int? _port;
  String? _authToken;

  LocalStreamingProxy({
    required FileRepository fileRepository,
    required ChunkingEngine chunkingEngine,
    required String channelId,
    required Uint8List masterKey,
  })  : _fileRepository = fileRepository,
        _chunkingEngine = chunkingEngine,
        _channelId = channelId,
        _masterKey = masterKey;

  int? get port => _port;
  String? get baseUrl => _port != null ? 'http://127.0.0.1:$_port' : null;

  /// Starts the local HTTP streaming server on an available loopback port
  /// with a fresh cryptographically random authorization token.
  Future<int> start() async {
    if (_server != null) return _port!;

    _authToken = HashUtils.bytesToHex(CryptoEngine.generateIv());
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;

    _server!.listen(_handleRequest);
    return _port!;
  }

  /// Generates an authenticated streaming URL for a specific file node.
  String getStreamUrl(String nodeId) {
    if (_port == null || _authToken == null) {
      throw StateError('LocalStreamingProxy has not been started yet.');
    }
    return 'http://127.0.0.1:$_port/stream/$nodeId?token=$_authToken';
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final uri = request.uri;

    // Security: Validate per-session authorization token to prevent
    // local co-installed applications from accessing decrypted streams.
    final providedToken = uri.queryParameters['token'] ?? '';
    final tokenValid = _authToken != null &&
        providedToken.isNotEmpty &&
        HashUtils.constantTimeCompare(
          providedToken.codeUnits,
          _authToken!.codeUnits,
        );

    if (!tokenValid) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write('Unauthorized: Missing or invalid streaming token');
      await request.response.close();
      return;
    }

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
    int rangeStart = 0;
    int rangeEnd = totalBytes - 1;
    bool isRange = false;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      isRange = true;
      final rangeValues = rangeHeader.substring(6).split('-');
      rangeStart = int.tryParse(rangeValues[0]) ?? 0;
      rangeEnd = rangeValues.length > 1 && rangeValues[1].isNotEmpty
          ? int.tryParse(rangeValues[1]) ?? (totalBytes - 1)
          : (totalBytes - 1);

      if (rangeStart > rangeEnd || rangeStart >= totalBytes) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$totalBytes');
        await request.response.close();
        return;
      }

      final contentLength = (rangeEnd - rangeStart) + 1;

      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $rangeStart-$rangeEnd/$totalBytes')
        ..headers.set(HttpHeaders.contentLengthHeader, contentLength.toString());
    } else {
      request.response.headers.set(HttpHeaders.contentLengthHeader, totalBytes.toString());
    }

    // Decrypt and stream chunks into response
    try {
      int currentOffset = 0;
      for (final chunk in chunks) {
        final chunkStart = currentOffset;
        final chunkEnd = currentOffset + chunk.sizeBytes - 1;
        currentOffset += chunk.sizeBytes;

        if (isRange) {
          if (chunkEnd < rangeStart) {
            continue;
          }
          if (chunkStart > rangeEnd) {
            break;
          }
        }

        // Download and decrypt chunk
        final chunkBytes = await _chunkingEngine.downloadAndDecryptSingleChunk(
          chunk: chunk,
          masterKey: _masterKey, // BUG 1 FIX: real key used
          channelId: _channelId,
        );

        if (isRange) {
          final sliceStart = (rangeStart > chunkStart) ? (rangeStart - chunkStart) : 0;
          final sliceEnd = (rangeEnd < chunkEnd) ? (rangeEnd - chunkStart + 1) : chunkBytes.length;
          if (sliceStart < chunkBytes.length) {
            request.response.add(chunkBytes.sublist(sliceStart, sliceEnd.clamp(sliceStart, chunkBytes.length)));
          }
        } else {
          request.response.add(chunkBytes);
        }
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
