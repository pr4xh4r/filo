import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import 'update_model.dart';

/// Riverpod provider for UpdateService
final updateServiceProvider = Provider<UpdateService>((ref) {
  return UpdateService();
});

/// Zero-knowledge, serverless in-app update checker querying GitHub Releases.
class UpdateService {
  static const String _repoReleasesUrl =
      'https://api.github.com/repos/pr4xh4r/filo/releases/latest';

  static const _channel = MethodChannel('com.filo.vault.filo/transfers');

  final http.Client _client;

  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  /// Compares two semantic version strings (e.g. '1.0.1' vs '1.0.0').
  /// Returns true if [remote] is strictly newer than [current].
  static bool isNewerVersion(String remote, String current) {
    try {
      final cleanRemote = remote.replaceAll(RegExp(r'[^0-9.]'), '');
      final cleanCurrent = current.replaceAll(RegExp(r'[^0-9.]'), '');

      final remoteParts = cleanRemote.split('.').map(int.parse).toList();
      final currentParts = cleanCurrent.split('.').map(int.parse).toList();

      for (int i = 0; i < remoteParts.length && i < currentParts.length; i++) {
        if (remoteParts[i] > currentParts[i]) return true;
        if (remoteParts[i] < currentParts[i]) return false;
      }
      return remoteParts.length > currentParts.length;
    } catch (_) {
      return false;
    }
  }

  /// Checks for available updates from GitHub.
  /// If [forceTest] is true, returns a simulated production update object for verification.
  Future<AppUpdateInfo?> checkForUpdate({bool forceTest = false}) async {
    if (forceTest) {
      return AppUpdateInfo(
        version: '1.0.1-preview',
        title: 'Filo v1.0.1 • Fast Chunk Streaming & UI Polish',
        highlights: [
          '⚡ 120fps hardware-accelerated animations & isolate crypto',
          '🛡️ Zero-knowledge cloud snapshot sync pinned to channel filo',
          '📲 Instant QR vault pairing between devices',
          '🔄 Background transfer resilience with native Android service',
          '📱 Dynamic Island real-time upload progress pill',
        ],
        fullBody: 'This update includes major stability fixes and performance optimizations.',
        downloadUrl: 'https://github.com/pr4xh4r/filo/releases',
        publishedAt: DateTime.now(),
        isTestRelease: true,
      );
    }

    try {
      final response = await _client.get(
        Uri.parse(_repoReleasesUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String? ?? '';
      final remoteVersion = tagName.replaceAll(RegExp(r'^[vV]'), '');

      if (!isNewerVersion(remoteVersion, AppConfig.appVersion)) {
        return null; // Current version is up to date
      }

      // Extract APK download URL if attached as a release asset
      String downloadUrl = data['html_url'] as String? ?? 'https://github.com/pr4xh4r/filo/releases';
      final assets = data['assets'] as List<dynamic>?;
      if (assets != null && assets.isNotEmpty) {
        for (final asset in assets) {
          final name = asset['name'] as String? ?? '';
          if (name.endsWith('.apk')) {
            downloadUrl = asset['browser_download_url'] as String? ?? downloadUrl;
            break;
          }
        }
      }

      // Parse release notes into bullet points
      final body = data['body'] as String? ?? '';
      final highlights = <String>[];
      for (final line in body.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.startsWith('- ') || trimmed.startsWith('* ') || trimmed.startsWith('• ')) {
          highlights.add(trimmed.substring(2).trim());
        }
      }

      if (highlights.isEmpty) {
        highlights.add('Performance improvements and bug fixes');
      }

      return AppUpdateInfo(
        version: remoteVersion,
        title: (data['name'] as String?)?.isNotEmpty == true
            ? data['name'] as String
            : 'Filo v$remoteVersion',
        highlights: highlights,
        fullBody: body,
        downloadUrl: downloadUrl,
        publishedAt: DateTime.tryParse(data['published_at'] as String? ?? '') ?? DateTime.now(),
        isTestRelease: false,
      );
    } catch (e) {
      debugPrint('UpdateService check error: $e');
      return null;
    }
  }

  /// Opens the release or download URL in the device's native browser.
  static Future<void> openDownloadUrl(String url) async {
    try {
      await _channel.invokeMethod('openUrl', {'url': url});
    } catch (_) {
      // Fallback
      Clipboard.setData(ClipboardData(text: url));
    }
  }
}
