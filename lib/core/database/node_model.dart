/// Type of virtual filesystem node.
enum NodeType { file, folder }

/// Synchronization state with the Telegram cloud vault.
enum SyncState { localOnly, uploading, synced, modified, deleting }

/// Represents a virtual file or folder node stored in the local encrypted index.
class FileNode {
  final String id;
  final String? parentId;
  final String name;
  final NodeType type;
  final int sizeBytes;
  final String? mimeType;
  final String? contentHash; // SHA-256 for duplicate detection
  final DateTime createdAt;
  final DateTime modifiedAt;
  final bool isFavorite;
  final bool isTrashed;
  final DateTime? trashedAt;
  final SyncState syncState;
  final List<String> tags;
  final String workspaceId;

  const FileNode({
    required this.id,
    this.parentId,
    required this.name,
    required this.type,
    this.sizeBytes = 0,
    this.mimeType,
    this.contentHash,
    required this.createdAt,
    required this.modifiedAt,
    this.isFavorite = false,
    this.isTrashed = false,
    this.trashedAt,
    this.syncState = SyncState.synced,
    this.tags = const [],
    this.workspaceId = 'personal',
  });

  bool get isFolder => type == NodeType.folder;
  bool get isFile => type == NodeType.file;

  FileNode copyWith({
    String? id,
    String? parentId,
    String? name,
    NodeType? type,
    int? sizeBytes,
    String? mimeType,
    String? contentHash,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? isFavorite,
    bool? isTrashed,
    DateTime? trashedAt,
    SyncState? syncState,
    List<String>? tags,
    String? workspaceId,
  }) {
    return FileNode(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      type: type ?? this.type,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      mimeType: mimeType ?? this.mimeType,
      contentHash: contentHash ?? this.contentHash,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      isTrashed: isTrashed ?? this.isTrashed,
      trashedAt: trashedAt ?? this.trashedAt,
      syncState: syncState ?? this.syncState,
      tags: tags ?? this.tags,
      workspaceId: workspaceId ?? this.workspaceId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'parentId': parentId,
      'name': name,
      'type': type.name,
      'sizeBytes': sizeBytes,
      'mimeType': mimeType,
      'contentHash': contentHash,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'modifiedAt': modifiedAt.millisecondsSinceEpoch,
      'isFavorite': isFavorite ? 1 : 0,
      'isTrashed': isTrashed ? 1 : 0,
      'trashedAt': trashedAt?.millisecondsSinceEpoch,
      'syncState': syncState.name,
      'tags': tags.join(','),
      'workspaceId': workspaceId,
    };
  }

  factory FileNode.fromJson(Map<String, dynamic> json) {
    return FileNode(
      id: json['id'] as String,
      parentId: json['parentId'] as String?,
      name: json['name'] as String,
      type: NodeType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => NodeType.file,
      ),
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      mimeType: json['mimeType'] as String?,
      contentHash: json['contentHash'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      modifiedAt: DateTime.fromMillisecondsSinceEpoch(json['modifiedAt'] as int),
      isFavorite: (json['isFavorite'] as int? ?? 0) == 1,
      isTrashed: (json['isTrashed'] as int? ?? 0) == 1,
      trashedAt: json['trashedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['trashedAt'] as int)
          : null,
      syncState: SyncState.values.firstWhere(
        (e) => e.name == json['syncState'],
        orElse: () => SyncState.synced,
      ),
      tags: json['tags'] != null
          ? (json['tags'] as String).split(',').where((s) => s.isNotEmpty).toList()
          : const [],
      workspaceId: (json['workspaceId'] as String?) ?? 'personal',
    );
  }
}
