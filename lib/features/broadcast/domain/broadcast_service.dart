import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../../update/domain/update_service.dart';
import 'broadcast_model.dart';

const _channel = MethodChannel('com.filo.vault.filo/transfers');

class BroadcastState {
  final AdminBroadcast? broadcast;
  final AppUpdateDetails? update;
  final bool isUpdateCollapsed;
  final bool isLoading;

  const BroadcastState({
    this.broadcast,
    this.update,
    this.isUpdateCollapsed = false,
    this.isLoading = false,
  });

  BroadcastState copyWith({
    AdminBroadcast? broadcast,
    bool clearBroadcast = false,
    AppUpdateDetails? update,
    bool clearUpdate = false,
    bool? isUpdateCollapsed,
    bool? isLoading,
  }) {
    return BroadcastState(
      broadcast: clearBroadcast ? null : (broadcast ?? this.broadcast),
      update: clearUpdate ? null : (update ?? this.update),
      isUpdateCollapsed: isUpdateCollapsed ?? this.isUpdateCollapsed,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class BroadcastNotifier extends StateNotifier<BroadcastState> {
  static const String _defaultReleasesUrl = 'https://github.com/pr4xh4r/filo/releases';

  final http.Client _client;
  final FlutterSecureStorage _storage;

  static const _keyDismissedBroadcast = 'filo_dismissed_broadcast_id';
  static const _keyUpdateCollapsed = 'filo_update_collapsed';

  BroadcastNotifier({
    http.Client? client,
    FlutterSecureStorage? storage,
  })  : _client = client ?? http.Client(),
        _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(
                encryptedSharedPreferences: true,
              ),
            ),
        super(const BroadcastState(isLoading: true)) {
    refresh();
  }

  /// Validates that [url] uses strict HTTPS, belongs to a trusted GitHub host,
  /// and targets the official `/pr4xh4r/filo` repository when hosted on GitHub.
  static bool isTrustedUrl(String url) => UpdateService.isTrustedUrl(url);

  /// Refreshes the broadcast and version updates manifest.
  /// If [forceTest] is true, populates realistic test broadcast and update data for user verification.
  Future<void> refresh({bool forceTest = false}) async {
    state = state.copyWith(isLoading: true);

    if (forceTest) {
      state = state.copyWith(
        broadcast: AdminBroadcast(
          id: 'test_announcement_101',
          title: '📢 Admin Announcement: Welcome to Filo!',
          message:
              'All your files are safely encrypted with zero-knowledge AES-256-GCM. You can customize workspaces or sync via Telegram.',
          actionTitle: 'View Guide',
          actionUrl: 'https://github.com/pr4xh4r/filo',
          isDismissible: true,
          priority: 'normal',
          publishedAt: DateTime.now(),
        ),
        update: const AppUpdateDetails(
          latestVersion: '1.0.1',
          title: 'Filo v1.0.1 Released',
          changelog: [
            '⚡ 2x faster parallel chunk upload and streaming',
            '🛡️ Automatic cloud snapshot sync pinned to channel filo',
            '📲 Instant QR vault pairing between devices',
            '🔄 Background transfer resilience with native Android service',
          ],
          downloadUrl: _defaultReleasesUrl,
          isMandatory: false,
        ),
        isUpdateCollapsed: false,
        isLoading: false,
      );
      return;
    }

    try {
      final collapsedStr = await _storage.read(key: _keyUpdateCollapsed);
      final isCollapsed = collapsedStr == 'true';

      final response = await _client.get(
        Uri.parse(AppConfig.broadcastManifestUrl),
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final manifest = BroadcastManifest.fromJson(data);

        // Check if broadcast was already dismissed by the user
        AdminBroadcast? activeBroadcast = manifest.broadcast;
        if (activeBroadcast != null && activeBroadcast.isDismissible) {
          final dismissedId = await _storage.read(key: _keyDismissedBroadcast);
          if (dismissedId == activeBroadcast.id) {
            activeBroadcast = null;
          }
        }
        if (activeBroadcast != null &&
            activeBroadcast.actionUrl != null &&
            activeBroadcast.actionUrl!.isNotEmpty &&
            !isTrustedUrl(activeBroadcast.actionUrl!)) {
          activeBroadcast = AdminBroadcast(
            id: activeBroadcast.id,
            title: activeBroadcast.title,
            message: activeBroadcast.message,
            actionTitle: null,
            actionUrl: null,
            isDismissible: activeBroadcast.isDismissible,
            priority: activeBroadcast.priority,
            publishedAt: activeBroadcast.publishedAt,
          );
        }

        // Check if update is strictly newer than current app version
        AppUpdateDetails? activeUpdate = manifest.update;
        if (activeUpdate != null) {
          final isNewer = UpdateService.isNewerVersion(
            activeUpdate.latestVersion,
            AppConfig.appVersion,
          );
          if (!isNewer) {
            activeUpdate = null;
          } else if (!isTrustedUrl(activeUpdate.downloadUrl)) {
            activeUpdate = AppUpdateDetails(
              latestVersion: activeUpdate.latestVersion,
              title: activeUpdate.title,
              changelog: activeUpdate.changelog,
              downloadUrl: _defaultReleasesUrl,
              isMandatory: activeUpdate.isMandatory,
            );
          }
        }

        state = state.copyWith(
          broadcast: activeBroadcast,
          clearBroadcast: activeBroadcast == null,
          update: activeUpdate,
          clearUpdate: activeUpdate == null,
          isUpdateCollapsed: isCollapsed,
          isLoading: false,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      debugPrint('BroadcastService refresh error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  /// Dismisses an admin broadcast so the user is never bothered by this ID again.
  Future<void> dismissBroadcast(String id) async {
    await _storage.write(key: _keyDismissedBroadcast, value: id);
    state = state.copyWith(clearBroadcast: true);
  }

  /// Toggles whether the update banner is expanded or minimized as a compact chip.
  Future<void> toggleCollapseUpdate(bool collapsed) async {
    await _storage.write(key: _keyUpdateCollapsed, value: collapsed ? 'true' : 'false');
    state = state.copyWith(isUpdateCollapsed: collapsed);
  }

  /// Launches a verified link in the native browser after enforcing host allowlist.
  static Future<void> openUrl(String url) async {
    final trimmed = url.trim();
    if (!isTrustedUrl(trimmed)) {
      return;
    }
    try {
      await _channel.invokeMethod('openUrl', {'url': trimmed});
    } catch (_) {
      Clipboard.setData(ClipboardData(text: trimmed));
    }
  }
}

final broadcastNotifierProvider =
    StateNotifierProvider<BroadcastNotifier, BroadcastState>((ref) {
  return BroadcastNotifier();
});
