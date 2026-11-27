import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:filo/core/config/app_config.dart';
import 'package:filo/core/crypto/crypto_engine.dart';
import 'package:filo/core/crypto/hash_utils.dart';
import 'package:filo/core/database/chunk_model.dart';
import 'package:filo/features/files/data/file_repository.dart';
import 'package:filo/features/files/domain/workspace.dart';
import 'package:filo/features/storage/domain/storage_backend.dart';
import 'package:filo/features/transfer/domain/chunking_engine.dart';

/// Lightweight authenticated loopback HTTP proxy (strictly bound to 127.0.0.1) that translates
/// video player HTTP Range requests into targeted decrypted chunk streams on the fly.
/// Includes per-session 256-bit cryptographic token validation, DNS rebinding protection,
/// brute-force rate limiting, and explicit key zeroing on shutdown.
class LocalStreamingProxy {
  static const int _maxFailedAttempts = 10;
  static const Duration _lockoutDuration = Duration(seconds: 30);

  final FileRepository _fileRepository;
  final ChunkingEngine _chunkingEngine;
  final StorageBackend? _storageBackend;
  final String _channelId;
  final Uint8List _masterKey;

  HttpServer? _server;
  int? _port;
  String? _authToken;
  bool _stopped = false;
  int _failedAttempts = 0;
  DateTime? _lockoutUntil;

  LocalStreamingProxy({
    required FileRepository fileRepository,
    required ChunkingEngine chunkingEngine,
    required String channelId,
    required Uint8List masterKey,
    StorageBackend? storageBackend,
  })  : _fileRepository = fileRepository,
        _chunkingEngine = chunkingEngine,
        _channelId = channelId,
        _storageBackend = storageBackend,
        _masterKey = Uint8List.fromList(masterKey);

  int? get port => _port;
  String? get baseUrl => _port != null ? 'http://127.0.0.1:$_port' : null;
  bool get isRunning => _server != null && !_stopped;

  @visibleForTesting
  bool get isMasterKeyZeroed => _masterKey.every((b) => b == 0);

  @visibleForTesting
  bool get hasAuthToken => _authToken != null;

  /// Starts the local HTTP streaming server on an available loopback port
  /// with a fresh 256-bit cryptographically random authorization token.
  Future<int> start() async {
    if (_stopped) {
      throw StateError('LocalStreamingProxy cannot be restarted after stop().');
    }
    if (_server != null) return _port!;

    _authToken = HashUtils.bytesToHex(CryptoEngine.generateMasterKey());
    _failedAttempts = 0;
    _lockoutUntil = null;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _port = _server!.port;

    _server!.listen(_handleRequest);
    return _port!;
  }

  /// Returns HTTP authorization headers for media players that support custom headers,
  /// keeping the session token out of request URLs and logs.
  Map<String, String> getAuthHeaders() {
    if (_stopped || _authToken == null) {
      throw StateError('LocalStreamingProxy has not been started yet.');
    }
    return {'Authorization': 'Bearer $_authToken'};
  }

  /// Generates an authenticated streaming URL for a specific file node.
  /// Set [includeTokenQuery] to false when passing [getAuthHeaders] via HTTP headers.
  String getStreamUrl(String nodeId, {bool includeTokenQuery = true}) {
    if (_stopped || _port == null || _authToken == null) {
      throw StateError('LocalStreamingProxy has not been started yet.');
    }
    final base = 'http://127.0.0.1:$_port/stream/$nodeId';
    return includeTokenQuery ? '$base?token=$_authToken' : base;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (_stopped) {
      await _safeClose(request.response, HttpStatus.serviceUnavailable);
      return;
    }

    // Security: Reject non-loopback Host headers to defend against DNS rebinding attacks.
    final hostHeader = request.headers.value(HttpHeaders.hostHeader);
    if (hostHeader != null && !_isAllowedLoopbackHost(hostHeader)) {
      await _safeWriteAndClose(
        request.response,
        HttpStatus.forbidden,
        'Forbidden: Invalid Host header',
      );
      return;
    }

    // Security: Enforce brute-force lockout after consecutive failed auth attempts.
    final now = DateTime.now();
    if (_lockoutUntil != null) {
      if (now.isBefore(_lockoutUntil!)) {
        final retryAfterSeconds = _lockoutUntil!.difference(now).inSeconds.clamp(1, 30);
        request.response.headers.set(HttpHeaders.retryAfterHeader, retryAfterSeconds.toString());
        await _safeWriteAndClose(
          request.response,
          HttpStatus.tooManyRequests,
          'Too Many Requests: Streaming authentication temporarily locked',
        );
        return;
      }
      _lockoutUntil = null;
      _failedAttempts = 0;
    }

    // Security: Only allow read-only GET and HEAD streaming requests.
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await _safeWriteAndClose(
        request.response,
        HttpStatus.methodNotAllowed,
        'Method Not Allowed',
      );
      return;
    }

    // Security: Validate per-session authorization token (Bearer header preferred, query fallback).
    final providedToken = _extractAuthToken(request);
    final expectedToken = _authToken;
    final tokenValid = expectedToken != null &&
        providedToken.isNotEmpty &&
        HashUtils.constantTimeCompare(
          providedToken.codeUnits,
          expectedToken.codeUnits,
        );

    if (!tokenValid) {
      _failedAttempts++;
      if (_failedAttempts >= _maxFailedAttempts) {
        _lockoutUntil = DateTime.now().add(_lockoutDuration);
      }
      await _safeWriteAndClose(
        request.response,
        HttpStatus.unauthorized,
        'Unauthorized: Missing or invalid streaming token',
      );
      return;
    }

    _failedAttempts = 0;
    _lockoutUntil = null;

    final pathSegments = request.uri.pathSegments;
    if (pathSegments.length != 2 || pathSegments[0] != 'stream') {
      await _safeClose(request.response, HttpStatus.notFound);
      return;
    }

    final nodeId = pathSegments[1];
    if (!_isValidNodeId(nodeId)) {
      await _safeClose(request.response, HttpStatus.badRequest);
      return;
    }

    final node = await _fileRepository.database.getNode(nodeId);
    if (_stopped) {
      await _safeClose(request.response, HttpStatus.serviceUnavailable);
      return;
    }
    if (node == null || node.isTrashed || node.isFolder) {
      await _safeClose(request.response, HttpStatus.notFound);
      return;
    }

    final chunks = await _fileRepository.getChunksForNode(nodeId);
    if (_stopped) {
      await _safeClose(request.response, HttpStatus.serviceUnavailable);
      return;
    }
    if (chunks.isEmpty) {
      await _safeClose(request.response, HttpStatus.noContent);
      return;
    }

    final sortedChunks = List<FileChunk>.from(chunks)
      ..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
    final effectiveChannelId = await _resolveChannelIdForNode(node.workspaceId);
    if (_stopped) {
      await _safeClose(request.response, HttpStatus.serviceUnavailable);
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
    int rangeEnd = totalBytes > 0 ? totalBytes - 1 : 0;
    bool isRange = false;

    if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
      isRange = true;
      final parsedRange = _parseByteRange(rangeHeader, totalBytes);
      if (parsedRange == null) {
        request.response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$totalBytes');
        await _safeCloseResponse(request.response);
        return;
      }

      rangeStart = parsedRange.start;
      rangeEnd = parsedRange.end;
      final contentLength = (rangeEnd - rangeStart) + 1;

      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(HttpHeaders.contentRangeHeader, 'bytes $rangeStart-$rangeEnd/$totalBytes')
        ..headers.set(HttpHeaders.contentLengthHeader, contentLength.toString());
    } else {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.set(HttpHeaders.contentLengthHeader, (totalBytes < 0 ? 0 : totalBytes).toString());
    }

    if (request.method == 'HEAD' || totalBytes <= 0) {
      await _safeCloseResponse(request.response);
      return;
    }

    // Decrypt and stream chunks into response
    try {
      int currentOffset = 0;
      for (final chunk in sortedChunks) {
        if (_stopped) break;

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
          masterKey: _masterKey,
          channelId: effectiveChannelId,
        );
        if (_stopped) break;

        if (isRange) {
          final sliceStart = (rangeStart > chunkStart) ? (rangeStart - chunkStart) : 0;
          final sliceEnd = (rangeEnd < chunkEnd) ? (rangeEnd - chunkStart + 1) : chunkBytes.length;
          if (sliceStart < chunkBytes.length) {
            request.response.add(
              chunkBytes.sublist(sliceStart, sliceEnd.clamp(sliceStart, chunkBytes.length)),
            );
          }
        } else {
          request.response.add(chunkBytes);
        }
      }
    } catch (_) {
      // Client disconnected or seek interrupted
    } finally {
      await _safeCloseResponse(request.response);
    }
  }

  bool _isAllowedLoopbackHost(String hostHeader) {
    final normalized = hostHeader.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    final colonIndex = normalized.indexOf(':');
    final hostOnly = colonIndex >= 0 ? normalized.substring(0, colonIndex) : normalized;
    if (colonIndex >= 0) {
      final portStr = normalized.substring(colonIndex + 1);
      final parsedPort = int.tryParse(portStr);
      if (parsedPort == null || parsedPort < 1 || parsedPort > 65535) {
        return false;
      }
    }

    return hostOnly == '127.0.0.1' || hostOnly == 'localhost';
  }

  String _extractAuthToken(HttpRequest request) {
    final authHeader = request.headers.value(HttpHeaders.authorizationHeader);
    if (authHeader != null && authHeader.trim().isNotEmpty) {
      final trimmed = authHeader.trim();
      if (trimmed.length > 7 && trimmed.substring(0, 7).toLowerCase() == 'bearer ') {
        return trimmed.substring(7).trim();
      }
      return '';
    }
    return request.uri.queryParameters['token'] ?? '';
  }

  bool _isValidNodeId(String nodeId) {
    return nodeId.isNotEmpty &&
        !nodeId.contains('..') &&
        !nodeId.contains('/') &&
        !nodeId.contains('\\') &&
        !nodeId.contains('\x00');
  }

  Future<String> _resolveChannelIdForNode(String workspaceId) async {
    if (_storageBackend == null && _channelId.isNotEmpty) {
      return _channelId;
    }

    try {
      final workspaces = await _fileRepository.getWorkspaces();
      final ws = workspaces.firstWhere(
        (w) => w.id == workspaceId,
        orElse: () => Workspace.fromId(workspaceId, workspaces),
      );
      final channelTitle = AppConfig.getChannelTitle(isEncrypted: ws.isEncrypted);
      if (_storageBackend != null) {
        final channelInfo = await _storageBackend.getOrCreateVaultChannel(channelTitle);
        return channelInfo.channelId;
      }
      if (_channelId.isEmpty) {
        return channelTitle;
      }
    } catch (_) {
      // Fall back to configured channel ID if workspace lookup fails.
    }

    return _channelId;
  }

  ({int start, int end})? _parseByteRange(String rangeHeader, int totalBytes) {
    if (totalBytes <= 0) return null;

    final spec = rangeHeader.substring(6).trim();
    if (spec.isEmpty || spec.contains(',')) return null;

    final rangeValues = spec.split('-');
    if (rangeValues.length != 2) return null;

    final startStr = rangeValues[0].trim();
    final endStr = rangeValues[1].trim();

    int rangeStart;
    int rangeEnd;

    if (startStr.isEmpty) {
      final suffixLength = int.tryParse(endStr);
      if (suffixLength == null || suffixLength <= 0) return null;
      rangeStart = totalBytes - suffixLength;
      if (rangeStart < 0) rangeStart = 0;
      rangeEnd = totalBytes - 1;
    } else {
      final parsedStart = int.tryParse(startStr);
      if (parsedStart == null || parsedStart < 0) return null;
      rangeStart = parsedStart;

      if (endStr.isEmpty) {
        rangeEnd = totalBytes - 1;
      } else {
        final parsedEnd = int.tryParse(endStr);
        if (parsedEnd == null || parsedEnd < 0) return null;
        rangeEnd = parsedEnd >= totalBytes ? totalBytes - 1 : parsedEnd;
      }
    }

    if (rangeStart < 0 || rangeStart > rangeEnd || rangeStart >= totalBytes) {
      return null;
    }

    return (start: rangeStart, end: rangeEnd);
  }

  Future<void> _safeClose(HttpResponse response, int statusCode) async {
    try {
      response.statusCode = statusCode;
      await response.close();
    } catch (_) {}
  }

  Future<void> _safeWriteAndClose(
    HttpResponse response,
    int statusCode,
    String body,
  ) async {
    try {
      response.statusCode = statusCode;
      response.write(body);
      await response.close();
    } catch (_) {}
  }

  Future<void> _safeCloseResponse(HttpResponse response) async {
    try {
      await response.close();
    } catch (_) {}
  }

  Future<void> stop() async {
    _stopped = true;
    _authToken = null;
    _failedAttempts = 0;
    _lockoutUntil = null;
    _masterKey.fillRange(0, _masterKey.length, 0);
    await _server?.close(force: true);
    _server = null;
    _port = null;
  }
}
