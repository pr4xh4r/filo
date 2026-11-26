import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:filo/core/database/node_model.dart';
import 'package:filo/core/database/transfer_model.dart';
import 'package:filo/features/auth/presentation/providers/auth_provider.dart';
import 'package:filo/features/files/presentation/providers/file_browser_provider.dart';
import 'package:filo/features/sync/domain/index_sync_service.dart';
import 'package:filo/features/transfer/data/transfer_manager.dart';

final transferManagerProvider = Provider<TransferManager>((ref) {
  final storage = ref.watch(storageBackendProvider);
  final fileRepo = ref.watch(fileRepositoryProvider);

  final manager = TransferManager(
    storageBackend: storage,
    fileRepository: fileRepo,
  );

  // BUG 28 FIX: Dispose the manager (closes StreamController) when provider is disposed
  ref.onDispose(manager.dispose);

  return manager;
});

class TransferQueueNotifier extends StateNotifier<List<TransferTask>> {
  final TransferManager _manager;
  final Ref _ref;
  // BUG 15 FIX: Store subscription reference so it can be cancelled on dispose
  late final StreamSubscription<List<TransferTask>> _subscription;

  TransferQueueNotifier({
    required TransferManager manager,
    required Ref ref,
  })  : _manager = manager,
        _ref = ref,
        super([]) {
    _subscription = _manager.tasksStream.listen((tasks) {
      state = tasks;
    });
  }

  @override
  void dispose() {
    // BUG 15 FIX: Cancel subscription to avoid memory/event leak
    _subscription.cancel();
    super.dispose();
  }

  Future<FileNode?> pickAndUploadFile({
    String? parentId,
    String workspaceId = 'personal',
    List<String> tags = const [],
    bool? isEncrypted,
    void Function(FileNode node)? onTaskCreated,
  }) async {
    final authState = _ref.read(authNotifierProvider);
    if (authState.masterKey == null) {
      throw Exception('Vault is locked. Unlock vault before uploading.');
    }

    final uploaded = await _manager.pickAndUploadFile(
      masterKey: authState.masterKey!,
      parentId: parentId,
      workspaceId: workspaceId,
      tags: tags,
      isEncrypted: isEncrypted,
      onTaskCreated: onTaskCreated,
    );

    if (uploaded != null) {
      _ref.read(indexSyncServiceProvider).triggerAutoSync(masterKey: authState.masterKey!);
    }
    return uploaded;
  }

  Future<List<FileNode>> pickAndUploadFiles({
    String? parentId,
    String workspaceId = 'personal',
    List<String> tags = const [],
    bool? isEncrypted,
    void Function(FileNode node)? onTaskCreated,
  }) async {
    final authState = _ref.read(authNotifierProvider);
    if (authState.masterKey == null) {
      throw Exception('Vault is locked. Unlock vault before uploading.');
    }

    final uploadedList = await _manager.pickAndUploadFiles(
      masterKey: authState.masterKey!,
      parentId: parentId,
      workspaceId: workspaceId,
      tags: tags,
      isEncrypted: isEncrypted,
      onTaskCreated: onTaskCreated,
      onFileUploaded: (_) {
        _ref.read(indexSyncServiceProvider).triggerAutoSync(masterKey: authState.masterKey!);
      },
    );

    if (uploadedList.isNotEmpty) {
      _ref.read(indexSyncServiceProvider).triggerAutoSync(masterKey: authState.masterKey!);
    }
    return uploadedList;
  }

  Future<FileNode> uploadLocalFile({
    required File file,
    String? parentId,
    String workspaceId = 'personal',
    List<String> tags = const [],
    String? customName,
    bool? isEncrypted,
    void Function(FileNode node)? onTaskCreated,
  }) async {
    final authState = _ref.read(authNotifierProvider);
    if (authState.masterKey == null) {
      throw Exception('Vault is locked. Unlock vault before uploading.');
    }

    final node = await _manager.uploadLocalFile(
      file: file,
      masterKey: authState.masterKey!,
      parentId: parentId,
      workspaceId: workspaceId,
      tags: tags,
      customName: customName,
      isEncrypted: isEncrypted,
      onTaskCreated: onTaskCreated,
    );

    _ref.read(indexSyncServiceProvider).triggerAutoSync(masterKey: authState.masterKey!);
    return node;
  }

  Future<List<FileNode>> uploadLocalFiles({
    required List<File> files,
    String? parentId,
    String workspaceId = 'personal',
    List<String> tags = const [],
    bool? isEncrypted,
    void Function(FileNode node)? onTaskCreated,
  }) async {
    final authState = _ref.read(authNotifierProvider);
    if (authState.masterKey == null) {
      throw Exception('Vault is locked. Unlock vault before uploading.');
    }

    final uploadedList = <FileNode>[];
    for (final file in files) {
      if (!file.existsSync()) continue;
      try {
        final node = await _manager.uploadLocalFile(
          file: file,
          masterKey: authState.masterKey!,
          parentId: parentId,
          workspaceId: workspaceId,
          tags: tags,
          isEncrypted: isEncrypted,
          onTaskCreated: onTaskCreated,
        );
        uploadedList.add(node);
        _ref.read(indexSyncServiceProvider).triggerAutoSync(masterKey: authState.masterKey!);
        await Future.delayed(const Duration(milliseconds: 350));
      } catch (e) {
        // Continue uploading remaining files
      }
    }

    if (uploadedList.isNotEmpty) {
      _ref.read(indexSyncServiceProvider).triggerAutoSync(masterKey: authState.masterKey!);
    }
    return uploadedList;
  }

  Future<void> shareDecryptedCopy(FileNode node) async {
    final authState = _ref.read(authNotifierProvider);
    if (authState.masterKey == null) {
      throw Exception('Vault is locked. Unlock vault to decrypt and share.');
    }

    return _manager.shareDecryptedCopy(node, authState.masterKey!);
  }

  Future<void> downloadFileToDevice(FileNode node) async {
    final authState = _ref.read(authNotifierProvider);
    if (authState.masterKey == null) {
      throw Exception('Vault is locked. Unlock vault before downloading.');
    }

    await _manager.downloadFileToDevice(node, authState.masterKey!);
  }
}

final transferQueueProvider =
    StateNotifierProvider<TransferQueueNotifier, List<TransferTask>>((ref) {
  final manager = ref.watch(transferManagerProvider);
  return TransferQueueNotifier(manager: manager, ref: ref);
});

/// Returns currently active/running transfers for badges and dynamic island animations.
final activeTransfersProvider = Provider<List<TransferTask>>((ref) {
  final tasks = ref.watch(transferQueueProvider);
  return tasks.where((t) => t.status == TransferStatus.running).toList();
});
