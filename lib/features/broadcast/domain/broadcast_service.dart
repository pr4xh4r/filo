import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
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
  final http.Client _client;
  final FlutterSecureStorage _storage;

  static const _keyDismissedBroadcast = 'filo_dismissed_broadcast_id';
  static const _keyUpdateCollapsed = 'filo_update_collapsed';

  BroadcastNotifier({
    http.Client? client,
    FlutterSecureStorage? storage,
  })  : _client = client ?? http.Client(),
        _storage = storage ?? const FlutterSecureStorage(),
        super(const BroadcastState(isLoading: true)) {
    refresh();
  }

  /// Refreshes the broadcast and version updates manifest.
  /// If [forceTest] is true, populates realistic test broadcast and update data for user verification.
  Future<void> refresh({bool forceTest = false}) async {
    state = state.copyWith(isLoading: true);

    if (forceTest) {
      state = state.copyWith(
        broadcast: const AdminBroadcast(
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
          downloadUrl: 'https://github.com/pr4xh4r/filo/releases',
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

        // Check if update is strictly newer than current app version
        AppUpdateDetails? activeUpdate = manifest.update;
        if (activeUpdate != null) {
          final isNewer = _isNewerVersion(activeUpdate.latestVersion, AppConfig.appVersion);
          if (!isNewer) {
            activeUpdate = null;
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

  /// Launches a link in the native browser.
  static Future<void> openUrl(String url) async {
    try {
      await _channel.invokeMethod('openUrl', {'url': url});
    } catch (_) {
      Clipboard.setData(ClipboardData(text: url));
    }
  }

  bool _isNewerVersion(String remote, String current) {
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
}

final broadcastNotifierProvider =
    StateNotifierProvider<BroadcastNotifier, BroadcastState>((ref) {
  return BroadcastNotifier();
});
