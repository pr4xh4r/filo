import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:filo/core/database/node_model.dart';
import 'package:filo/core/database/transfer_model.dart';
import 'package:filo/features/auth/presentation/providers/auth_provider.dart';
import 'package:filo/features/files/presentation/providers/file_browser_provider.dart';
import 'package:filo/features/transfer/data/transfer_manager.dart';

final transferManagerProvider = Provider<TransferManager>((ref) {
  final storage = ref.watch(storageBackendProvider);
  final fileRepo = ref.watch(fileRepositoryProvider);

  return TransferManager(
    storageBackend: storage,
    fileRepository: fileRepo,
  );
});

class TransferQueueNotifier extends StateNotifier<List<TransferTask>> {
  final TransferManager _manager;
  final Ref _ref;

  TransferQueueNotifier({
    required TransferManager manager,
    required Ref ref,
  })  : _manager = manager,
        _ref = ref,
        super([]) {
    _manager.tasksStream.listen((tasks) {
      state = tasks;
    });
  }

  Future<FileNode?> pickAndUploadFile({String? parentId}) async {
    final authState = _ref.read(authNotifierProvider);
    if (authState.masterKey == null) {
      throw Exception('Vault is locked. Unlock vault before uploading.');
    }

    return _manager.pickAndUploadFile(
      masterKey: authState.masterKey!,
      parentId: parentId,
    );
  }

  Future<void> shareDecryptedCopy(FileNode node) async {
    final authState = _ref.read(authNotifierProvider);
    if (authState.masterKey == null) {
      throw Exception('Vault is locked. Unlock vault to decrypt and share.');
    }

    return _manager.shareDecryptedCopy(node, authState.masterKey!);
  }
}

final transferQueueProvider =
    StateNotifierProvider<TransferQueueNotifier, List<TransferTask>>((ref) {
  final manager = ref.watch(transferManagerProvider);
  return TransferQueueNotifier(manager: manager, ref: ref);
});
