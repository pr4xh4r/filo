/// Represents a single encrypted multi-part chunk stored in Telegram.
class FileChunk {
  final String id;
  final String nodeId;
  final int chunkIndex;
  final String remoteMessageId;
  final String remoteFileId;
  final int sizeBytes;
  final String sha256Hash;
  final String ivHex;

  const FileChunk({
    required this.id,
    required this.nodeId,
    required this.chunkIndex,
    required this.remoteMessageId,
    required this.remoteFileId,
    required this.sizeBytes,
    required this.sha256Hash,
    required this.ivHex,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nodeId': nodeId,
      'chunkIndex': chunkIndex,
      'remoteMessageId': remoteMessageId,
      'remoteFileId': remoteFileId,
      'sizeBytes': sizeBytes,
      'sha256Hash': sha256Hash,
      'ivHex': ivHex,
    };
  }

  factory FileChunk.fromJson(Map<String, dynamic> json) {
    return FileChunk(
      id: json['id'] as String,
      nodeId: json['nodeId'] as String,
      chunkIndex: (json['chunkIndex'] as num).toInt(),
      remoteMessageId: json['remoteMessageId'] as String,
      remoteFileId: json['remoteFileId'] as String,
      sizeBytes: (json['sizeBytes'] as num).toInt(),
      sha256Hash: json['sha256Hash'] as String,
      ivHex: json['ivHex'] as String,
    );
  }
}
