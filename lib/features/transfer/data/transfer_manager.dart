import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import '../../../core/config/app_config.dart';
import '../../../core/crypto/hash_utils.dart';
import '../../../core/database/node_model.dart';
import '../../../core/database/transfer_model.dart';
import '../../files/data/file_repository.dart';
import '../../storage/domain/storage_backend.dart';
import '../domain/chunking_engine.dart';

/// Manages active file transfers, queuing, duplicate detection, and sharing.
class TransferManager {
  final ChunkingEngine _chunkingEngine;
  final FileRepository _fileRepository;
  final StorageBackend _storageBackend;
  final _uuid = const Uuid();

  // Active tasks map: taskId -> TransferTask
  final Map<String, TransferTask> _tasks = {};
  final StreamController<List<TransferTask>> _taskStreamController =
      StreamController<List<TransferTask>>.broadcast();

  TransferManager({
    required StorageBackend storageBackend,
    required FileRepository fileRepository,
  })  : _storageBackend = storageBackend,
        _fileRepository = fileRepository,
        _chunkingEngine = ChunkingEngine(storageBackend: storageBackend);

  Stream<List<TransferTask>> get tasksStream => _taskStreamController.stream;
  List<TransferTask> get currentTasks => _tasks.values.toList();

  /// Picks a file from device and uploads it to the vault.
  Future<FileNode?> pickAndUploadFile({
    required Uint8List masterKey,
    String? parentId,
    void Function(FileNode node)? onTaskCreated,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withReadStream: false,
    );

    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.first;
    if (picked.path == null) return null;

    final file = File(picked.path!);
    return uploadLocalFile(
      file: file,
      masterKey: masterKey,
      parentId: parentId,
      customName: picked.name,
      onTaskCreated: onTaskCreated,
    );
  }

  /// Uploads a local file with duplicate detection and chunked encryption.
  Future<FileNode> uploadLocalFile({
    required File file,
    required Uint8List masterKey,
    String? parentId,
    String? customName,
    void Function(FileNode node)? onTaskCreated,
  }) async {
    final fileName = customName ?? p.basename(file.path);
    final fileSize = await file.length();
    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';

    // 1. Create Node in database immediately so it is visible in real time
    final node = await _fileRepository.createFileNode(
      name: fileName,
      sizeBytes: fileSize,
      parentId: parentId,
      mimeType: mimeType,
      contentHash: null,
    );

    // 2. Create Transfer Task in Queue immediately
    final taskId = _uuid.v4();
    final task = TransferTask(
      id: taskId,
      nodeId: node.id,
      fileName: fileName,
      type: TransferType.upload,
      status: TransferStatus.running,
      totalBytes: fileSize,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _tasks[taskId] = task;
    _notify();

    // Notify caller that task and node are live in database
    onTaskCreated?.call(node);

    // 3. Fast Duplicate detection: compute SHA-256 of plaintext
    final contentHash = await HashUtils.sha256Stream(file.openRead());
    final existingDuplicate = await _fileRepository.findDuplicateByHash(contentHash);

    if (existingDuplicate != null) {
      // Re-use chunks without re-uploading
      final existingChunks = await _fileRepository.getChunksForNode(existingDuplicate.id);
      await _fileRepository.saveFileChunks(existingChunks.map((c) => c).toList());

      _tasks[taskId] = _tasks[taskId]!.copyWith(
        status: TransferStatus.completed,
        progress: 1.0,
        bytesTransferred: fileSize,
        updatedAt: DateTime.now(),
      );
      _notify();

      return node;
    }

    // 4. Execute Chunked Upload
    try {
      final channelInfo = await _storageBackend.getOrCreateVaultChannel(AppConfig.vaultChannelTitle);

      final chunks = await _chunkingEngine.uploadFile(
        file: file,
        nodeId: node.id,
        masterKey: masterKey,
        channelId: channelInfo.channelId,
        onProgress: (bytes, total, progress) {
          _tasks[taskId] = _tasks[taskId]!.copyWith(
            bytesTransferred: bytes,
            progress: progress,
            updatedAt: DateTime.now(),
          );
          _notify();
        },
      );

      // Save chunks to SQLite
      await _fileRepository.saveFileChunks(chunks);

      _tasks[taskId] = _tasks[taskId]!.copyWith(
        status: TransferStatus.completed,
        progress: 1.0,
        bytesTransferred: fileSize,
        updatedAt: DateTime.now(),
      );
      _notify();

      return node;
    } catch (e) {
      _tasks[taskId] = _tasks[taskId]!.copyWith(
        status: TransferStatus.failed,
        errorMessage: e.toString(),
        updatedAt: DateTime.now(),
      );
      _notify();
      rethrow;
    }
  }

  /// Downloads and decrypts a file to a temporary location for sharing via the system share sheet.
  Future<void> shareDecryptedCopy(FileNode node, Uint8List masterKey) async {
    final taskId = _uuid.v4();
    final task = TransferTask(
      id: taskId,
      nodeId: node.id,
      fileName: node.name,
      type: TransferType.download,
      status: TransferStatus.running,
      totalBytes: node.sizeBytes,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _tasks[taskId] = task;
    _notify();

    final tempDir = await getTemporaryDirectory();
    final decryptedPath = p.join(tempDir.path, 'filo_share_${node.name}');
    final decryptedFile = File(decryptedPath);

    try {
      final chunks = await _fileRepository.getChunksForNode(node.id);
      final channelInfo = await _storageBackend.getOrCreateVaultChannel(AppConfig.vaultChannelTitle);

      await _chunkingEngine.downloadAndDecryptFile(
        chunks: chunks,
        destinationFile: decryptedFile,
        masterKey: masterKey,
        channelId: channelInfo.channelId,
        onProgress: (bytes, total, progress) {
          _tasks[taskId] = _tasks[taskId]!.copyWith(
            bytesTransferred: bytes,
            progress: progress,
            updatedAt: DateTime.now(),
          );
          _notify();
        },
      );

      _tasks[taskId] = _tasks[taskId]!.copyWith(
        status: TransferStatus.completed,
        progress: 1.0,
        bytesTransferred: node.sizeBytes,
        updatedAt: DateTime.now(),
      );
      _notify();

      // Share via OS share sheet
      await Share.shareXFiles(
        [XFile(decryptedFile.path)],
        text: node.name,
      );
    } catch (e) {
      _tasks[taskId] = _tasks[taskId]!.copyWith(
        status: TransferStatus.failed,
        errorMessage: e.toString(),
        updatedAt: DateTime.now(),
      );
      _notify();
      rethrow;
    } finally {
      // Security rule: Delete decrypted temp file after sharing
      if (decryptedFile.existsSync()) {
        try {
          decryptedFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Downloads and decrypts a file directly to the device storage.
  Future<File> downloadFileToDevice(FileNode node, Uint8List masterKey) async {
    final taskId = _uuid.v4();
    final task = TransferTask(
      id: taskId,
      nodeId: node.id,
      fileName: node.name,
      type: TransferType.download,
      status: TransferStatus.running,
      totalBytes: node.sizeBytes,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    _tasks[taskId] = task;
    _notify();

    try {
      Directory? targetDir;
      if (Platform.isAndroid) {
        final downloadDir = Directory('/storage/emulated/0/Download');
        if (downloadDir.existsSync()) {
          targetDir = downloadDir;
        }
      }
      targetDir ??= await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();

      final targetFile = File(p.join(targetDir.path, node.name));
      final chunks = await _fileRepository.getChunksForNode(node.id);
      final channelInfo = await _storageBackend.getOrCreateVaultChannel(AppConfig.vaultChannelTitle);

      await _chunkingEngine.downloadAndDecryptFile(
        chunks: chunks,
        destinationFile: targetFile,
        masterKey: masterKey,
        channelId: channelInfo.channelId,
        onProgress: (bytes, total, progress) {
          _tasks[taskId] = _tasks[taskId]!.copyWith(
            bytesTransferred: bytes,
            progress: progress,
            updatedAt: DateTime.now(),
          );
          _notify();
        },
      );

      _tasks[taskId] = _tasks[taskId]!.copyWith(
        status: TransferStatus.completed,
        progress: 1.0,
        bytesTransferred: node.sizeBytes,
        updatedAt: DateTime.now(),
      );
      _notify();

      return targetFile;
    } catch (e) {
      _tasks[taskId] = _tasks[taskId]!.copyWith(
        status: TransferStatus.failed,
        errorMessage: e.toString(),
        updatedAt: DateTime.now(),
      );
      _notify();
      rethrow;
    }
  }

  void _notify() {
    _taskStreamController.add(currentTasks);
  }
}
