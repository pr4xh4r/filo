import 'package:uuid/uuid.dart';
import '../../../core/database/filo_database.dart';
import '../../../core/database/node_model.dart';
import '../../../core/database/chunk_model.dart';

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
  }) {
    return _database.listNodes(
      parentId: parentId,
      onlyFavorites: onlyFavorites,
      searchQuery: searchQuery,
      mimePrefix: mimePrefix,
    );
  }

  Future<FileNode> createFolder({
    required String name,
    String? parentId,
  }) async {
    final now = DateTime.now();
    final folder = FileNode(
      id: _uuid.v4(),
      parentId: parentId,
      name: name.trim(),
      type: NodeType.folder,
      createdAt: now,
      modifiedAt: now,
      syncState: SyncState.synced,
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
  }) async {
    final now = DateTime.now();
    final node = FileNode(
      id: _uuid.v4(),
      parentId: parentId,
      name: name,
      type: NodeType.file,
      sizeBytes: sizeBytes,
      mimeType: mimeType,
      contentHash: contentHash,
      createdAt: now,
      modifiedAt: now,
      // BUG 30 FIX: New files start as localOnly — they haven't been uploaded yet
      syncState: SyncState.localOnly,
    );
    await _database.insertNode(node);
    return node;
  }

  Future<void> saveFileChunks(List<FileChunk> chunks) {
    return _database.insertChunks(chunks);
  }

  Future<List<FileChunk>> getChunksForNode(String nodeId) {
    return _database.getChunksForNode(nodeId);
  }

  Future<void> renameNode(String id, String newName) {
    return _database.renameNode(id, newName.trim());
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

  Future<List<FileNode>> getFolders() async {
    final allNodes = await _database.listNodes(includeTrashed: false);
    return allNodes.where((n) => n.isFolder).toList();
  }

  Future<void> restoreFromTrash(String id) {
    return _database.restoreNode(id);
  }

  Future<void> deletePermanently(String id) {
    return _database.deleteNodePermanently(id);
  }

  Future<void> emptyTrash() {
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
}
