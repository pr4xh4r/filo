import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import 'node_model.dart';
import 'chunk_model.dart';
import 'transfer_model.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import '../../features/files/domain/workspace.dart';

bool _sqliteInitialized = false;

/// Ensures the sqlite3 dynamic library is reliably resolved across all Android
/// architectures (arm64-v8a, armeabi-v7a, x86_64), Android 16/15 16k page alignment,
/// and modern Android isolated ClassLoader namespaces.
void ensureSqliteInitialized() {
  if (_sqliteInitialized) return;
  _sqliteInitialized = true;

  if (Platform.isAndroid) {
    open.overrideFor(OperatingSystem.android, () {
      // 1. Try default dlopen by soname
      try {
        return DynamicLibrary.open('libsqlite3.so');
      } catch (_) {}

      // 2. Try process global namespace (available when preloaded by MainActivity via System.loadLibrary)
      try {
        final proc = DynamicLibrary.process();
        try {
          proc.lookup('sqlite3_open_v2');
          return proc;
        } catch (_) {}
      } catch (_) {}

      // 3. Inspect /proc/self/maps to discover the exact path where Android loaded libsqlite3.so
      try {
        final mapsFile = File('/proc/self/maps');
        if (mapsFile.existsSync()) {
          final lines = mapsFile.readAsLinesSync();
          for (final line in lines) {
            if (line.contains('libsqlite3.so')) {
              final tokens = line.split(RegExp(r'\s+'));
              for (final token in tokens.reversed) {
                if (token.endsWith('libsqlite3.so') && File(token).existsSync()) {
                  return DynamicLibrary.open(token);
                }
              }
            }
          }
        }
      } catch (_) {}

      // 4. Scan package cmdline and search app-specific library directories
      try {
        final cmdline = File('/proc/self/cmdline');
        if (cmdline.existsSync()) {
          final bytes = cmdline.readAsBytesSync();
          final end = bytes.indexOf(0);
          final pkg = String.fromCharCodes(bytes.sublist(0, end > 0 ? end : bytes.length));
          final candidateDirs = [
            '/data/data/$pkg/lib',
            '/data/user/0/$pkg/lib',
          ];
          for (final dir in candidateDirs) {
            final f = File('$dir/libsqlite3.so');
            if (f.existsSync()) {
              return DynamicLibrary.open(f.path);
            }
          }
        }
      } catch (_) {}

      // 5. Final fallback to soname
      return DynamicLibrary.open('libsqlite3.so');
    });
  }
}

/// Storage category breakdown for settings & usage analytics.
class StorageUsageStats {
  final int totalBytes;
  final int imagesBytes;
  final int videosBytes;
  final int audioBytes;
  final int documentsBytes;
  final int archivesBytes;
  final int otherBytes;
  final int totalFiles;
  final int totalFolders;

  const StorageUsageStats({
    required this.totalBytes,
    required this.imagesBytes,
    required this.videosBytes,
    required this.audioBytes,
    required this.documentsBytes,
    required this.archivesBytes,
    required this.otherBytes,
    required this.totalFiles,
    required this.totalFolders,
  });
}

/// Encrypted local index database for Filo.
///
/// Features:
/// - Fast, zero-latency local queries for 10,000+ files.
/// - Full folder tree hierarchy with breadcrumb resolution.
/// - Trash bin with 30-day retention and one-tap restore.
/// - Full-text and metadata search by name, type, date, size.
/// - Serializes/deserializes index snapshots for zero-knowledge Telegram cloud backup.
class FiloDatabase {
  final Database _db;

  FiloDatabase._(this._db) {
    _createTables();
  }

  /// Opens or creates a file-backed SQLite database.
  static Future<FiloDatabase> openFile(String path) async {
    ensureSqliteInitialized();
    final file = File(path);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    final db = sqlite3.open(path);
    return FiloDatabase._(db);
  }

  /// Opens an in-memory database for unit tests and hermetic execution.
  static FiloDatabase openInMemory() {
    ensureSqliteInitialized();
    final db = sqlite3.openInMemory();
    return FiloDatabase._(db);
  }

  void _createTables() {
    _db.execute('PRAGMA foreign_keys = ON;');
    _db.execute('PRAGMA journal_mode = WAL;');
    _db.execute('PRAGMA synchronous = NORMAL;');
    _db.execute('PRAGMA temp_store = MEMORY;');
    _db.execute('PRAGMA cache_size = -64000;'); // 64MB RAM page cache for 120fps scrolling
    _db.execute('''
      CREATE TABLE IF NOT EXISTS nodes (
        id TEXT PRIMARY KEY,
        parent_id TEXT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        size_bytes INTEGER NOT NULL DEFAULT 0,
        mime_type TEXT,
        content_hash TEXT,
        created_at INTEGER NOT NULL,
        modified_at INTEGER NOT NULL,
        is_favorite INTEGER NOT NULL DEFAULT 0,
        is_trashed INTEGER NOT NULL DEFAULT 0,
        trashed_at INTEGER,
        sync_state TEXT NOT NULL DEFAULT 'synced',
        tags TEXT DEFAULT '',
        workspace_id TEXT NOT NULL DEFAULT 'personal',
        is_pinned_offline INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (parent_id) REFERENCES nodes (id) ON DELETE CASCADE
      );

      CREATE INDEX IF NOT EXISTS idx_nodes_parent ON nodes (parent_id);
      CREATE INDEX IF NOT EXISTS idx_nodes_trashed ON nodes (is_trashed);
      CREATE INDEX IF NOT EXISTS idx_nodes_favorite ON nodes (is_favorite);
      CREATE INDEX IF NOT EXISTS idx_nodes_hash ON nodes (content_hash);
      CREATE INDEX IF NOT EXISTS idx_nodes_parent_trashed ON nodes (parent_id, is_trashed);
      CREATE INDEX IF NOT EXISTS idx_nodes_ws_parent_trashed ON nodes (workspace_id, parent_id, is_trashed);
      CREATE INDEX IF NOT EXISTS idx_nodes_type_name ON nodes (type DESC, name COLLATE NOCASE ASC);
      CREATE INDEX IF NOT EXISTS idx_nodes_search ON nodes (name COLLATE NOCASE);

      CREATE TABLE IF NOT EXISTS chunks (
        id TEXT PRIMARY KEY,
        node_id TEXT NOT NULL,
        chunk_index INTEGER NOT NULL,
        remote_message_id TEXT NOT NULL,
        remote_file_id TEXT NOT NULL,
        size_bytes INTEGER NOT NULL,
        sha256_hash TEXT NOT NULL,
        iv_hex TEXT NOT NULL,
        FOREIGN KEY (node_id) REFERENCES nodes (id) ON DELETE CASCADE
      );

      CREATE INDEX IF NOT EXISTS idx_chunks_node ON chunks (node_id);
      CREATE INDEX IF NOT EXISTS idx_chunks_node_index ON chunks (node_id, chunk_index);

      CREATE TABLE IF NOT EXISTS transfer_tasks (
        id TEXT PRIMARY KEY,
        node_id TEXT NOT NULL,
        file_name TEXT NOT NULL,
        type TEXT NOT NULL,
        status TEXT NOT NULL,
        progress REAL NOT NULL DEFAULT 0.0,
        bytes_transferred INTEGER NOT NULL DEFAULT 0,
        total_bytes INTEGER NOT NULL,
        error_message TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS workspaces (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL,
        icon_code INTEGER NOT NULL,
        is_encrypted INTEGER NOT NULL DEFAULT 1,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      );

      CREATE TABLE IF NOT EXISTS sync_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      );
    ''');

    // Backward-compatible schema migrations
    try {
      _db.execute("ALTER TABLE nodes ADD COLUMN tags TEXT DEFAULT '';");
    } catch (_) {}
    try {
      _db.execute('ALTER TABLE workspaces ADD COLUMN is_encrypted INTEGER NOT NULL DEFAULT 1;');
    } catch (_) {}
    try {
      _db.execute('ALTER TABLE workspaces ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;');
    } catch (_) {}
    try {
      _db.execute("ALTER TABLE nodes ADD COLUMN workspace_id TEXT NOT NULL DEFAULT 'personal';");
    } catch (_) {}
    try {
      _db.execute('CREATE INDEX IF NOT EXISTS idx_nodes_ws_parent_trashed ON nodes (workspace_id, parent_id, is_trashed);');
    } catch (_) {}
    try {
      _db.execute('ALTER TABLE nodes ADD COLUMN is_pinned_offline INTEGER NOT NULL DEFAULT 0;');
    } catch (_) {}
  }

  // -------------------------------------------------------------
  // Node Operations (Files and Folders)
  // -------------------------------------------------------------

  Future<void> insertNode(FileNode node) async {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO nodes (
        id, parent_id, name, type, size_bytes, mime_type, content_hash,
        created_at, modified_at, is_favorite, is_trashed, trashed_at, sync_state,
        tags, workspace_id, is_pinned_offline
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');

    stmt.execute([
      node.id,
      node.parentId,
      node.name,
      node.type.name,
      node.sizeBytes,
      node.mimeType,
      node.contentHash,
      node.createdAt.millisecondsSinceEpoch,
      node.modifiedAt.millisecondsSinceEpoch,
      node.isFavorite ? 1 : 0,
      node.isTrashed ? 1 : 0,
      node.trashedAt?.millisecondsSinceEpoch,
      node.syncState.name,
      node.tags.join(','),
      node.workspaceId,
      node.isPinnedOffline ? 1 : 0,
    ]);
    stmt.dispose();
  }

  Future<void> updateNodeTags(String id, List<String> tags) async {
    _db.execute(
      'UPDATE nodes SET tags = ?, modified_at = ? WHERE id = ?',
      [tags.join(','), DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  Future<void> updateNodeWorkspace(String id, String workspaceId) async {
    _db.execute(
      'UPDATE nodes SET workspace_id = ?, modified_at = ? WHERE id = ?',
      [workspaceId, DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  Future<List<Workspace>> getWorkspaces({bool includeDeleted = false}) async {
    final query = includeDeleted
        ? 'SELECT * FROM workspaces ORDER BY created_at ASC'
        : 'SELECT * FROM workspaces WHERE is_deleted = 0 ORDER BY created_at ASC';
    final ResultSet result = _db.select(query);
    if (result.isEmpty && !includeDeleted) {
      for (final ws in Workspace.defaults) {
        _db.execute(
          'INSERT OR IGNORE INTO workspaces (id, name, description, icon_code, is_encrypted, is_deleted, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [ws.id, ws.name, ws.description, ws.icon.codePoint, ws.isEncrypted ? 1 : 0, 0, DateTime.now().millisecondsSinceEpoch],
        );
      }
      return Workspace.defaults;
    }
    return result.map((row) {
      final id = row['id'] as String;
      final iconCode = row['icon_code'] as int;
      final icon = _resolveWorkspaceIcon(iconCode);
      final isEncrypted = (row['is_encrypted'] as int? ?? 1) == 1;
      final isDeleted = (row['is_deleted'] as int? ?? 0) == 1;
      return Workspace(
        id: id,
        name: row['name'] as String,
        description: row['description'] as String,
        icon: icon,
        isEncrypted: isEncrypted,
        isDeleted: isDeleted,
      );
    }).toList();
  }

  Future<List<Workspace>> getDeletedWorkspaces() async {
    final ResultSet result = _db.select('SELECT * FROM workspaces WHERE is_deleted = 1 ORDER BY created_at DESC');
    return result.map((row) {
      final id = row['id'] as String;
      final iconCode = row['icon_code'] as int;
      final icon = _resolveWorkspaceIcon(iconCode);
      final isEncrypted = (row['is_encrypted'] as int? ?? 1) == 1;
      return Workspace(
        id: id,
        name: row['name'] as String,
        description: row['description'] as String,
        icon: icon,
        isEncrypted: isEncrypted,
        isDeleted: true,
      );
    }).toList();
  }

  Future<void> insertWorkspace(Workspace ws) async {
    _db.execute(
      'INSERT OR REPLACE INTO workspaces (id, name, description, icon_code, is_encrypted, is_deleted, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [ws.id, ws.name, ws.description, ws.icon.codePoint, ws.isEncrypted ? 1 : 0, ws.isDeleted ? 1 : 0, DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> deleteWorkspace(String id, {bool moveToTrash = true}) async {
    if (moveToTrash) {
      _db.execute('UPDATE workspaces SET is_deleted = 1 WHERE id = ?', [id]);
      _db.execute(
        'UPDATE nodes SET is_trashed = 1, trashed_at = ? WHERE workspace_id = ? AND is_trashed = 0',
        [DateTime.now().millisecondsSinceEpoch, id],
      );
    } else {
      _db.execute('BEGIN TRANSACTION');
      try {
        _db.execute('DELETE FROM chunks WHERE node_id IN (SELECT id FROM nodes WHERE workspace_id = ?)', [id]);
        _db.execute('DELETE FROM nodes WHERE workspace_id = ?', [id]);
        _db.execute('DELETE FROM workspaces WHERE id = ?', [id]);
        _db.execute('COMMIT');
      } catch (_) {
        _db.execute('ROLLBACK');
        rethrow;
      }
    }
  }

  Future<void> restoreWorkspace(String id) async {
    _db.execute('UPDATE workspaces SET is_deleted = 0 WHERE id = ?', [id]);
    _db.execute(
      'UPDATE nodes SET is_trashed = 0, trashed_at = NULL WHERE workspace_id = ? AND is_trashed = 1',
      [id],
    );
  }

  Future<int> getWorkspaceTrashedFileCount(String workspaceId) async {
    final ResultSet res = _db.select(
      'SELECT COUNT(*) as cnt FROM nodes WHERE workspace_id = ? AND is_trashed = 1',
      [workspaceId],
    );
    if (res.isEmpty) return 0;
    return res.first['cnt'] as int;
  }

  static IconData _resolveWorkspaceIcon(int code) {
    if (code == Icons.folder_outlined.codePoint) return Icons.folder_outlined;
    if (code == Icons.business_center_outlined.codePoint) return Icons.business_center_outlined;
    if (code == Icons.lock_outline_rounded.codePoint) return Icons.lock_outline_rounded;
    return Icons.folder_outlined;
  }

  Future<FileNode?> getNode(String id) async {
    final ResultSet result = _db.select('SELECT * FROM nodes WHERE id = ?', [id]);
    if (result.isEmpty) return null;
    return _rowToNode(result.first);
  }

  /// Total number of stored filesystem nodes (used for auto-restore checks).
  Future<int> getNodeCount() async {
    final ResultSet result = _db.select('SELECT COUNT(*) as count FROM nodes');
    if (result.isEmpty) return 0;
    return result.first['count'] as int;
  }

  Future<FileNode?> findByHash(String contentHash) async {
    final ResultSet result = _db.select(
      'SELECT * FROM nodes WHERE content_hash = ? AND is_trashed = 0 LIMIT 1',
      [contentHash],
    );
    if (result.isEmpty) return null;
    return _rowToNode(result.first);
  }

  Future<List<FileNode>> listNodes({
    String? parentId,
    bool includeTrashed = false,
    bool onlyFavorites = false,
    String? searchQuery,
    String? mimePrefix,
    String? workspaceId,
    String? tag,
  }) async {
    final conditions = <String>[];
    final params = <dynamic>[];

    if (!includeTrashed) {
      conditions.add('is_trashed = 0');
    }

    if (onlyFavorites) {
      conditions.add('is_favorite = 1');
      if (workspaceId != null && workspaceId.isNotEmpty) {
        if (workspaceId == 'personal' || workspaceId == 'default') {
          conditions.add('(workspace_id = ? OR workspace_id IS NULL OR workspace_id = \'personal\' OR workspace_id = \'default\')');
          params.add(workspaceId);
        } else {
          conditions.add('workspace_id = ?');
          params.add(workspaceId);
        }
      }
    } else if (parentId != null) {
      conditions.add('parent_id = ?');
      params.add(parentId);
    } else if (searchQuery == null) {
      // Root folder listing: optionally filter by workspace
      conditions.add('parent_id IS NULL');
      if (workspaceId != null && workspaceId.isNotEmpty) {
        if (workspaceId == 'personal' || workspaceId == 'default') {
          conditions.add('(workspace_id = ? OR workspace_id IS NULL OR workspace_id = \'personal\' OR workspace_id = \'default\')');
          params.add(workspaceId);
        } else {
          conditions.add('workspace_id = ?');
          params.add(workspaceId);
        }
      }
    }

    if (tag != null && tag.isNotEmpty) {
      conditions.add('tags LIKE ?');
      params.add('%$tag%');
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      conditions.add('name LIKE ?');
      params.add('%$searchQuery%');
    }

    if (mimePrefix != null) {
      conditions.add('mime_type LIKE ?');
      params.add('$mimePrefix%');
    }

    final whereClause = conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';
    final sql = '''
      SELECT * FROM nodes
      $whereClause
      ORDER BY type DESC, name COLLATE NOCASE ASC
    ''';

    final ResultSet result = _db.select(sql, params);
    return result.map(_rowToNode).toList();
  }

  Future<List<FileNode>> listTrashedNodes() async {
    final ResultSet result = _db.select('''
      SELECT * FROM nodes
      WHERE is_trashed = 1
      ORDER BY trashed_at DESC
    ''');
    return result.map(_rowToNode).toList();
  }

  Future<void> updateNode(FileNode node) async {
    // BUG 13 & 28 FIX: Use explicit UPDATE instead of INSERT OR REPLACE
    // to avoid deleting the node and cascading deletion of chunks.
    final stmt = _db.prepare('''
      UPDATE nodes SET
        parent_id = ?,
        name = ?,
        type = ?,
        size_bytes = ?,
        mime_type = ?,
        content_hash = ?,
        created_at = ?,
        modified_at = ?,
        is_favorite = ?,
        is_trashed = ?,
        trashed_at = ?,
        sync_state = ?,
        is_pinned_offline = ?
      WHERE id = ?
    ''');
    stmt.execute([
      node.parentId,
      node.name,
      node.type.name,
      node.sizeBytes,
      node.mimeType,
      node.contentHash,
      node.createdAt.millisecondsSinceEpoch,
      node.modifiedAt.millisecondsSinceEpoch,
      node.isFavorite ? 1 : 0,
      node.isTrashed ? 1 : 0,
      node.trashedAt?.millisecondsSinceEpoch,
      node.syncState.name,
      node.isPinnedOffline ? 1 : 0,
      node.id,
    ]);
    stmt.dispose();
  }

  Future<void> updateNodeHash(String id, String contentHash) async {
    _db.execute(
      'UPDATE nodes SET content_hash = ?, modified_at = ? WHERE id = ?',
      [contentHash, DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  Future<void> updateNodeSyncState(String id, SyncState state) async {
    _db.execute(
      'UPDATE nodes SET sync_state = ? WHERE id = ?',
      [state.name, id],
    );
  }

  Future<String?> getSyncMeta(String key) async {
    final ResultSet result = _db.select(
      'SELECT value FROM sync_meta WHERE key = ? LIMIT 1',
      [key],
    );
    if (result.isEmpty) return null;
    return result.first['value'] as String?;
  }

  Future<void> setSyncMeta(String key, String value) async {
    _db.execute(
      'INSERT OR REPLACE INTO sync_meta (key, value) VALUES (?, ?)',
      [key, value],
    );
  }

  Future<void> markSyncDirty() async {
    await setSyncMeta('sync_dirty', '1');
  }

  Future<void> renameNode(String id, String newName) async {
    _db.execute(
      'UPDATE nodes SET name = ?, modified_at = ? WHERE id = ?',
      [newName, DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  Future<void> moveNode(String id, String? newParentId) async {
    _db.execute(
      'UPDATE nodes SET parent_id = ?, modified_at = ? WHERE id = ?',
      [newParentId, DateTime.now().millisecondsSinceEpoch, id],
    );
  }

  Future<void> toggleFavorite(String id, bool isFavorite) async {
    _db.execute(
      'UPDATE nodes SET is_favorite = ? WHERE id = ?',
      [isFavorite ? 1 : 0, id],
    );
  }

  Future<void> trashNode(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute('''
      WITH RECURSIVE subtree(id) AS (
        SELECT id FROM nodes WHERE id = ?
        UNION ALL
        SELECT n.id FROM nodes n JOIN subtree s ON n.parent_id = s.id
      )
      UPDATE nodes SET is_trashed = 1, trashed_at = ? WHERE id IN subtree
    ''', [id, now]);
  }

  Future<void> trashNodes(List<String> ids) async {
    if (ids.isEmpty) return;
    _db.execute('PRAGMA foreign_keys = OFF;');
    _db.execute('BEGIN TRANSACTION');
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final stmt = _db.prepare('''
        WITH RECURSIVE subtree(id) AS (
          SELECT id FROM nodes WHERE id = ?
          UNION ALL
          SELECT n.id FROM nodes n JOIN subtree s ON n.parent_id = s.id
        )
        UPDATE nodes SET is_trashed = 1, trashed_at = ? WHERE id IN subtree
      ''');
      for (final id in ids) {
        stmt.execute([id, now]);
      }
      stmt.dispose();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    } finally {
      _db.execute('PRAGMA foreign_keys = ON;');
    }
  }

  Future<void> restoreNode(String id) async {
    _db.execute('''
      WITH RECURSIVE subtree(id) AS (
        SELECT id FROM nodes WHERE id = ?
        UNION ALL
        SELECT n.id FROM nodes n JOIN subtree s ON n.parent_id = s.id
      )
      UPDATE nodes SET is_trashed = 0, trashed_at = NULL WHERE id IN subtree
    ''', [id]);
  }

  Future<void> deleteNodePermanently(String id) async {
    _db.execute('PRAGMA foreign_keys = OFF;');
    _db.execute('BEGIN TRANSACTION');
    try {
      _db.execute('''
        WITH RECURSIVE subtree(id) AS (
          SELECT id FROM nodes WHERE id = ?
          UNION ALL
          SELECT n.id FROM nodes n JOIN subtree s ON n.parent_id = s.id
        )
        DELETE FROM chunks WHERE node_id IN subtree
      ''', [id]);
      _db.execute('''
        WITH RECURSIVE subtree(id) AS (
          SELECT id FROM nodes WHERE id = ?
          UNION ALL
          SELECT n.id FROM nodes n JOIN subtree s ON n.parent_id = s.id
        )
        DELETE FROM nodes WHERE id IN subtree
      ''', [id]);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    } finally {
      _db.execute('PRAGMA foreign_keys = ON;');
    }
  }

  Future<int> purgeOldTrash({int days = 30}) async {
    final cutoff = DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    _db.execute('PRAGMA foreign_keys = OFF;');
    _db.execute('BEGIN TRANSACTION');
    try {
      final oldNodes = _db.select(
        'SELECT id FROM nodes WHERE is_trashed = 1 AND trashed_at IS NOT NULL AND trashed_at < ?',
        [cutoff],
      );
      if (oldNodes.isNotEmpty) {
        _db.execute(
          'DELETE FROM chunks WHERE node_id IN (SELECT id FROM nodes WHERE is_trashed = 1 AND trashed_at IS NOT NULL AND trashed_at < ?)',
          [cutoff],
        );
        _db.execute(
          'DELETE FROM nodes WHERE is_trashed = 1 AND trashed_at IS NOT NULL AND trashed_at < ?',
          [cutoff],
        );
      }
      _db.execute('COMMIT');
      return oldNodes.length;
    } catch (_) {
      _db.execute('ROLLBACK');
      return 0;
    } finally {
      _db.execute('PRAGMA foreign_keys = ON;');
    }
  }

  Future<void> emptyTrash() async {
    // BUG 12 FIX: Execute emptyTrash in an atomic transaction
    _db.execute('PRAGMA foreign_keys = OFF;');
    _db.execute('BEGIN TRANSACTION');
    try {
      _db.execute('DELETE FROM chunks WHERE node_id IN (SELECT id FROM nodes WHERE is_trashed = 1)');
      _db.execute('DELETE FROM nodes WHERE is_trashed = 1');
      _db.execute('DELETE FROM workspaces WHERE is_deleted = 1');
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    } finally {
      _db.execute('PRAGMA foreign_keys = ON;');
    }
  }

  Future<List<FileNode>> getBreadcrumbs(String nodeId) async {
    final trail = <FileNode>[];
    final seen = <String>{};
    String? currentId = nodeId;

    // BUG 21 FIX: Guard against circular parent references with 'seen' set
    while (currentId != null && seen.add(currentId)) {
      final node = await getNode(currentId);
      if (node == null) break;
      trail.insert(0, node);
      currentId = node.parentId;
    }

    return trail;
  }

  // -------------------------------------------------------------
  // Chunk Operations
  // -------------------------------------------------------------

  Future<void> insertChunks(List<FileChunk> chunks, {bool inTransaction = false}) async {
    if (chunks.isEmpty) return;
    if (!inTransaction) _db.execute('BEGIN TRANSACTION');
    try {
      final stmt = _db.prepare('''
        INSERT OR REPLACE INTO chunks (
          id, node_id, chunk_index, remote_message_id, remote_file_id,
          size_bytes, sha256_hash, iv_hex
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''');

      for (final chunk in chunks) {
        stmt.execute([
          chunk.id,
          chunk.nodeId,
          chunk.chunkIndex,
          chunk.remoteMessageId,
          chunk.remoteFileId,
          chunk.sizeBytes,
          chunk.sha256Hash,
          chunk.ivHex,
        ]);
      }
      stmt.dispose();
      if (!inTransaction) _db.execute('COMMIT');
    } catch (_) {
      if (!inTransaction) _db.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<List<FileChunk>> getChunksForNode(String nodeId) async {
    final ResultSet result = _db.select(
      'SELECT * FROM chunks WHERE node_id = ? ORDER BY chunk_index ASC',
      [nodeId],
    );
    return result.map((row) {
      return FileChunk(
        id: row['id'] as String,
        nodeId: row['node_id'] as String,
        chunkIndex: row['chunk_index'] as int,
        remoteMessageId: row['remote_message_id'] as String,
        remoteFileId: row['remote_file_id'] as String,
        sizeBytes: row['size_bytes'] as int,
        sha256Hash: row['sha256_hash'] as String,
        ivHex: row['iv_hex'] as String,
      );
    }).toList();
  }

  // -------------------------------------------------------------
  // Transfer Task Operations
  // -------------------------------------------------------------

  Future<void> saveTransferTask(TransferTask task) async {
    final stmt = _db.prepare('''
      INSERT OR REPLACE INTO transfer_tasks (
        id, node_id, file_name, type, status, progress,
        bytes_transferred, total_bytes, error_message, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');

    stmt.execute([
      task.id,
      task.nodeId,
      task.fileName,
      task.type.name,
      task.status.name,
      task.progress,
      task.bytesTransferred,
      task.totalBytes,
      task.errorMessage,
      task.createdAt.millisecondsSinceEpoch,
      task.updatedAt.millisecondsSinceEpoch,
    ]);
    stmt.dispose();
  }

  Future<List<TransferTask>> listTransferTasks({bool activeOnly = false}) async {
    final where = activeOnly
        ? "WHERE status IN ('queued', 'running', 'paused')"
        : '';
    final ResultSet result = _db.select('''
      SELECT * FROM transfer_tasks
      $where
      ORDER BY updated_at DESC
    ''');

    return result.map((row) {
      return TransferTask(
        id: row['id'] as String,
        nodeId: row['node_id'] as String,
        fileName: row['file_name'] as String,
        type: TransferType.values.firstWhere((e) => e.name == row['type']),
        status: TransferStatus.values.firstWhere((e) => e.name == row['status']),
        progress: (row['progress'] as num).toDouble(),
        bytesTransferred: row['bytes_transferred'] as int,
        totalBytes: row['total_bytes'] as int,
        errorMessage: row['error_message'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
      );
    }).toList();
  }

  Future<void> deleteTransferTask(String taskId) async {
    _db.execute('DELETE FROM transfer_tasks WHERE id = ?', [taskId]);
  }

  // -------------------------------------------------------------
  // Storage Usage & Categories
  // -------------------------------------------------------------

  Future<StorageUsageStats> getStorageUsage() async {
    final ResultSet files = _db.select('''
      SELECT mime_type, size_bytes FROM nodes WHERE type = 'file' AND is_trashed = 0
    ''');

    final ResultSet folderCount = _db.select('''
      SELECT COUNT(*) as count FROM nodes WHERE type = 'folder' AND is_trashed = 0
    ''');

    int totalBytes = 0;
    int images = 0;
    int videos = 0;
    int audio = 0;
    int documents = 0;
    int archives = 0;
    int other = 0;

    for (final row in files) {
      final size = row['size_bytes'] as int;
      final mime = (row['mime_type'] as String?)?.toLowerCase() ?? '';
      totalBytes += size;

      if (mime.startsWith('image/')) {
        images += size;
      } else if (mime.startsWith('video/')) {
        videos += size;
      } else if (mime.startsWith('audio/')) {
        audio += size;
      } else if (mime.contains('pdf') ||
          mime.contains('text') ||
          mime.contains('document') ||
          mime.contains('word') ||
          mime.contains('excel')) {
        documents += size;
      } else if (mime.contains('zip') ||
          mime.contains('tar') ||
          mime.contains('compressed') ||
          mime.contains('archive')) {
        archives += size;
      } else {
        other += size;
      }
    }

    return StorageUsageStats(
      totalBytes: totalBytes,
      imagesBytes: images,
      videosBytes: videos,
      audioBytes: audio,
      documentsBytes: documents,
      archivesBytes: archives,
      otherBytes: other,
      totalFiles: files.length,
      totalFolders: folderCount.first['count'] as int,
    );
  }

  // -------------------------------------------------------------
  // Cloud Snapshot Serialization & Disaster Recovery
  // -------------------------------------------------------------

  /// Exports the entire virtual index (nodes + chunks + workspaces) to a serialized JSON string.
  /// Ready to be encrypted on-device with the Master Key and pinned to Telegram.
  Future<String> exportSnapshotJson() async {
    final ResultSet allNodes = _db.select('SELECT * FROM nodes');
    final ResultSet allChunks = _db.select('SELECT * FROM chunks');
    final ResultSet allWorkspaces = _db.select('SELECT * FROM workspaces ORDER BY created_at ASC');

    final nodesList = allNodes.map((r) => _rowToNode(r).toJson()).toList();
    final chunksList = allChunks.map((r) {
      return {
        'id': r['id'],
        'nodeId': r['node_id'],
        'chunkIndex': r['chunk_index'],
        'remoteMessageId': r['remote_message_id'],
        'remoteFileId': r['remote_file_id'],
        'sizeBytes': r['size_bytes'],
        'sha256Hash': r['sha256_hash'],
        'ivHex': r['iv_hex'],
      };
    }).toList();
    final workspacesList = allWorkspaces.map((r) {
      return {
        'id': r['id'],
        'name': r['name'],
        'description': r['description'],
        'iconCode': r['icon_code'],
        'createdAt': r['created_at'],
        'isEncrypted': r.containsKey('is_encrypted') && r['is_encrypted'] != null ? r['is_encrypted'] : 1,
        'isDeleted': r.containsKey('is_deleted') && r['is_deleted'] != null ? r['is_deleted'] : 0,
      };
    }).toList();

    final payload = {
      'version': 1,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'nodes': nodesList,
      'chunks': chunksList,
      'workspaces': workspacesList,
    };

    return json.encode(payload);
  }

  /// Restores the entire virtual index from a decrypted snapshot JSON string.
  /// BUG 10 FIX: Execute entire restore in a transaction to prevent data loss on error.
  Future<void> restoreFromSnapshotJson(String jsonStr) async {
    final Map<String, dynamic> data = json.decode(jsonStr) as Map<String, dynamic>;
    final nodesRaw = data['nodes'] as List<dynamic>? ?? [];
    final chunksRaw = data['chunks'] as List<dynamic>? ?? [];
    final workspacesRaw = data['workspaces'] as List<dynamic>?;
    final exportedAt = (data['exportedAt'] as num?)?.toInt();

    _db.execute('PRAGMA foreign_keys = OFF;');
    _db.execute('BEGIN TRANSACTION');
    try {
      _db.execute('DELETE FROM chunks');
      _db.execute('DELETE FROM nodes');

      if (workspacesRaw != null && workspacesRaw.isNotEmpty) {
        _db.execute('DELETE FROM workspaces');
        for (final item in workspacesRaw) {
          final w = item as Map<String, dynamic>;
          _db.execute(
            'INSERT OR REPLACE INTO workspaces (id, name, description, icon_code, created_at, is_encrypted, is_deleted) VALUES (?, ?, ?, ?, ?, ?, ?)',
            [
              w['id'] as String,
              w['name'] as String,
              w['description'] as String? ?? 'Personal space',
              (w['iconCode'] as num?)?.toInt() ?? Icons.folder_outlined.codePoint,
              (w['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
              (w['isEncrypted'] as num?)?.toInt() ?? 1,
              (w['isDeleted'] as num?)?.toInt() ?? 0,
            ],
          );
        }
      }

      for (final item in nodesRaw) {
        final node = FileNode.fromJson(item as Map<String, dynamic>);
        await insertNode(node);
      }

      final chunks = chunksRaw.map((c) {
        final m = c as Map<String, dynamic>;
        return FileChunk(
          id: m['id'] as String,
          nodeId: m['nodeId'] as String,
          chunkIndex: (m['chunkIndex'] as num).toInt(),
          remoteMessageId: m['remoteMessageId'] as String,
          remoteFileId: m['remoteFileId'] as String,
          sizeBytes: (m['sizeBytes'] as num).toInt(),
          sha256Hash: m['sha256Hash'] as String,
          ivHex: m['ivHex'] as String,
        );
      }).toList();

      await insertChunks(chunks, inTransaction: true);
      if (exportedAt != null) {
        _db.execute(
          'INSERT OR REPLACE INTO sync_meta (key, value) VALUES (?, ?)',
          ['last_synced_at', exportedAt.toString()],
        );
      }
      _db.execute(
        'INSERT OR REPLACE INTO sync_meta (key, value) VALUES (?, ?)',
        ['sync_dirty', '0'],
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    } finally {
      _db.execute('PRAGMA foreign_keys = ON;');
    }
  }

  /// Wipes all tables locally.
  Future<void> wipeAllLocalData() async {
    _db.execute('DELETE FROM transfer_tasks');
    _db.execute('DELETE FROM chunks');
    _db.execute('DELETE FROM nodes');
    _db.execute('DELETE FROM workspaces');
    _db.execute('DELETE FROM sync_meta');
  }

  void close() {
    _db.dispose();
  }

  FileNode _rowToNode(Row row) {
    return FileNode(
      id: row['id'] as String,
      parentId: row['parent_id'] as String?,
      name: row['name'] as String,
      type: NodeType.values.firstWhere((e) => e.name == row['type']),
      sizeBytes: row['size_bytes'] as int,
      mimeType: row['mime_type'] as String?,
      contentHash: row['content_hash'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(row['modified_at'] as int),
      isFavorite: (row['is_favorite'] as int) == 1,
      isTrashed: (row['is_trashed'] as int) == 1,
      trashedAt: row['trashed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['trashed_at'] as int)
          : null,
      syncState: SyncState.values.firstWhere(
        (e) => e.name == row['sync_state'],
        orElse: () => SyncState.synced,
      ),
      tags: row.containsKey('tags') && row['tags'] != null && row['tags'] is String
          ? (row['tags'] as String).split(',').where((s) => s.isNotEmpty).toList()
          : const [],
      workspaceId: row.containsKey('workspace_id') && row['workspace_id'] != null && row['workspace_id'] is String
          ? (row['workspace_id'] as String)
          : 'personal',
      isPinnedOffline: row.containsKey('is_pinned_offline') && row['is_pinned_offline'] != null
          ? (row['is_pinned_offline'] as int) == 1
          : false,
    );
  }
}
