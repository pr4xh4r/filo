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

    final randomAccessFile = await file.open(mode: FileMode.read);

    try {
      while (bytesProcessed < fileSize) {
        final remaining = fileSize - bytesProcessed;
        final currentChunkSize = remaining < chunkSize ? remaining : chunkSize;

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

        // 3. Upload encrypted chunk to Telegram channel
        final remoteChunk = await _storageBackend.uploadChunk(
          channelId: channelId,
          chunkData: combinedBytes,
          partFileName: partFileName,
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
        // 1. Download ciphertext chunk
        final cipherBytes = await _storageBackend.downloadChunk(
          channelId: channelId,
          remoteFileId: chunk.remoteFileId,
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
  Future<Uint8List> downloadAndDecryptSingleChunk({
    required FileChunk chunk,
    required Uint8List masterKey,
    required String channelId,
  }) async {
    final cipherBytes = await _storageBackend.downloadChunk(
      channelId: channelId,
      remoteFileId: chunk.remoteFileId,
    );

    return CryptoEngine.decryptBytes(
      combinedBytes: cipherBytes,
      key: masterKey,
    );
  }
}
