/// Model representing an available application release update.
class AppUpdateInfo {
  final String version;
  final String title;
  final List<String> highlights;
  final String? fullBody;
  final String downloadUrl;
  final DateTime publishedAt;
  final bool isMandatory;
  final bool isTestRelease;

  const AppUpdateInfo({
    required this.version,
    required this.title,
    required this.highlights,
    this.fullBody,
    required this.downloadUrl,
    required this.publishedAt,
    this.isMandatory = false,
    this.isTestRelease = false,
  });
}
