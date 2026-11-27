import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/cache/session_cache_service.dart';
import '../../../core/config/app_config.dart';
import '../../../core/database/chunk_model.dart';
import '../../../core/database/node_model.dart';
import '../../../core/database/transfer_model.dart';
import '../../files/data/file_repository.dart';
import '../../files/domain/workspace.dart';
import '../../storage/domain/storage_backend.dart';
import '../../storage/domain/storage_models.dart';
import '../data/transfer_manager.dart';
import 'chunking_engine.dart';
import 'streaming_zip_writer.dart';

const _transferChannel = MethodChannel('com.filo.vault.filo/transfers');

/// Top-level helper for isolated ZIP file append to prevent capturing
/// enclosing service instances (DB handles / StreamControllers) in the Isolate.
Future<StreamingZipEntry> _appendFileToZipInIsolate({
  required String archivePartPath,
  required int offset,
  required String nodeId,
  required String entryName,
  String? sourceFilePath,
  required DateTime modifiedAt,
}) {
  return Isolate.run(
    () => StreamingZipWriter.appendFile(
      archivePartPath: archivePartPath,
      offset: offset,
      nodeId: nodeId,
      entryName: entryName,
      sourceFilePath: sourceFilePath,
      modifiedAt: modifiedAt,
    ),
  );
}

/// Top-level helper for isolated ZIP Central Directory finalization.
Future<void> _finalizeZipInIsolate({
  required String archivePartPath,
  required List<StreamingZipEntry> entries,
  required int centralDirectoryOffset,
  required String comment,
}) {
  return Isolate.run(
    () => StreamingZipWriter.finalize(
      archivePartPath: archivePartPath,
      entries: entries,
      centralDirectoryOffset: centralDirectoryOffset,
      comment: comment,
    ),
  );
}

/// High-level lifecycle status of a full-vault export job.
enum VaultExportStatus {
  idle,
  preparing,
  running,
  paused,
  partialNeedsAction,
  finalizing,
  completed,
  failed,
}

/// Captures a per-file failure without silently dropping data.
class ExportFileFailure {
  final String nodeId;
  final String fileName;
  final String zipEntryName;
  final String error;

  const ExportFileFailure({
    required this.nodeId,
    required this.fileName,
    required this.zipEntryName,
    required this.error,
  });

  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'fileName': fileName,
        'zipEntryName': zipEntryName,
        'error': error,
      };

  factory ExportFileFailure.fromJson(Map<String, dynamic> json) {
    return ExportFileFailure(
      nodeId: json['nodeId'] as String,
      fileName: json['fileName'] as String,
      zipEntryName: json['zipEntryName'] as String,
      error: json['error'] as String,
    );
  }
}

/// Persistent checkpoint written atomically after every completed ZIP entry.
class VaultExportCheckpoint {
  final int version;
  final String exportId;
  final String archivePartPath;
  final String finalZipFileName;
  final String? customDestinationDir;
  final int lastValidOffset;
  final int totalFiles;
  final int totalBytes;
  final int completedBytes;
  final List<StreamingZipEntry> completedEntries;
  final List<ExportFileFailure> failedFiles;
  final int updatedAtMillis;

  const VaultExportCheckpoint({
    this.version = 1,
    required this.exportId,
    required this.archivePartPath,
    required this.finalZipFileName,
    this.customDestinationDir,
    required this.lastValidOffset,
    required this.totalFiles,
    required this.totalBytes,
    required this.completedBytes,
    required this.completedEntries,
    this.failedFiles = const [],
    required this.updatedAtMillis,
  });

  int get completedFileCount => completedEntries.length;

  Map<String, dynamic> toJson() => {
        'version': version,
        'exportId': exportId,
        'archivePartPath': archivePartPath,
        'finalZipFileName': finalZipFileName,
        'customDestinationDir': customDestinationDir,
        'lastValidOffset': lastValidOffset,
        'totalFiles': totalFiles,
        'totalBytes': totalBytes,
        'completedBytes': completedBytes,
        'completedEntries': completedEntries.map((e) => e.toJson()).toList(),
        'failedFiles': failedFiles.map((e) => e.toJson()).toList(),
        'updatedAtMillis': updatedAtMillis,
      };

  factory VaultExportCheckpoint.fromJson(Map<String, dynamic> json) {
    final entriesRaw = json['completedEntries'] as List<dynamic>? ?? const [];
    final failuresRaw = json['failedFiles'] as List<dynamic>? ?? const [];
    return VaultExportCheckpoint(
      version: (json['version'] as num?)?.toInt() ?? 1,
      exportId: json['exportId'] as String,
      archivePartPath: json['archivePartPath'] as String,
      finalZipFileName: json['finalZipFileName'] as String,
      customDestinationDir: json['customDestinationDir'] as String?,
      lastValidOffset: (json['lastValidOffset'] as num).toInt(),
      totalFiles: (json['totalFiles'] as num).toInt(),
      totalBytes: (json['totalBytes'] as num).toInt(),
      completedBytes: (json['completedBytes'] as num).toInt(),
      completedEntries: entriesRaw
          .map((e) => StreamingZipEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      failedFiles: failuresRaw
          .map((e) => ExportFileFailure.fromJson(e as Map<String, dynamic>))
          .toList(),
      updatedAtMillis: (json['updatedAtMillis'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Immutable state snapshot exposed to UI and progress listeners.
class VaultExportState {
  final VaultExportStatus status;
  final int completedFiles;
  final int totalFiles;
  final int bytesTransferred;
  final int totalBytes;
  final String? currentFileName;
  final String? outputDisplayPath;
  final String? localShareableFilePath;
  final String? statusMessage;
  final String? errorMessage;
  final List<ExportFileFailure> failedFiles;
  final VaultExportCheckpoint? resumableCheckpoint;

  const VaultExportState({
    this.status = VaultExportStatus.idle,
    this.completedFiles = 0,
    this.totalFiles = 0,
    this.bytesTransferred = 0,
    this.totalBytes = 0,
    this.currentFileName,
    this.outputDisplayPath,
    this.localShareableFilePath,
    this.statusMessage,
    this.errorMessage,
    this.failedFiles = const [],
    this.resumableCheckpoint,
  });

  bool get isActive =>
      status == VaultExportStatus.preparing ||
      status == VaultExportStatus.running ||
      status == VaultExportStatus.finalizing;

  double get progress {
    if (totalBytes > 0) {
      return (bytesTransferred / totalBytes).clamp(0.0, 1.0);
    }
    if (totalFiles > 0) {
      return (completedFiles / totalFiles).clamp(0.0, 1.0);
    }
    return 0.0;
  }

  VaultExportState copyWith({
    VaultExportStatus? status,
    int? completedFiles,
    int? totalFiles,
    int? bytesTransferred,
    int? totalBytes,
    String? currentFileName,
    bool clearCurrentFileName = false,
    String? outputDisplayPath,
    bool clearOutputDisplayPath = false,
    String? localShareableFilePath,
    bool clearLocalShareableFilePath = false,
    String? statusMessage,
    bool clearStatusMessage = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    List<ExportFileFailure>? failedFiles,
    VaultExportCheckpoint? resumableCheckpoint,
    bool clearResumableCheckpoint = false,
  }) {
    return VaultExportState(
      status: status ?? this.status,
      completedFiles: completedFiles ?? this.completedFiles,
      totalFiles: totalFiles ?? this.totalFiles,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      totalBytes: totalBytes ?? this.totalBytes,
      currentFileName: clearCurrentFileName
          ? null
          : (currentFileName ?? this.currentFileName),
      outputDisplayPath: clearOutputDisplayPath
          ? null
          : (outputDisplayPath ?? this.outputDisplayPath),
      localShareableFilePath: clearLocalShareableFilePath
          ? null
          : (localShareableFilePath ?? this.localShareableFilePath),
      statusMessage: clearStatusMessage
          ? null
          : (statusMessage ?? this.statusMessage),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      failedFiles: failedFiles ?? this.failedFiles,
      resumableCheckpoint: clearResumableCheckpoint
          ? null
          : (resumableCheckpoint ?? this.resumableCheckpoint),
    );
  }
}

/// Platform storage adapter for export staging, free-space inspection, and final delivery.
/// Can be overridden in unit tests to run hermetic multi-file and crash/resume tests.
class ExportPlatformBridge {
  const ExportPlatformBridge();

  Future<Directory> getExportWorkingDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'filo_exports'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<int?> getAvailableStorageBytes(String path) async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final bytes = await _transferChannel.invokeMethod<int>(
          'getAvailableStorageBytes',
          {'path': path},
        );
        return bytes;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// Delivers the finalized ZIP archive to a user-accessible location.
  ///
  /// Returns `(displayPath, localShareablePath)`. On Android 10+, streams into
  /// `MediaStore.Downloads/Filo` and deletes the private staging file; on Desktop
  /// or iOS, moves directly into the destination folder without duplicating bytes.
  Future<({String displayPath, String? localShareablePath})> deliverArchive({
    required File finalizedPartFile,
    required String finalFileName,
    String? customDestinationDir,
  }) async {
    if (customDestinationDir != null && customDestinationDir.isNotEmpty) {
      final targetDir = Directory(customDestinationDir);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      final targetPath = p.join(targetDir.path, finalFileName);
      final moved = await _moveFile(finalizedPartFile, File(targetPath));
      return (displayPath: moved.path, localShareablePath: moved.path);
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final res = await _transferChannel.invokeMapMethod<String, dynamic>(
          'saveExportToDownloads',
          {
            'sourcePath': finalizedPartFile.path,
            'fileName': finalFileName,
            'mimeType': 'application/zip',
            'deleteSource': true,
          },
        );
        if (res != null && res['savedPath'] != null) {
          return (
            displayPath: res['savedPath'] as String,
            localShareablePath: null,
          );
        }
      } on MissingPluginException {
        // Fall through to app-local Exports directory in tests or older runners
      }
    }

    Directory? destDir;
    if (!kIsWeb && (Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      destDir = await getDownloadsDirectory();
    }
    destDir ??= Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'Exports'),
    );
    if (!await destDir.exists()) {
      await destDir.create(recursive: true);
    }
    final targetFile = File(p.join(destDir.path, finalFileName));
    final moved = await _moveFile(finalizedPartFile, targetFile);
    return (displayPath: moved.path, localShareablePath: moved.path);
  }

  Future<File> _moveFile(File src, File dst) async {
    if (p.canonicalize(src.path) == p.canonicalize(dst.path)) {
      return dst;
    }
    try {
      return await src.rename(dst.path);
    } on FileSystemException {
      // Cross-filesystem move: stream in chunks then securely delete source
      final sink = dst.openWrite();
      var sinkClosed = false;
      try {
        await sink.addStream(src.openRead());
        await sink.flush();
        await sink.close();
        sinkClosed = true;
      } catch (_) {
        if (!sinkClosed) {
          try {
            await sink.close();
          } catch (_) {
            // Ignore close error on rollback
          }
        }
        if (await dst.exists()) {
          try {
            await dst.delete();
          } catch (_) {
            // Best-effort rollback cleanup
          }
        }
        rethrow;
      }
      await SessionCacheService.secureDeleteFile(src);
      return dst;
    }
  }
}

class _PreparedExportItem {
  final FileNode node;
  final String zipEntryName;
  final List<FileChunk> chunks;
  final bool isEncryptedWorkspace;

  const _PreparedExportItem({
    required this.node,
    required this.zipEntryName,
    required this.chunks,
    required this.isEncryptedWorkspace,
  });
}

/// Resumable, constant-memory multi-GB vault export orchestrator.
///
/// Key guarantees:
/// - Streams chunks directly to disk (1 file staged at a time, deleted immediately
///   after appending to `.zip.part`), keeping peak RAM bounded to ~1 chunk.
/// - Integrates with [TransferManager] (`activeTransfersProvider`) so Android
///   foreground service (`FiloTransferService`) and auto-lock suppression stay active.
/// - Preloads decrypted path metadata and isolates a copy of [masterKey] so
///   even manual lock events cannot corrupt in-flight decryption or filenames.
/// - Persists atomic checkpoints after every completed file so interrupted exports
///   can resume seamlessly from the exact byte offset.
class VaultExportService {
  final FileRepository _fileRepository;
  final StorageBackend _storageBackend;
  final TransferManager _transferManager;
  final ChunkingEngine _chunkingEngine;
  final ExportPlatformBridge _platformBridge;
  final int _maxChunkRetries;
  final _uuid = const Uuid();

  static const String _checkpointFileName = 'export_checkpoint.json';

  bool _cancelRequested = false;
  bool _isRunning = false;

  VaultExportService({
    required FileRepository fileRepository,
    required StorageBackend storageBackend,
    required TransferManager transferManager,
    ChunkingEngine? chunkingEngine,
    ExportPlatformBridge? platformBridge,
    int maxChunkRetries = 5,
  })  : _fileRepository = fileRepository,
        _storageBackend = storageBackend,
        _transferManager = transferManager,
        _chunkingEngine =
            chunkingEngine ?? ChunkingEngine(storageBackend: storageBackend),
        _platformBridge = platformBridge ?? const ExportPlatformBridge(),
        _maxChunkRetries = maxChunkRetries;

  bool get isRunning => _isRunning;

  void requestCancel() {
    _cancelRequested = true;
  }

  /// Checks whether a valid resumable export checkpoint exists on disk.
  Future<VaultExportCheckpoint?> loadValidCheckpoint() async {
    try {
      final workDir = await _platformBridge.getExportWorkingDirectory();
      final checkpointFile = File(p.join(workDir.path, _checkpointFileName));
      if (!await checkpointFile.exists()) return null;

      final raw = await checkpointFile.readAsString();
      final cp = VaultExportCheckpoint.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );

      final partFile = File(cp.archivePartPath);
      if (!await partFile.exists()) {
        await checkpointFile.delete();
        return null;
      }
      final partLen = await partFile.length();
      if (partLen < cp.lastValidOffset) {
        await SessionCacheService.secureDeleteFile(partFile);
        await checkpointFile.delete();
        return null;
      }
      return cp;
    } catch (e) {
      debugPrint('[VaultExportService] Failed to load checkpoint: $e');
      return null;
    }
  }

  /// Securely deletes any unfinished export archive part and checkpoint.
  Future<void> discardCheckpoint() async {
    try {
      final workDir = await _platformBridge.getExportWorkingDirectory();
      final cpFile = File(p.join(workDir.path, _checkpointFileName));
      if (await cpFile.exists()) {
        try {
          final raw = await cpFile.readAsString();
          final cp = VaultExportCheckpoint.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          );
          final partFile = File(cp.archivePartPath);
          if (await partFile.exists()) {
            await SessionCacheService.secureDeleteFile(partFile);
          }
        } catch (_) {
          // Best-effort cleanup of corrupt checkpoint metadata
        }
        if (await cpFile.exists()) {
          await cpFile.delete();
        }
      }
      // Also clean any leftover staging or .part files in filo_exports
      if (await workDir.exists()) {
        await for (final entity in workDir.list(followLinks: false)) {
          if (entity is File) {
            final name = p.basename(entity.path);
            if (name.endsWith('.part') || name.endsWith('.tmp')) {
              await SessionCacheService.secureDeleteFile(entity);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[VaultExportService] Error discarding checkpoint: $e');
    }
  }

  /// Estimates total file count and byte size of the unlocked vault.
  Future<({int fileCount, int totalBytes})> estimateExportSize() async {
    final nodes = await _fileRepository.getNodes(searchQuery: '');
    final fileNodes = nodes.where((n) => n.isFile).toList();
    final totalBytes = fileNodes.fold<int>(0, (sum, n) => sum + n.sizeBytes);
    return (fileCount: fileNodes.length, totalBytes: totalBytes);
  }

  /// Queries available free bytes on the export working volume, if supported.
  Future<int?> getAvailableStorageBytes() async {
    final workDir = await _platformBridge.getExportWorkingDirectory();
    return _platformBridge.getAvailableStorageBytes(workDir.path);
  }

  /// Starts a fresh export or resumes from [resumeCheckpoint].
  ///
  /// When [finalizePartialOnly] is true alongside [resumeCheckpoint], skips
  /// retrying remaining/failed files and finalizes the already-written entries
  /// into the output ZIP archive.
  Future<VaultExportState> runExport({
    required Uint8List masterKey,
    VaultExportCheckpoint? resumeCheckpoint,
    String? customDestinationDir,
    bool finalizePartialOnly = false,
    bool runInIsolate = true,
    required void Function(VaultExportState state) onStateChanged,
  }) async {
    if (_isRunning) {
      throw StateError('An export is already in progress');
    }

    _isRunning = true;
    _cancelRequested = false;

    final exportKey = Uint8List.fromList(masterKey);
    final taskId = 'export_${_uuid.v4()}';
    final workDir = await _platformBridge.getExportWorkingDirectory();
    final checkpointFile = File(p.join(workDir.path, _checkpointFileName));
    final stagingFile = File(p.join(workDir.path, 'current_export_item.tmp'));

    void emitState(VaultExportState s) {
      onStateChanged(s);
    }

    void updateTransferTask({
      required TransferStatus status,
      required int bytesTransferred,
      required int totalBytes,
      required String label,
      String? errorMessage,
    }) {
      final now = DateTime.now();
      final progress =
          totalBytes > 0 ? (bytesTransferred / totalBytes).clamp(0.0, 1.0) : 0.0;
      _transferManager.upsertExternalTask(
        TransferTask(
          id: taskId,
          nodeId: 'vault_export',
          fileName: label,
          type: TransferType.download,
          status: status,
          progress: progress,
          bytesTransferred: bytesTransferred,
          totalBytes: totalBytes,
          errorMessage: errorMessage,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    try {
      emitState(const VaultExportState(
        status: VaultExportStatus.preparing,
        statusMessage: 'Indexing vault files...',
      ));

      final reservedLowerPaths = resumeCheckpoint != null
          ? resumeCheckpoint.completedEntries
              .map((e) => e.entryName.toLowerCase())
              .toSet()
          : <String>{};
      final prepared = await _prepareExportItems(
        completedNodeIds: resumeCheckpoint != null
            ? resumeCheckpoint.completedEntries.map((e) => e.nodeId).toSet()
            : const <String>{},
        reservedLowerPaths: reservedLowerPaths,
      );
      if (prepared.isEmpty && resumeCheckpoint == null) {
        const emptyState = VaultExportState(
          status: VaultExportStatus.failed,
          errorMessage: 'No files to export in vault',
        );
        emitState(emptyState);
        return emptyState;
      }

      // Initialize or restore checkpoint state
      final String exportId;
      final String archivePartPath;
      final String finalZipFileName;
      final String? effectiveCustomDir;
      int lastValidOffset;
      final List<StreamingZipEntry> completedEntries;
      final List<ExportFileFailure> failedFiles = [];

      if (resumeCheckpoint != null) {
        exportId = resumeCheckpoint.exportId;
        archivePartPath = resumeCheckpoint.archivePartPath;
        finalZipFileName = resumeCheckpoint.finalZipFileName;
        effectiveCustomDir =
            customDestinationDir ?? resumeCheckpoint.customDestinationDir;
        lastValidOffset = resumeCheckpoint.lastValidOffset;
        completedEntries = List<StreamingZipEntry>.from(
          resumeCheckpoint.completedEntries,
        );
        if (finalizePartialOnly) {
          failedFiles.addAll(resumeCheckpoint.failedFiles);
        }
      } else {
        await discardCheckpoint();
        exportId = _uuid.v4();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        finalZipFileName = 'filo_backup_export_$timestamp.zip';
        effectiveCustomDir = customDestinationDir;
        final basePartDir = (effectiveCustomDir != null &&
                effectiveCustomDir.isNotEmpty)
            ? effectiveCustomDir
            : workDir.path;
        archivePartPath = p.join(
          basePartDir,
          '$finalZipFileName.part',
        );
        lastValidOffset = 0;
        completedEntries = <StreamingZipEntry>[];
      }

      final completedNodeIds = completedEntries.map((e) => e.nodeId).toSet();
      final totalBytes = prepared.isNotEmpty
          ? prepared.fold<int>(0, (sum, item) => sum + item.node.sizeBytes)
          : (resumeCheckpoint?.totalBytes ?? 0);
      final totalFiles =
          prepared.isNotEmpty ? prepared.length : (resumeCheckpoint?.totalFiles ?? 0);
      int completedBytes = completedEntries.fold<int>(
        0,
        (sum, entry) => sum + entry.uncompressedSize,
      );

      final channelCache = <String, VaultChannelInfo>{};
      int consecutiveNetworkFailures = 0;

      VaultExportCheckpoint buildCheckpoint() {
        return VaultExportCheckpoint(
          exportId: exportId,
          archivePartPath: archivePartPath,
          finalZipFileName: finalZipFileName,
          customDestinationDir: effectiveCustomDir,
          lastValidOffset: lastValidOffset,
          totalFiles: totalFiles,
          totalBytes: totalBytes,
          completedBytes: completedBytes,
          completedEntries: List.unmodifiable(completedEntries),
          failedFiles: List.unmodifiable(failedFiles),
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        );
      }

      Future<void> persistCheckpoint(VaultExportCheckpoint cp) async {
        final tmpFile = File('${checkpointFile.path}.tmp');
        await tmpFile.writeAsString(jsonEncode(cp.toJson()), flush: true);
        await tmpFile.rename(checkpointFile.path);
      }

      updateTransferTask(
        status: TransferStatus.running,
        bytesTransferred: completedBytes,
        totalBytes: totalBytes,
        label: 'Vault Backup (${completedEntries.length}/$totalFiles)',
      );

      if (!finalizePartialOnly) {
        final remainingItems = prepared
            .where((item) => !completedNodeIds.contains(item.node.id))
            .toList();

        for (final item in remainingItems) {
          if (_cancelRequested) {
            final cp = buildCheckpoint();
            await persistCheckpoint(cp);
            updateTransferTask(
              status: TransferStatus.paused,
              bytesTransferred: completedBytes,
              totalBytes: totalBytes,
              label: 'Export paused (${completedEntries.length}/$totalFiles)',
            );
            final pausedState = VaultExportState(
              status: VaultExportStatus.paused,
              completedFiles: completedEntries.length,
              totalFiles: totalFiles,
              bytesTransferred: completedBytes,
              totalBytes: totalBytes,
              failedFiles: List.unmodifiable(failedFiles),
              resumableCheckpoint: cp,
              statusMessage: 'Export paused. You can resume anytime.',
            );
            emitState(pausedState);
            return pausedState;
          }

          emitState(VaultExportState(
            status: VaultExportStatus.running,
            completedFiles: completedEntries.length,
            totalFiles: totalFiles,
            bytesTransferred: completedBytes,
            totalBytes: totalBytes,
            currentFileName: item.node.name,
            failedFiles: List.unmodifiable(failedFiles),
            statusMessage:
                'Exporting ${completedEntries.length + 1} of $totalFiles...',
          ));

          String? sourceFilePathForZip;
          bool shouldSecureDeleteStaging = false;

          try {
            final offlineFile =
                await _fileRepository.getOfflineFile(item.node.id);
            if (offlineFile != null && await offlineFile.exists()) {
              sourceFilePathForZip = offlineFile.path;
            } else if (item.chunks.isNotEmpty) {
              if (await stagingFile.exists()) {
                await SessionCacheService.secureDeleteFile(stagingFile);
              }
              final channelTitle = AppConfig.getChannelTitle(
                isEncrypted: item.isEncryptedWorkspace,
              );
              final channel = channelCache[channelTitle] ??=
                  await _storageBackend.getOrCreateVaultChannel(channelTitle);

              shouldSecureDeleteStaging = true;
              await _chunkingEngine.downloadAndDecryptFile(
                chunks: item.chunks,
                destinationFile: stagingFile,
                masterKey: exportKey,
                channelId: channel.channelId,
                deleteRemoteCache: true,
                isCancelled: () => _cancelRequested,
                maxRetries: _maxChunkRetries,
                onProgress: (fileBytes, fileTotal, _) {
                  final liveTotal = completedBytes + fileBytes;
                  updateTransferTask(
                    status: TransferStatus.running,
                    bytesTransferred: liveTotal.clamp(0, totalBytes),
                    totalBytes: totalBytes,
                    label:
                        'Exporting ${item.node.name} (${completedEntries.length + 1}/$totalFiles)',
                  );
                  emitState(VaultExportState(
                    status: VaultExportStatus.running,
                    completedFiles: completedEntries.length,
                    totalFiles: totalFiles,
                    bytesTransferred: liveTotal.clamp(0, totalBytes),
                    totalBytes: totalBytes,
                    currentFileName: item.node.name,
                    failedFiles: List.unmodifiable(failedFiles),
                    statusMessage:
                        'Exporting ${completedEntries.length + 1} of $totalFiles...',
                  ));
                },
              );
              sourceFilePathForZip = stagingFile.path;
            } else {
              // 0-byte empty file
              sourceFilePathForZip = null;
            }

            if (_cancelRequested) {
              throw const TransferCancelledException();
            }

            final entryName = item.zipEntryName;
            final nodeId = item.node.id;
            final modifiedAt = item.node.modifiedAt;
            final offset = lastValidOffset;
            final srcPath = sourceFilePathForZip;

            final entry = runInIsolate
                ? await _appendFileToZipInIsolate(
                    archivePartPath: archivePartPath,
                    offset: offset,
                    nodeId: nodeId,
                    entryName: entryName,
                    sourceFilePath: srcPath,
                    modifiedAt: modifiedAt,
                  )
                : await StreamingZipWriter.appendFile(
                    archivePartPath: archivePartPath,
                    offset: offset,
                    nodeId: nodeId,
                    entryName: entryName,
                    sourceFilePath: srcPath,
                    modifiedAt: modifiedAt,
                  );

            completedEntries.add(entry);
            lastValidOffset = entry.endOffset;
            completedBytes += item.node.sizeBytes;
            consecutiveNetworkFailures = 0;

            await persistCheckpoint(buildCheckpoint());

            updateTransferTask(
              status: TransferStatus.running,
              bytesTransferred: completedBytes,
              totalBytes: totalBytes,
              label: 'Vault Backup (${completedEntries.length}/$totalFiles)',
            );
          } on TransferCancelledException {
            final cp = buildCheckpoint();
            await persistCheckpoint(cp);
            updateTransferTask(
              status: TransferStatus.paused,
              bytesTransferred: completedBytes,
              totalBytes: totalBytes,
              label: 'Export paused (${completedEntries.length}/$totalFiles)',
            );
            final pausedState = VaultExportState(
              status: VaultExportStatus.paused,
              completedFiles: completedEntries.length,
              totalFiles: totalFiles,
              bytesTransferred: completedBytes,
              totalBytes: totalBytes,
              failedFiles: List.unmodifiable(failedFiles),
              resumableCheckpoint: cp,
              statusMessage: 'Export paused. You can resume anytime.',
            );
            emitState(pausedState);
            return pausedState;
          } catch (e) {
            failedFiles.add(
              ExportFileFailure(
                nodeId: item.node.id,
                fileName: item.node.name,
                zipEntryName: item.zipEntryName,
                error: e.toString(),
              ),
            );
            if (_isConnectivityFailure(e)) {
              consecutiveNetworkFailures++;
              if (consecutiveNetworkFailures >= 2) {
                final cp = buildCheckpoint();
                await persistCheckpoint(cp);
                const msg =
                    'Paused due to network interruption. Tap Resume when online.';
                updateTransferTask(
                  status: TransferStatus.paused,
                  bytesTransferred: completedBytes,
                  totalBytes: totalBytes,
                  label: 'Export paused (${completedEntries.length}/$totalFiles)',
                  errorMessage: msg,
                );
                final pausedState = VaultExportState(
                  status: VaultExportStatus.paused,
                  completedFiles: completedEntries.length,
                  totalFiles: totalFiles,
                  bytesTransferred: completedBytes,
                  totalBytes: totalBytes,
                  failedFiles: List.unmodifiable(failedFiles),
                  resumableCheckpoint: cp,
                  statusMessage: msg,
                  errorMessage: e.toString(),
                );
                emitState(pausedState);
                return pausedState;
              }
            }
          } finally {
            if (shouldSecureDeleteStaging && await stagingFile.exists()) {
              await SessionCacheService.secureDeleteFile(stagingFile);
            }
          }
        }
      }

      if (completedEntries.isEmpty) {
        await discardCheckpoint();
        final errText = failedFiles.isNotEmpty
            ? failedFiles.first.error
            : 'No files could be exported';
        updateTransferTask(
          status: TransferStatus.failed,
          bytesTransferred: 0,
          totalBytes: totalBytes,
          label: 'Vault Export failed',
          errorMessage: errText,
        );
        final failedState = VaultExportState(
          status: VaultExportStatus.failed,
          completedFiles: 0,
          totalFiles: totalFiles,
          bytesTransferred: 0,
          totalBytes: totalBytes,
          failedFiles: List.unmodifiable(failedFiles),
          errorMessage: errText,
        );
        emitState(failedState);
        return failedState;
      }

      // If any files failed and the user hasn't explicitly chosen to finalize anyway,
      // pause with checkpoint intact so zero progress is lost and failed files are visible.
      if (!finalizePartialOnly && failedFiles.isNotEmpty) {
        final cp = buildCheckpoint();
        await persistCheckpoint(cp);
        final msg =
            '${completedEntries.length} files ready, ${failedFiles.length} failed';
        updateTransferTask(
          status: TransferStatus.paused,
          bytesTransferred: completedBytes,
          totalBytes: totalBytes,
          label: 'Export needs attention ($msg)',
          errorMessage: failedFiles.first.error,
        );
        final partialState = VaultExportState(
          status: VaultExportStatus.partialNeedsAction,
          completedFiles: completedEntries.length,
          totalFiles: totalFiles,
          bytesTransferred: completedBytes,
          totalBytes: totalBytes,
          failedFiles: List.unmodifiable(failedFiles),
          resumableCheckpoint: cp,
          statusMessage: msg,
        );
        emitState(partialState);
        return partialState;
      }

      // Finalize Central Directory + Zip64 EOCD & deliver archive
      emitState(VaultExportState(
        status: VaultExportStatus.finalizing,
        completedFiles: completedEntries.length,
        totalFiles: totalFiles,
        bytesTransferred: completedBytes,
        totalBytes: totalBytes,
        failedFiles: List.unmodifiable(failedFiles),
        statusMessage: 'Finalizing ZIP archive...',
      ));

      final entriesToFinalize = List<StreamingZipEntry>.from(completedEntries);
      final cdOffset = lastValidOffset;
      final comment =
          '${AppConfig.appName} Complete Archive Backup (${entriesToFinalize.length} files)';

      if (runInIsolate) {
        await _finalizeZipInIsolate(
          archivePartPath: archivePartPath,
          entries: entriesToFinalize,
          centralDirectoryOffset: cdOffset,
          comment: comment,
        );
      } else {
        await StreamingZipWriter.finalize(
          archivePartPath: archivePartPath,
          entries: entriesToFinalize,
          centralDirectoryOffset: cdOffset,
          comment: comment,
        );
      }

      final delivery = await _platformBridge.deliverArchive(
        finalizedPartFile: File(archivePartPath),
        finalFileName: finalZipFileName,
        customDestinationDir: effectiveCustomDir,
      );

      if (await checkpointFile.exists()) {
        await checkpointFile.delete();
      }

      updateTransferTask(
        status: TransferStatus.completed,
        bytesTransferred: totalBytes,
        totalBytes: totalBytes,
        label: 'Exported ${entriesToFinalize.length} files',
      );

      final doneState = VaultExportState(
        status: VaultExportStatus.completed,
        completedFiles: entriesToFinalize.length,
        totalFiles: totalFiles,
        bytesTransferred: totalBytes,
        totalBytes: totalBytes,
        outputDisplayPath: delivery.displayPath,
        localShareableFilePath: delivery.localShareablePath,
        failedFiles: List.unmodifiable(failedFiles),
        statusMessage:
            'Exported ${entriesToFinalize.length} files to ${delivery.displayPath}',
      );
      emitState(doneState);
      return doneState;
    } catch (e) {
      updateTransferTask(
        status: TransferStatus.failed,
        bytesTransferred: 0,
        totalBytes: 0,
        label: 'Vault Export failed',
        errorMessage: e.toString(),
      );
      final errState = VaultExportState(
        status: VaultExportStatus.failed,
        errorMessage: e.toString(),
        resumableCheckpoint: resumeCheckpoint,
      );
      emitState(errState);
      return errState;
    } finally {
      _isRunning = false;
      exportKey.fillRange(0, exportKey.length, 0);
      if (await stagingFile.exists()) {
        await SessionCacheService.secureDeleteFile(stagingFile);
      }
    }
  }

  /// Resolves every file node's workspace-prefixed, collision-free ZIP entry path
  /// and chunks upfront so no DB decryption calls occur during transfer.
  Future<List<_PreparedExportItem>> _prepareExportItems({
    Set<String> completedNodeIds = const <String>{},
    Set<String> reservedLowerPaths = const <String>{},
  }) async {
    final allNodes = await _fileRepository.getNodes(searchQuery: '');
    final fileNodes = allNodes.where((n) => n.isFile).toList();
    if (fileNodes.isEmpty) return const [];

    final workspaces = await _fileRepository.getWorkspaces();
    final workspaceById = {for (final w in workspaces) w.id: w};
    final nodeById = {for (final n in allNodes) n.id: n};

    final usedLowerPaths = <String>{...reservedLowerPaths};
    final prepared = <_PreparedExportItem>[];

    for (final node in fileNodes) {
      final ws = workspaceById[node.workspaceId] ??
          Workspace.defaults.cast<Workspace?>().firstWhere(
                (w) => w!.id == node.workspaceId,
                orElse: () => null,
              ) ??
          Workspace.fromId(node.workspaceId, workspaces);
      final wsFolder = FileNode.sanitizeNodeName(ws.name);
      final folderParts = _buildFolderSegments(node, nodeById);
      final safeFileName = FileNode.sanitizeNodeName(node.name);

      final String uniquePath;
      if (completedNodeIds.contains(node.id)) {
        uniquePath = [...[wsFolder, ...folderParts], safeFileName].join('/');
      } else {
        final baseParts = [wsFolder, ...folderParts];
        uniquePath = _allocateUniqueZipPath(
          directoryParts: baseParts,
          fileName: safeFileName,
          usedLowerPaths: usedLowerPaths,
        );
      }

      final chunks = await _fileRepository.getChunksForNode(node.id);
      prepared.add(
        _PreparedExportItem(
          node: node,
          zipEntryName: uniquePath,
          chunks: chunks,
          isEncryptedWorkspace: ws.isEncrypted,
        ),
      );
    }

    return prepared;
  }

  List<String> _buildFolderSegments(
    FileNode fileNode,
    Map<String, FileNode> nodeById,
  ) {
    final segments = <String>[];
    final seen = <String>{fileNode.id};
    String? currentParentId = fileNode.parentId;

    while (currentParentId != null && seen.add(currentParentId)) {
      final parent = nodeById[currentParentId];
      if (parent == null) break;
      segments.insert(0, FileNode.sanitizeNodeName(parent.name));
      currentParentId = parent.parentId;
    }

    return segments;
  }

  String _allocateUniqueZipPath({
    required List<String> directoryParts,
    required String fileName,
    required Set<String> usedLowerPaths,
  }) {
    final dirPrefix = directoryParts.isNotEmpty ? '${directoryParts.join('/')}/' : '';
    var candidate = '$dirPrefix$fileName';
    if (usedLowerPaths.add(candidate.toLowerCase())) {
      return candidate;
    }

    final dotIndex = fileName.lastIndexOf('.');
    final hasExt = dotIndex > 0 && dotIndex < fileName.length - 1;
    final stem = hasExt ? fileName.substring(0, dotIndex) : fileName;
    final ext = hasExt ? fileName.substring(dotIndex) : '';

    int counter = 2;
    while (true) {
      candidate = '$dirPrefix$stem ($counter)$ext';
      if (usedLowerPaths.add(candidate.toLowerCase())) {
        return candidate;
      }
      counter++;
    }
  }

  bool _isConnectivityFailure(Object error) {
    if (error is TimeoutException ||
        error is SocketException ||
        error is HttpException ||
        error is HandshakeException) {
      return true;
    }
    final msg = error.toString();
    return msg.contains('FLOOD_WAIT_') ||
        msg.contains('Timed out') ||
        msg.contains('Stalled downloading') ||
        msg.contains('SocketException') ||
        msg.contains('network');
  }
}
