enum TransferType { upload, download }
enum TransferStatus { queued, running, paused, completed, failed }

/// Represents an asynchronous background file transfer in the queue.
class TransferTask {
  final String id;
  final String nodeId;
  final String fileName;
  final TransferType type;
  final TransferStatus status;
  final double progress; // 0.0 to 1.0
  final int bytesTransferred;
  final int totalBytes;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  const TransferTask({
    required this.id,
    required this.nodeId,
    required this.fileName,
    required this.type,
    required this.status,
    this.progress = 0.0,
    this.bytesTransferred = 0,
    required this.totalBytes,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
  });

  TransferTask copyWith({
    String? id,
    String? nodeId,
    String? fileName,
    TransferType? type,
    TransferStatus? status,
    double? progress,
    int? bytesTransferred,
    int? totalBytes,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TransferTask(
      id: id ?? this.id,
      nodeId: nodeId ?? this.nodeId,
      fileName: fileName ?? this.fileName,
      type: type ?? this.type,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nodeId': nodeId,
      'fileName': fileName,
      'type': type.name,
      'status': status.name,
      'progress': progress,
      'bytesTransferred': bytesTransferred,
      'totalBytes': totalBytes,
      'errorMessage': errorMessage,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory TransferTask.fromJson(Map<String, dynamic> json) {
    return TransferTask(
      id: json['id'] as String,
      nodeId: json['nodeId'] as String,
      fileName: json['fileName'] as String? ?? 'file',
      type: TransferType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => TransferType.upload,
      ),
      status: TransferStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => TransferStatus.queued,
      ),
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      bytesTransferred: (json['bytesTransferred'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      errorMessage: json['errorMessage'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
    );
  }
}
