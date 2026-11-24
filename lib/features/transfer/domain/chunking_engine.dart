import 'dart:io';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';
import '../../../core/config/app_config.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/crypto/hash_utils.dart';
import '../../../core/database/chunk_model.dart';
import '../../storage/domain/storage_backend.dart';

/// Progress callback for overall file transfer.
typedef TransferProgressCallback = void Function(
  int bytesTransferred,
  int totalBytes,
  double progress,
);

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
    int maxRetries = 4,
    String debugLabel = 'chunk-transfer',
  }) async {
    int attempt = 0;
    while (true) {
      attempt++;
      try {
        return await action();
      } catch (e) {
        if (attempt >= maxRetries) {
          rethrow;
        }

        int delayMs = 800 * (1 << (attempt - 1)); // 800ms, 1600ms, 3200ms
        final errText = e.toString();

        // Respect Telegram Flood Wait if returned
        if (errText.contains('FLOOD_WAIT_')) {
          final match = RegExp(r'FLOOD_WAIT_(\d+)').firstMatch(errText);
          if (match != null) {
            final seconds = int.tryParse(match.group(1)!) ?? 2;
            delayMs = seconds * 1000;
          }
        }

        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }
  }

  /// Uploads a file with chunked AES-256-GCM encryption.
  /// Handles files of any size (including files > 1 GB) with memory safety.
  Future<List<FileChunk>> uploadFile({
    required File file,
    required String nodeId,
    required Uint8List masterKey,
    required String channelId,
    int chunkSize = AppConfig.mtprotoChunkSize,
    TransferProgressCallback? onProgress,
  }) async {
    final fileSize = await file.length();
    final chunks = <FileChunk>[];
    int bytesProcessed = 0;
    int chunkIndex = 0;

    // Adaptive chunk sizing for responsive, real-time transfers
    final effectiveChunkSize = (chunkSize != AppConfig.mtprotoChunkSize)
        ? chunkSize
        : (fileSize <= 4 * 1024 * 1024
            ? 512 * 1024 // 512 KB
            : (fileSize <= 32 * 1024 * 1024
                ? 2 * 1024 * 1024 // 2 MB
                : 8 * 1024 * 1024)); // 8 MB

    final randomAccessFile = await file.open(mode: FileMode.read);

    try {
      while (bytesProcessed < fileSize) {
        final remaining = fileSize - bytesProcessed;
        final currentChunkSize = remaining < effectiveChunkSize ? remaining : effectiveChunkSize;

        // 1. Read chunk directly into buffer
        final buffer = Uint8List(currentChunkSize);
        await randomAccessFile.readInto(buffer);

        // 2. Encrypt chunk on-device with Master Key
        final iv = CryptoEngine.generateIv();
        final encryptedPayload = await CryptoEngine.encrypt(
          plaintext: buffer,
          key: masterKey,
          customIv: iv,
        );

        final combinedBytes = encryptedPayload.toCombinedBytes();
        final chunkHash = HashUtils.sha256Hex(combinedBytes);
        final partFileName = '${nodeId}_part$chunkIndex.enc';

        // 3. Upload encrypted chunk to Telegram channel with streaming progress and resilience
        final remoteChunk = await _retryWithBackoff(
          () => _storageBackend.uploadChunk(
            channelId: channelId,
            chunkData: combinedBytes,
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

        // 4. Record chunk metadata
        final chunk = FileChunk(
          id: _uuid.v4(),
          nodeId: nodeId,
          chunkIndex: chunkIndex,
          remoteMessageId: remoteChunk.messageId,
          remoteFileId: remoteChunk.remoteFileId,
          sizeBytes: currentChunkSize,
          sha256Hash: chunkHash,
          ivHex: HashUtils.bytesToHex(iv),
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
  }) async {
    if (!destinationFile.parent.existsSync()) {
      destinationFile.parent.createSync(recursive: true);
    }

    final sortedChunks = List<FileChunk>.from(chunks)
      ..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));

    final totalBytes = sortedChunks.fold<int>(0, (sum, c) => sum + c.sizeBytes);
    int bytesDownloaded = 0;

    final outputSink = destinationFile.openWrite();

    try {
      for (final chunk in sortedChunks) {
        // 1. Download ciphertext chunk with resilient retry
        final cipherBytes = await _retryWithBackoff(
          () => _storageBackend.downloadChunk(
            channelId: channelId,
            remoteFileId: chunk.remoteFileId,
          ),
          debugLabel: 'download-chunk-${chunk.chunkIndex}',
        );

        // 2. Validate ciphertext integrity hash
        final downloadedHash = HashUtils.sha256Hex(cipherBytes);
        if (downloadedHash != chunk.sha256Hash) {
          throw Exception(
            'Chunk integrity verification failed for part ${chunk.chunkIndex}. '
            'Expected ${chunk.sha256Hash}, got $downloadedHash',
          );
        }

        // 3. Decrypt on-device with Master Key
        final plaintext = await CryptoEngine.decryptBytes(
          combinedBytes: cipherBytes,
          key: masterKey,
        );

        outputSink.add(plaintext);
        bytesDownloaded += chunk.sizeBytes;

        if (onProgress != null) {
          onProgress(
            bytesDownloaded,
            totalBytes,
            (bytesDownloaded / totalBytes).clamp(0.0, 1.0),
          );
        }
      }
    } finally {
      await outputSink.flush();
      await outputSink.close();
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

    return CryptoEngine.decryptBytes(
      combinedBytes: cipherBytes,
      key: masterKey,
    );
  }
}
