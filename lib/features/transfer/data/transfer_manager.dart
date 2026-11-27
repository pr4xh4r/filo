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
import '../../../core/database/chunk_model.dart';
import '../../../core/database/node_model.dart';
import '../../../core/database/transfer_model.dart';
import '../../files/data/file_repository.dart';
import '../../files/domain/workspace.dart';
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

  /// Picks one or more files from device and uploads them sequentially to the vault,
  /// honoring Telegram channel rate limits (FloodWait handling) and chunk size boundaries.
  Future<List<FileNode>> pickAndUploadFiles({
    required Uint8List masterKey,
    String? parentId,
    String workspaceId = 'personal',
    List<String> tags = const [],
    bool? isEncrypted,
    void Function(FileNode node)? onTaskCreated,
    void Function(FileNode node)? onFileUploaded,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withReadStream: false,
    );

    if (result == null || result.files.isEmpty) return [];

    final uploadedNodes = <FileNode>[];

    for (final picked in result.files) {
      if (picked.path == null) continue;
      final file = File(picked.path!);
      if (!file.existsSync()) continue;

      try {
        final node = await uploadLocalFile(
          file: file,
          masterKey: masterKey,
          parentId: parentId,
          workspaceId: workspaceId,
          tags: tags,
          customName: picked.name,
          isEncrypted: isEncrypted,
          onTaskCreated: onTaskCreated,
        );
        uploadedNodes.add(node);
        onFileUploaded?.call(node);

        // Telegram channel rate limiting pacing:
        // Add 350ms delay between consecutive files to stay well within
        // Telegram's ~20-30 messages/minute broadcast rate limits.
        await Future.delayed(const Duration(milliseconds: 350));
      } catch (e) {
        // If Telegram API returns FLOOD_WAIT_X, honor the cooldown and retry once
        if (e.toString().contains('FLOOD_WAIT_')) {
          final match = RegExp(r'FLOOD_WAIT_(\d+)').firstMatch(e.toString());
          final waitSeconds = match != null ? int.parse(match.group(1)!) : 10;
          await Future.delayed(Duration(seconds: waitSeconds + 1));
          try {
            final node = await uploadLocalFile(
              file: file,
              masterKey: masterKey,
              parentId: parentId,
              workspaceId: workspaceId,
              tags: tags,
              customName: picked.name,
              isEncrypted: isEncrypted,
              onTaskCreated: onTaskCreated,
            );
            uploadedNodes.add(node);
            onFileUploaded?.call(node);
          } catch (_) {
            // Failed after retry
          }
        }
      }
    }

    return uploadedNodes;
  }

  /// Picks a single or multiple files from device and uploads to the vault.
  Future<FileNode?> pickAndUploadFile({
    required Uint8List masterKey,
    String? parentId,
    String workspaceId = 'personal',
    List<String> tags = const [],
    bool? isEncrypted,
    void Function(FileNode node)? onTaskCreated,
  }) async {
    final nodes = await pickAndUploadFiles(
      masterKey: masterKey,
      parentId: parentId,
      workspaceId: workspaceId,
      tags: tags,
      isEncrypted: isEncrypted,
      onTaskCreated: onTaskCreated,
    );
    return nodes.isNotEmpty ? nodes.first : null;
  }

  /// Uploads a local file with duplicate detection and chunked encryption.
  Future<FileNode> uploadLocalFile({
    required File file,
    required Uint8List masterKey,
    String? parentId,
    String workspaceId = 'personal',
    List<String> tags = const [],
    String? customName,
    bool? isEncrypted,
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
      workspaceId: workspaceId,
      tags: tags,
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
      // BUG 3 FIX: Re-link chunks to the NEW node id, not the old duplicate's id.
      final existingChunks =
          await _fileRepository.getChunksForNode(existingDuplicate.id);
      final relinkedChunks = existingChunks
          .map((c) => FileChunk(
                id: _uuid.v4(),
                nodeId: node.id, // ← correct node id
                chunkIndex: c.chunkIndex,
                remoteMessageId: c.remoteMessageId,
                remoteFileId: c.remoteFileId,
                sizeBytes: c.sizeBytes,
                sha256Hash: c.sha256Hash,
                ivHex: c.ivHex,
              ))
          .toList();
      await _fileRepository.saveFileChunks(relinkedChunks);
      // Also record the content hash and mark node synced
      await _fileRepository.updateNodeHash(node.id, contentHash);
      await _fileRepository.markNodeSynced(node.id);

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
      // Determine encryption setting
      bool effectiveIsEncrypted = true;
      if (isEncrypted != null) {
        effectiveIsEncrypted = isEncrypted;
      } else {
        try {
          final workspaces = await _fileRepository.getWorkspaces();
          final ws = workspaces.firstWhere(
            (w) => w.id == workspaceId,
            orElse: () => Workspace.fromId(workspaceId, workspaces),
          );
          effectiveIsEncrypted = ws.isEncrypted;
        } catch (_) {
          effectiveIsEncrypted = true;
        }
      }

      final channelTitle = AppConfig.getChannelTitle(isEncrypted: effectiveIsEncrypted);
      final channelInfo = await _storageBackend.getOrCreateVaultChannel(channelTitle);

      final chunks = await _chunkingEngine.uploadFile(
        file: file,
        nodeId: node.id,
        masterKey: masterKey,
        channelId: channelInfo.channelId,
        customFileName: fileName,
        isEncrypted: effectiveIsEncrypted,
        onProgress: (bytes, total, progress) {
          _tasks[taskId] = _tasks[taskId]!.copyWith(
            bytesTransferred: bytes,
            progress: progress,
            updatedAt: DateTime.now(),
          );
          _notify(immediate: false);
        },
      );

      // Save chunks to SQLite and mark node synced
      await _fileRepository.saveFileChunks(chunks);
      await _fileRepository.markNodeSynced(node.id);

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

    final safeName = FileNode.sanitizeNodeName(node.name);
    final tempDir = await getTemporaryDirectory();
    final decryptedPath = p.normalize(p.join(tempDir.path, 'filo_share_$safeName'));
    if (!p.isWithin(tempDir.path, decryptedPath)) {
      throw ArgumentError('Invalid node name path traversal: ${node.name}');
    }
    final decryptedFile = File(decryptedPath);

    try {
      final offlineFile = await _fileRepository.getOfflineFile(node.id);
      if (offlineFile != null && offlineFile.existsSync() && offlineFile.lengthSync() > 0) {
        await offlineFile.copy(decryptedFile.path);
      } else {
        final chunks = await _fileRepository.getChunksForNode(node.id);
        final workspaces = await _fileRepository.getWorkspaces();
        final ws = workspaces.firstWhere(
          (w) => w.id == node.workspaceId,
          orElse: () => Workspace.fromId(node.workspaceId, workspaces),
        );
        final channelTitle = AppConfig.getChannelTitle(isEncrypted: ws.isEncrypted);
        final channelInfo = await _storageBackend.getOrCreateVaultChannel(channelTitle);

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
            _notify(immediate: false);
          },
        );
      }

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

      final safeName = FileNode.sanitizeNodeName(node.name);
      final targetPath = p.normalize(p.join(targetDir.path, safeName));
      if (!p.isWithin(targetDir.path, targetPath)) {
        throw ArgumentError('Invalid destination path traversal: ${node.name}');
      }
      final targetFile = File(targetPath);
      final offlineFile = await _fileRepository.getOfflineFile(node.id);
      if (offlineFile != null && offlineFile.existsSync() && offlineFile.lengthSync() > 0) {
        await offlineFile.copy(targetFile.path);
      } else {
        final chunks = await _fileRepository.getChunksForNode(node.id);
        final workspaces = await _fileRepository.getWorkspaces();
        final ws = workspaces.firstWhere(
          (w) => w.id == node.workspaceId,
          orElse: () => Workspace.fromId(node.workspaceId, workspaces),
        );
        final channelTitle = AppConfig.getChannelTitle(isEncrypted: ws.isEncrypted);
        final channelInfo = await _storageBackend.getOrCreateVaultChannel(channelTitle);

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
            _notify(immediate: false);
          },
        );
      }

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

  /// Inserts or updates a task managed by an external orchestrator (e.g. VaultExportService)
  /// so background keep-alive, auto-lock suppression, and transfer UI stay synchronized.
  void upsertExternalTask(TransferTask task) {
    _tasks[task.id] = task;
    _notify(immediate: task.status != TransferStatus.running);
  }

  /// Removes a completed/cancelled external task from the in-memory queue if needed.
  void removeExternalTask(String taskId) {
    if (_tasks.remove(taskId) != null) {
      _notify(immediate: true);
    }
  }

  DateTime _lastNotifyTime = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _throttleTimer;

  void _notify({bool immediate = true}) {
    if (_taskStreamController.isClosed) return;
    final now = DateTime.now();
    if (immediate || now.difference(_lastNotifyTime).inMilliseconds >= 120) {
      _lastNotifyTime = now;
      _throttleTimer?.cancel();
      _throttleTimer = null;
      _taskStreamController.add(currentTasks);
    } else {
      _throttleTimer ??= Timer(const Duration(milliseconds: 120), () {
        if (_taskStreamController.isClosed) return;
        _lastNotifyTime = DateTime.now();
        _throttleTimer = null;
        _taskStreamController.add(currentTasks);
      });
    }
  }

  /// BUG 28 FIX: Dispose the StreamController to prevent resource leaks.
  void dispose() {
    _throttleTimer?.cancel();
    _throttleTimer = null;
    _taskStreamController.close();
  }
}
