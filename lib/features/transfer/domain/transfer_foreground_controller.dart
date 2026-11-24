import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/transfer_model.dart';
import '../presentation/providers/transfer_provider.dart';

/// MethodChannel for coordinating with native foreground services.
const _channel = MethodChannel('com.filo.vault.filo/transfers');

/// Riverpod provider for the background transfer keep-alive controller.
final transferForegroundControllerProvider =
    Provider<TransferForegroundController>((ref) {
  final controller = TransferForegroundController();
  // Listen to active transfers and notify the native service
  ref.listen<List<TransferTask>>(activeTransfersProvider, (previous, next) {
    controller.onActiveTransfersChanged(next);
  });
  ref.onDispose(controller.dispose);
  return controller;
});

/// Manages native Android/iOS background transfer notifications and foreground service keep-alive.
class TransferForegroundController {
  bool _isServiceActive = false;

  void onActiveTransfersChanged(List<TransferTask> activeTasks) {
    if (!kIsWeb && Platform.isAndroid) {
      if (activeTasks.isNotEmpty) {
        final totalCount = activeTasks.length;
        const title = 'Filo Secure Sync';
        final content = totalCount == 1
            ? 'Transferring ${activeTasks.first.fileName}...'
            : 'Transferring $totalCount items in background...';

        _startOrUpdateNativeService(title, content);
      } else if (_isServiceActive) {
        _stopNativeService();
      }
    }
  }

  Future<void> _startOrUpdateNativeService(String title, String content) async {
    try {
      await _channel.invokeMethod('startForegroundTransfer', {
        'title': title,
        'content': content,
      });
      _isServiceActive = true;
    } catch (e) {
      debugPrint('TransferForegroundController: startForegroundTransfer error: $e');
    }
  }

  Future<void> _stopNativeService() async {
    try {
      await _channel.invokeMethod('stopForegroundTransfer');
      _isServiceActive = false;
    } catch (e) {
      debugPrint('TransferForegroundController: stopForegroundTransfer error: $e');
    }
  }

  void dispose() {
    if (_isServiceActive) {
      _stopNativeService();
    }
  }
}
