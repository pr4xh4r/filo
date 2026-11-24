/// Represents an admin announcement broadcast to all users.
class AdminBroadcast {
  final String id;
  final String title;
  final String message;
  final String? actionTitle;
  final String? actionUrl;
  final bool isDismissible;
  final String priority; // 'normal', 'important', 'critical'
  final DateTime publishedAt;

  const AdminBroadcast({
    required this.id,
    required this.title,
    required this.message,
    this.actionTitle,
    this.actionUrl,
    this.isDismissible = true,
    this.priority = 'normal',
    required this.publishedAt,
  });

  factory AdminBroadcast.fromJson(Map<String, dynamic> json) {
    return AdminBroadcast(
      id: json['id'] as String? ?? 'broadcast_default',
      title: json['title'] as String? ?? 'Announcement',
      message: json['message'] as String? ?? '',
      actionTitle: json['action_title'] as String?,
      actionUrl: json['action_url'] as String?,
      isDismissible: json['is_dismissible'] as bool? ?? true,
      priority: json['priority'] as String? ?? 'normal',
      publishedAt: json.containsKey('published_at') && json['published_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['published_at'] as int)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'action_title': actionTitle,
        'action_url': actionUrl,
        'is_dismissible': isDismissible,
        'priority': priority,
        'published_at': publishedAt.millisecondsSinceEpoch,
      };
}

/// Represents an available application version release.
class AppUpdateDetails {
  final String latestVersion;
  final String title;
  final List<String> changelog;
  final String downloadUrl;
  final bool isMandatory;

  const AppUpdateDetails({
    required this.latestVersion,
    required this.title,
    required this.changelog,
    required this.downloadUrl,
    this.isMandatory = false,
  });

  factory AppUpdateDetails.fromJson(Map<String, dynamic> json) {
    final list = json['changelog'] as List<dynamic>?;
    return AppUpdateDetails(
      latestVersion: json['latest_version'] as String? ?? '1.0.0',
      title: json['title'] as String? ?? 'New Update Available',
      changelog: list != null ? list.map((e) => e.toString()).toList() : const [],
      downloadUrl: json['download_url'] as String? ?? 'https://github.com/pr4xh4r/filo/releases',
      isMandatory: json['is_mandatory'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'latest_version': latestVersion,
        'title': title,
        'changelog': changelog,
        'download_url': downloadUrl,
        'is_mandatory': isMandatory,
      };
}

/// Root manifest combining broadcast announcements and version updates.
class BroadcastManifest {
  final AdminBroadcast? broadcast;
  final AppUpdateDetails? update;

  const BroadcastManifest({
    this.broadcast,
    this.update,
  });

  factory BroadcastManifest.fromJson(Map<String, dynamic> json) {
    return BroadcastManifest(
      broadcast: json['broadcast'] != null
          ? AdminBroadcast.fromJson(json['broadcast'] as Map<String, dynamic>)
          : null,
      update: json['update'] != null
          ? AppUpdateDetails.fromJson(json['update'] as Map<String, dynamic>)
          : null,
    );
  }
}
