import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../files/presentation/providers/file_browser_provider.dart';
import '../../domain/vault_export_service.dart';
import 'transfer_provider.dart';

final vaultExportServiceProvider = Provider<VaultExportService>((ref) {
  final fileRepo = ref.watch(fileRepositoryProvider);
  final storage = ref.watch(storageBackendProvider);
  final transferManager = ref.watch(transferManagerProvider);
  return VaultExportService(
    fileRepository: fileRepo,
    storageBackend: storage,
    transferManager: transferManager,
  );
});

class VaultExportNotifier extends StateNotifier<VaultExportState> {
  final VaultExportService _service;
  final Ref _ref;

  VaultExportNotifier({
    required VaultExportService service,
    required Ref ref,
  })  : _service = service,
        _ref = ref,
        super(const VaultExportState()) {
    refreshCheckpoint();
  }

  Future<void> refreshCheckpoint() async {
    if (_service.isRunning) return;
    final cp = await _service.loadValidCheckpoint();
    if (!mounted) return;
    if (cp != null) {
      state = state.copyWith(
        status: cp.failedFiles.isNotEmpty
            ? VaultExportStatus.partialNeedsAction
            : VaultExportStatus.paused,
        completedFiles: cp.completedFileCount,
        totalFiles: cp.totalFiles,
        bytesTransferred: cp.completedBytes,
        totalBytes: cp.totalBytes,
        failedFiles: cp.failedFiles,
        resumableCheckpoint: cp,
        statusMessage:
            'Resumable export: ${cp.completedFileCount}/${cp.totalFiles} files ready',
      );
    } else if (state.status == VaultExportStatus.paused ||
        state.status == VaultExportStatus.partialNeedsAction) {
      state = const VaultExportState();
    }
  }

  Future<({int fileCount, int totalBytes})> estimateExportSize() {
    return _service.estimateExportSize();
  }

  Future<int?> getAvailableStorageBytes() {
    return _service.getAvailableStorageBytes();
  }

  Future<VaultExportState> startFreshExport({
    String? customDestinationDir,
  }) async {
    final masterKey = _requireMasterKey();
    return _service.runExport(
      masterKey: masterKey,
      customDestinationDir: customDestinationDir,
      onStateChanged: (next) {
        if (mounted) state = next;
      },
    );
  }

  Future<VaultExportState> resumeExport({
    bool finalizePartialOnly = false,
  }) async {
    final masterKey = _requireMasterKey();
    final cp =
        state.resumableCheckpoint ?? await _service.loadValidCheckpoint();
    if (cp == null) {
      return startFreshExport();
    }
    return _service.runExport(
      masterKey: masterKey,
      resumeCheckpoint: cp,
      finalizePartialOnly: finalizePartialOnly,
      onStateChanged: (next) {
        if (mounted) state = next;
      },
    );
  }

  void pauseOrCancelExport() {
    _service.requestCancel();
  }

  Future<void> discardResumableExport() async {
    if (_service.isRunning) {
      _service.requestCancel();
    }
    await _service.discardCheckpoint();
    if (mounted) {
      state = const VaultExportState();
    }
  }

  Uint8List _requireMasterKey() {
    final masterKey = _ref.read(authNotifierProvider).masterKey;
    if (masterKey == null) {
      throw StateError('Vault is locked. Unlock before exporting.');
    }
    return masterKey;
  }
}

final vaultExportProvider =
    StateNotifierProvider<VaultExportNotifier, VaultExportState>((ref) {
  final service = ref.watch(vaultExportServiceProvider);
  return VaultExportNotifier(service: service, ref: ref);
});
