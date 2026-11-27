import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../../../core/config/app_config.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/crypto/hash_utils.dart';
import '../../../core/database/chunk_model.dart';
import '../../storage/domain/storage_backend.dart';

/// Exception thrown when an active transfer or export is explicitly cancelled.
class TransferCancelledException implements Exception {
  final String message;
  const TransferCancelledException([this.message = 'Transfer cancelled by user']);

  @override
  String toString() => message;
}

/// Progress callback for overall file transfer.
typedef TransferProgressCallback = void Function(
  int bytesTransferred,
  int totalBytes,
  double progress,
);

/// Top-level helper function for isolated AES-256-GCM chunk encryption.
/// Keeping this at top-level prevents closure capture of enclosing classes or callbacks
/// (such as TransferManager or SQLite database handles) when spawning in an Isolate.
Future<Uint8List> _encryptBufferInIsolate(
  Uint8List buffer,
  Uint8List masterKey,
  Uint8List iv,
) {
  return Isolate.run(() async {
    final encryptedPayload = await CryptoEngine.encrypt(
      plaintext: buffer,
      key: masterKey,
      customIv: iv,
    );
    return encryptedPayload.toCombinedBytes();
  });
}

/// Top-level helper function for isolated AES-256-GCM chunk decryption.
Future<Uint8List> _decryptBytesInIsolate(
  Uint8List combinedBytes,
  Uint8List masterKey,
) {
  return Isolate.run(() => CryptoEngine.decryptBytes(
    combinedBytes: combinedBytes,
    key: masterKey,
  ));
}

/// Handles chunking, on-the-fly streaming encryption, and reassembly.
class ChunkingEngine {
  final StorageBackend _storageBackend;
  final _uuid = const Uuid();

  ChunkingEngine({required StorageBackend storageBackend})
      : _storageBackend = storageBackend;

  /// Retries a network chunk operation with exponential backoff and Telegram FloodWait handling.
  /// Ensures uploads and downloads survive brief network interruptions or backgrounding.
  Future<T> _retryWithBackoff<T>(
    Future<T> Function() action, {
    int maxRetries = 5,
    String debugLabel = 'chunk-transfer',
    bool Function()? isCancelled,
  }) async {
    int attempt = 0;
    while (true) {
      if (isCancelled?.call() == true) {
        throw const TransferCancelledException();
      }
      attempt++;
      try {
        return await action();
      } catch (e) {
        if (e is TransferCancelledException || isCancelled?.call() == true) {
          if (e is TransferCancelledException) rethrow;
          throw const TransferCancelledException();
        }
        if (attempt >= maxRetries) {
          rethrow;
        }

        int delayMs = (800 * (1 << (attempt - 1))).clamp(800, 30000);
        final errText = e.toString();

        // Respect Telegram Flood Wait if returned
        if (errText.contains('FLOOD_WAIT_')) {
          final match = RegExp(r'FLOOD_WAIT_(\d+)').firstMatch(errText);
          if (match != null) {
            final seconds = int.tryParse(match.group(1)!) ?? 2;
            delayMs = (seconds + 1) * 1000;
          }
        }

        // Sleep in small increments so cancellation wakes up promptly during backoff
        int remainingMs = delayMs;
        while (remainingMs > 0) {
          if (isCancelled?.call() == true) {
            throw const TransferCancelledException();
          }
          final slice = remainingMs > 250 ? 250 : remainingMs;
          await Future<void>.delayed(Duration(milliseconds: slice));
          remainingMs -= slice;
        }
      }
    }
  }

  /// Uploads a file to Telegram.
  ///
  /// - For viewable spaces (`isEncrypted == false`): Uploads directly as a SINGLE complete file
  ///   with its authentic original filename to the `filo view` channel without chunking.
  /// - For encrypted spaces (`isEncrypted == true`): Encrypts chunks using AES-256-GCM
  ///   with high-performance adaptive chunk sizing (1-pass for files <= 16MB).
  Future<List<FileChunk>> uploadFile({
    required File file,
    required String nodeId,
    required Uint8List masterKey,
    required String channelId,
    String? customFileName,
    bool isEncrypted = true,
    int chunkSize = AppConfig.mtprotoChunkSize,
    TransferProgressCallback? onProgress,
  }) async {
    final fileSize = await file.length();
    final effectiveName = customFileName ?? p.basename(file.path);

    // 1. VIEWABLE SPACES: DIRECT SINGLE-FILE UPLOAD WITHOUT CHUNKING
    // In viewable spaces, users want their file saved whole in Telegram so they can
    // view photos, stream videos, or open documents directly inside Telegram.
    if (!isEncrypted) {
      final fileHash = await HashUtils.sha256Stream(file.openRead());
      final remoteChunk = await _retryWithBackoff(
        () => _storageBackend.uploadChunk(
          channelId: channelId,
          chunkData: Uint8List(0),
          sourceFile: file,
          partFileName: effectiveName,
          onProgress: (chunkBytes, chunkTotal) {
            if (onProgress != null && fileSize > 0) {
              onProgress(
                chunkBytes.clamp(0, fileSize),
                fileSize,
                (chunkBytes / fileSize).clamp(0.0, 1.0),
              );
            }
          },
        ),
        debugLabel: 'upload-viewable-$effectiveName',
      );

      final chunk = FileChunk(
        id: _uuid.v4(),
        nodeId: nodeId,
        chunkIndex: 0,
        remoteMessageId: remoteChunk.messageId,
        remoteFileId: remoteChunk.remoteFileId,
        sizeBytes: fileSize,
        sha256Hash: fileHash,
        ivHex: 'plain',
      );

      if (onProgress != null) {
        onProgress(fileSize, fileSize, 1.0);
      }

      return [chunk];
    }

    // 2. ENCRYPTED SPACES: SMART 3-TIER ADAPTIVE CHUNKING ARCHITECTURE
    // - Tier 1 (<= 32 MB): 1 single encrypted file ($nodeId.enc)
    //   Zero chunk fragmentation, 1 Telegram message, 0 rate limit flood, instant AES decryption.
    // - Tier 2 (32 MB to 128 MB): 32 MB chunks
    //   Low message count (e.g. 64 MB = 2 chunks), maximum MTProto throughput.
    // - Tier 3 (> 128 MB): 32 MB chunks
    //   Rock-solid resumability on spotty mobile data; chunk 0 enables instant video streaming.
    final effectiveChunkSize = (chunkSize != AppConfig.mtprotoChunkSize)
        ? chunkSize
        : (fileSize <= 32 * 1024 * 1024
            ? (fileSize > 0 ? fileSize : 1024 * 1024)
            : (fileSize <= 128 * 1024 * 1024
                ? 32 * 1024 * 1024
                : 32 * 1024 * 1024));

    final chunks = <FileChunk>[];
    int bytesProcessed = 0;
    int chunkIndex = 0;

    final randomAccessFile = await file.open(mode: FileMode.read);

    try {
      while (bytesProcessed < fileSize) {
        final remaining = fileSize - bytesProcessed;
        final currentChunkSize = remaining < effectiveChunkSize ? remaining : effectiveChunkSize;

        // Read chunk directly into buffer
        final buffer = Uint8List(currentChunkSize);
        await randomAccessFile.readInto(buffer);

        // Encrypt in background isolate for smooth 60fps UI
        final iv = CryptoEngine.generateIv();
        final chunkPayload = await _encryptBufferInIsolate(buffer, masterKey, iv);
        final ivHex = HashUtils.bytesToHex(iv);
        final partFileName = (fileSize <= effectiveChunkSize && chunkIndex == 0)
            ? '$nodeId.enc'
            : '${nodeId}_part$chunkIndex.enc';

        final chunkHash = HashUtils.sha256Hex(chunkPayload);

        // Upload chunk to Telegram channel with streaming progress
        final remoteChunk = await _retryWithBackoff(
          () => _storageBackend.uploadChunk(
            channelId: channelId,
            chunkData: chunkPayload,
            partFileName: partFileName,
            onProgress: (chunkBytes, chunkTotal) {
              if (onProgress != null && chunkTotal > 0) {
                final subChunk = bytesProcessed + (chunkBytes * currentChunkSize ~/ chunkTotal);
                onProgress(
                  subChunk.clamp(0, fileSize),
                  fileSize,
                  (subChunk / fileSize).clamp(0.0, 1.0),
                );
              }
            },
          ),
          debugLabel: 'upload-$partFileName',
        );

        final chunk = FileChunk(
          id: _uuid.v4(),
          nodeId: nodeId,
          chunkIndex: chunkIndex,
          remoteMessageId: remoteChunk.messageId,
          remoteFileId: remoteChunk.remoteFileId,
          sizeBytes: currentChunkSize,
          sha256Hash: chunkHash,
          ivHex: ivHex,
        );
        chunks.add(chunk);

        bytesProcessed += currentChunkSize;
        chunkIndex++;

        if (onProgress != null) {
          onProgress(
            bytesProcessed,
            fileSize,
            (bytesProcessed / fileSize).clamp(0.0, 1.0),
          );
        }
      }
    } finally {
      await randomAccessFile.close();
    }

    return chunks;
  }

  /// Downloads and decrypts all chunks of a file, writing plaintext directly to destination.
  Future<void> downloadAndDecryptFile({
    required List<FileChunk> chunks,
    required File destinationFile,
    required Uint8List masterKey,
    required String channelId,
    TransferProgressCallback? onProgress,
    bool deleteRemoteCache = false,
    bool Function()? isCancelled,
    int maxRetries = 5,
  }) async {
    if (!destinationFile.parent.existsSync()) {
      destinationFile.parent.createSync(recursive: true);
    }

    final sortedChunks = List<FileChunk>.from(chunks)
      ..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));

    final totalBytes = sortedChunks.fold<int>(0, (sum, c) => sum + c.sizeBytes);

    // Fast path: Single unencrypted file (viewable space) streams directly to disk
    // without loading multi-GB files into RAM.
    if (sortedChunks.length == 1 && sortedChunks.first.ivHex == 'plain') {
      final c = sortedChunks.first;
      await _retryWithBackoff(
        () async {
          if (isCancelled?.call() == true) {
            throw const TransferCancelledException();
          }
          await _storageBackend.downloadChunkToFile(
            channelId: channelId,
            remoteFileId: c.remoteFileId,
            destinationFile: destinationFile,
            deleteRemoteCache: deleteRemoteCache,
            onProgress: (chunkBytes, chunkTotal) {
              if (onProgress != null) {
                final effectiveTotal = totalBytes > 0 ? totalBytes : chunkTotal;
                final progress = effectiveTotal > 0
                    ? (chunkBytes / effectiveTotal).clamp(0.0, 1.0)
                    : 1.0;
                onProgress(
                  effectiveTotal > 0 ? chunkBytes.clamp(0, effectiveTotal) : chunkBytes,
                  effectiveTotal,
                  progress,
                );
              }
            },
          );
          if (c.sha256Hash.isNotEmpty) {
            final downloadedHash = await HashUtils.sha256Stream(destinationFile.openRead());
            if (downloadedHash != c.sha256Hash) {
              throw Exception(
                'Chunk integrity verification failed for part ${c.chunkIndex}. '
                'Expected ${c.sha256Hash}, got $downloadedHash',
              );
            }
          }
        },
        maxRetries: maxRetries,
        debugLabel: 'download-viewable-direct',
        isCancelled: isCancelled,
      );
      onProgress?.call(totalBytes, totalBytes, 1.0);
      return;
    }

    int bytesDownloaded = 0;
    final tempChunkFile = File('${destinationFile.path}.chunk.tmp');
    final outputSink = destinationFile.openWrite();
    var sinkClosed = false;
    var succeeded = false;

    try {
      for (final chunk in sortedChunks) {
        if (isCancelled?.call() == true) {
          throw const TransferCancelledException();
        }

        // 1. Download chunk to disk with resilient retry and verify integrity
        await _retryWithBackoff(
          () async {
            if (isCancelled?.call() == true) {
              throw const TransferCancelledException();
            }
            await _storageBackend.downloadChunkToFile(
              channelId: channelId,
              remoteFileId: chunk.remoteFileId,
              destinationFile: tempChunkFile,
              deleteRemoteCache: deleteRemoteCache,
              onProgress: (chunkBytes, chunkTotal) {
                if (onProgress != null && totalBytes > 0) {
                  final effectiveChunk = chunkTotal > 0
                      ? (chunkBytes * chunk.sizeBytes ~/ chunkTotal)
                      : chunkBytes;
                  final overall = (bytesDownloaded + effectiveChunk).clamp(0, totalBytes);
                  onProgress(
                    overall,
                    totalBytes,
                    (overall / totalBytes).clamp(0.0, 1.0),
                  );
                }
              },
            );

            final downloadedHash = await HashUtils.sha256Stream(tempChunkFile.openRead());
            if (downloadedHash != chunk.sha256Hash) {
              throw Exception(
                'Chunk integrity verification failed for part ${chunk.chunkIndex}. '
                'Expected ${chunk.sha256Hash}, got $downloadedHash',
              );
            }
          },
          maxRetries: maxRetries,
          debugLabel: 'download-chunk-${chunk.chunkIndex}',
          isCancelled: isCancelled,
        );

        if (isCancelled?.call() == true) {
          throw const TransferCancelledException();
        }

        // 2. Decrypt or stream plaintext chunk to output file and flush immediately
        // so IOSink does not buffer multiple chunks in RAM.
        if (chunk.ivHex == 'plain') {
          await outputSink.addStream(tempChunkFile.openRead());
        } else {
          final cipherBytes = await tempChunkFile.readAsBytes();
          final plaintext = await _decryptBytesInIsolate(cipherBytes, masterKey);
          outputSink.add(plaintext);
        }
        await outputSink.flush();

        if (tempChunkFile.existsSync()) {
          try {
            tempChunkFile.deleteSync();
          } catch (_) {}
        }

        bytesDownloaded += chunk.sizeBytes;
        if (onProgress != null) {
          final progress = totalBytes > 0
              ? (bytesDownloaded / totalBytes).clamp(0.0, 1.0)
              : 1.0;
          onProgress(bytesDownloaded, totalBytes, progress);
        }
      }

      await outputSink.close();
      sinkClosed = true;
      succeeded = true;
    } finally {
      if (!sinkClosed) {
        try {
          await outputSink.close();
        } catch (_) {
          // Ignore sink close failure during cleanup
        }
      }
      if (tempChunkFile.existsSync()) {
        try {
          tempChunkFile.deleteSync();
        } catch (_) {
          // Best-effort temp chunk cleanup
        }
      }
      if (!succeeded && destinationFile.existsSync()) {
        try {
          destinationFile.deleteSync();
        } catch (_) {
          // Best-effort partial destination cleanup
        }
      }
    }
  }

  /// Decrypts a single chunk in-memory (useful for on-demand media streaming).
  /// BUG 4 FIX: Integrity check added before decryption.
  Future<Uint8List> downloadAndDecryptSingleChunk({
    required FileChunk chunk,
    required Uint8List masterKey,
    required String channelId,
  }) async {
    final cipherBytes = await _retryWithBackoff(
      () => _storageBackend.downloadChunk(
        channelId: channelId,
        remoteFileId: chunk.remoteFileId,
      ),
      debugLabel: 'download-single-chunk-${chunk.chunkIndex}',
    );

    // BUG 4 FIX: Validate ciphertext integrity before decrypting
    final downloadedHash = HashUtils.sha256Hex(cipherBytes);
    if (downloadedHash != chunk.sha256Hash) {
      throw Exception(
        'Chunk integrity check failed for part ${chunk.chunkIndex}. '
        'Expected ${chunk.sha256Hash}, got $downloadedHash. '
        'Data may be corrupted or tampered.',
      );
    }

    if (chunk.ivHex == 'plain') {
      return cipherBytes;
    }

    return _decryptBytesInIsolate(cipherBytes, masterKey);
  }
}
