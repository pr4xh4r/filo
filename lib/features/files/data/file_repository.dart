import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/cache/session_cache_service.dart';
import '../../../core/config/app_config.dart';
import '../../../core/crypto/crypto_engine.dart';
import '../../../core/crypto/hash_utils.dart';
import '../../../core/database/filo_database.dart';
import '../../../core/database/node_model.dart';
import '../../../core/database/chunk_model.dart';
import '../../storage/domain/storage_backend.dart';
import '../domain/workspace.dart';

/// Repository managing file and folder operations in the local index.
class FileRepository {
  final FiloDatabase _database;
  final _uuid = const Uuid();

  FileRepository({required FiloDatabase database}) : _database = database;

  FiloDatabase get database => _database;

  Future<List<FileNode>> getNodes({
    String? parentId,
    bool onlyFavorites = false,
    String? searchQuery,
    String? mimePrefix,
    String? workspaceId,
    String? tag,
  }) {
    return _database.listNodes(
      parentId: parentId,
      onlyFavorites: onlyFavorites,
      searchQuery: searchQuery,
      mimePrefix: mimePrefix,
      workspaceId: workspaceId,
      tag: tag,
    );
  }

  Future<FileNode> createFolder({
    required String name,
    String? parentId,
    String workspaceId = 'personal',
    List<String> tags = const [],
  }) async {
    final now = DateTime.now();
    final folder = FileNode(
      id: _uuid.v4(),
      parentId: parentId,
      name: FileNode.sanitizeNodeName(name),
      type: NodeType.folder,
      createdAt: now,
      modifiedAt: now,
      syncState: SyncState.synced,
      workspaceId: workspaceId,
      tags: tags,
    );
    await _database.insertNode(folder);
    return folder;
  }

  Future<FileNode> createFileNode({
    required String name,
    required int sizeBytes,
    String? parentId,
    String? mimeType,
    String? contentHash,
    String workspaceId = 'personal',
    List<String> tags = const [],
  }) async {
    final now = DateTime.now();
    final node = FileNode(
      id: _uuid.v4(),
      parentId: parentId,
      name: FileNode.sanitizeNodeName(name),
      type: NodeType.file,
      sizeBytes: sizeBytes,
      mimeType: mimeType,
      contentHash: contentHash,
      createdAt: now,
      modifiedAt: now,
      // BUG 30 FIX: New files start as localOnly — they haven't been uploaded yet
      syncState: SyncState.localOnly,
      workspaceId: workspaceId,
      tags: tags,
    );
    await _database.insertNode(node);
    return node;
  }

  Future<void> updateNodeTags(String id, List<String> tags) {
    return _database.updateNodeTags(id, tags);
  }

  Future<void> updateNodeWorkspace(String id, String workspaceId) {
    return _database.updateNodeWorkspace(id, workspaceId);
  }

  Future<List<Workspace>> getWorkspaces() {
    return _database.getWorkspaces();
  }

  Future<List<Workspace>> getDeletedWorkspaces() {
    return _database.getDeletedWorkspaces();
  }

  Future<void> createWorkspace(Workspace workspace) {
    return _database.insertWorkspace(workspace);
  }

  Future<void> deleteWorkspace(String id, {bool moveToTrash = true}) {
    return _database.deleteWorkspace(id, moveToTrash: moveToTrash);
  }

  Future<void> restoreWorkspace(String id) {
    return _database.restoreWorkspace(id);
  }

  Future<int> getWorkspaceTrashedFileCount(String workspaceId) {
    return _database.getWorkspaceTrashedFileCount(workspaceId);
  }

  Future<void> saveFileChunks(List<FileChunk> chunks) {
    return _database.insertChunks(chunks);
  }

  Future<List<FileChunk>> getChunksForNode(String nodeId) {
    return _database.getChunksForNode(nodeId);
  }

  Future<void> renameNode(String id, String newName) {
    return _database.renameNode(id, FileNode.sanitizeNodeName(newName));
  }

  Future<void> moveNode(String id, String? newParentId) {
    return _database.moveNode(id, newParentId);
  }

  Future<void> toggleFavorite(String id, bool isFavorite) {
    return _database.toggleFavorite(id, isFavorite);
  }

  Future<void> moveToTrash(String id) {
    return _database.trashNode(id);
  }

  Future<void> trashNodes(List<String> ids) {
    return _database.trashNodes(ids);
  }

  Future<void> updateNodeHash(String id, String contentHash) {
    return _database.updateNodeHash(id, contentHash);
  }

  Future<void> markNodeSynced(String id) {
    return _database.updateNodeSyncState(id, SyncState.synced);
  }

  Future<List<FileNode>> getFolders() async {
    final allNodes = await _database.listNodes(includeTrashed: false);
    return allNodes.where((n) => n.isFolder).toList();
  }

  Future<void> restoreFromTrash(String id) {
    return _database.restoreNode(id);
  }

  File _offlineVaultFile(String appDirPath, String nodeId) {
    final vaultDir = p.join(appDirPath, 'offline_vault');
    final candidate = p.normalize(p.join(vaultDir, nodeId));
    if (!p.isWithin(vaultDir, candidate)) {
      throw ArgumentError('Invalid offline vault node ID: $nodeId');
    }
    return File(candidate);
  }

  Future<void> deletePermanently(String id) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final offlineFile = _offlineVaultFile(appDir.path, id);
      if (offlineFile.existsSync()) {
        SessionCacheService.secureDeleteFileSync(offlineFile);
      }
    } catch (_) {
      // Non-fatal if offline cache file does not exist or platform path unavailable
    }
    return _database.deleteNodePermanently(id);
  }

  Future<int> purgeOldTrash({int days = 30}) {
    return _database.purgeOldTrash(days: days);
  }

  Future<void> emptyTrash() async {
    try {
      final trashed = await _database.listTrashedNodes();
      final appDir = await getApplicationDocumentsDirectory();
      for (final n in trashed) {
        final offlineFile = _offlineVaultFile(appDir.path, n.id);
        if (offlineFile.existsSync()) {
          SessionCacheService.secureDeleteFileSync(offlineFile);
        }
      }
    } catch (_) {
      // Non-fatal if offline cache files or platform path unavailable
    }
    return _database.emptyTrash();
  }

  Future<List<FileNode>> getTrashedNodes() {
    return _database.listTrashedNodes();
  }

  Future<List<FileNode>> getBreadcrumbs(String nodeId) {
    return _database.getBreadcrumbs(nodeId);
  }

  Future<StorageUsageStats> getStorageUsage() {
    return _database.getStorageUsage();
  }

  Future<FileNode?> findDuplicateByHash(String contentHash) {
    return _database.findByHash(contentHash);
  }

  Future<File?> getOfflineFile(String nodeId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final offlineFile = _offlineVaultFile(appDir.path, nodeId);
      if (offlineFile.existsSync() && offlineFile.lengthSync() > 0) {
        return offlineFile;
      }
    } catch (_) {
      // Non-fatal if offline cache file or platform path unavailable
    }
    return null;
  }

  /// Securely wipes the entire offline vault directory (used on logout/wipe).
  Future<void> wipeOfflineVault() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final offlineDir = Directory(p.join(appDir.path, 'offline_vault'));
      await SessionCacheService.secureDeleteDirectory(offlineDir);
    } catch (_) {
      // Non-fatal if offline directory does not exist or platform path unavailable
    }
  }

  Future<bool> togglePinOffline(FileNode node, {Uint8List? masterKey, StorageBackend? storage}) async {
    final appDir = await getApplicationDocumentsDirectory();
    final offlineDir = Directory(p.join(appDir.path, 'offline_vault'));
    if (!offlineDir.existsSync()) {
      offlineDir.createSync(recursive: true);
    }
    final offlineFile = _offlineVaultFile(appDir.path, node.id);

    if (node.isPinnedOffline) {
      if (offlineFile.existsSync()) {
        try {
          SessionCacheService.secureDeleteFileSync(offlineFile);
        } catch (_) {
          // Best-effort cleanup during unpin
        }
      }
      await _database.updateNode(node.copyWith(isPinnedOffline: false));
      return false;
    } else {
      if (!offlineFile.existsSync() || offlineFile.lengthSync() == 0) {
        // Check active session cache first (0ms instant copy)
        final cachedSessionFile = await SessionCacheService.instance.getCachedFile(
          node.id,
          expectedSize: node.sizeBytes,
        );
        if (cachedSessionFile != null && cachedSessionFile.existsSync()) {
          await cachedSessionFile.copy(offlineFile.path);
        } else {
          final tempDir = await getTemporaryDirectory();
          final name = node.name.toLowerCase();
          final rawExt = name.contains('.') ? name.split('.').last : 'bin';
          final ext = FileNode.sanitizeNodeName(rawExt.isEmpty ? 'bin' : rawExt);
          final previewFile = File(p.join(tempDir.path, 'filo_preview_${node.id}.$ext'));
          final streamFile = File(p.join(tempDir.path, 'filo_stream_${node.id}.$ext'));

          if (previewFile.existsSync() && previewFile.lengthSync() == node.sizeBytes) {
            await previewFile.copy(offlineFile.path);
          } else if (streamFile.existsSync() && streamFile.lengthSync() == node.sizeBytes) {
            await streamFile.copy(offlineFile.path);
          } else if (storage != null && masterKey != null) {
            final chunks = await getChunksForNode(node.id);
            final workspaces = await getWorkspaces();
            final ws = workspaces.firstWhere(
              (w) => w.id == node.workspaceId,
              orElse: () => Workspace.fromId(node.workspaceId, workspaces),
            );
            final channelTitle = AppConfig.getChannelTitle(isEncrypted: ws.isEncrypted);
            final channel = await storage.getOrCreateVaultChannel(channelTitle);

            final sortedChunks = List<FileChunk>.from(chunks)
              ..sort((a, b) => a.chunkIndex.compareTo(b.chunkIndex));
            final sink = offlineFile.openWrite();
            bool sinkClosed = false;
            try {
              for (final c in sortedChunks) {
                final cipher = await storage.downloadChunk(
                  channelId: channel.channelId,
                  remoteFileId: c.remoteFileId,
                );
                final downloadedHash = HashUtils.sha256Hex(cipher);
                if (downloadedHash != c.sha256Hash) {
                  throw Exception(
                    'Chunk integrity verification failed for part ${c.chunkIndex}. '
                    'Expected ${c.sha256Hash}, got $downloadedHash',
                  );
                }
                final chunkData = (c.ivHex == 'plain')
                    ? cipher
                    : await CryptoEngine.decryptBytes(combinedBytes: cipher, key: masterKey);
                sink.add(chunkData);
              }
              await sink.flush();
              await sink.close();
              sinkClosed = true;
            } catch (e) {
              if (!sinkClosed) {
                try {
                  await sink.close();
                } catch (_) {
                  // Ignore close error during rollback
                }
              }
              if (offlineFile.existsSync()) {
                try {
                  SessionCacheService.secureDeleteFileSync(offlineFile);
                } catch (_) {
                  // Best-effort cleanup of partial file
                }
              }
              rethrow;
            }
          }
        }
      }
      await _database.updateNode(node.copyWith(isPinnedOffline: true));
      return true;
    }
  }
}
