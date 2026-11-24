import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:filo/core/config/app_config.dart';
import 'package:filo/core/crypto/crypto_engine.dart';
import 'package:filo/core/crypto/hash_utils.dart';
import 'package:filo/core/database/chunk_model.dart';
import 'package:filo/core/database/filo_database.dart';
import 'package:filo/features/auth/data/auth_repository.dart';
import 'package:filo/features/files/data/file_repository.dart';
import 'package:filo/features/files/domain/workspace.dart';
import 'package:filo/features/storage/data/fake_storage_backend.dart';
import 'package:filo/features/sync/domain/index_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Zero-Knowledge Cloud Snapshot & Reinstall Restore Suite', () {
    late FakeStorageBackend sharedTelegramCloud;

    setUp(() async {
      FlutterSecureStorage.setMockInitialValues({});
      sharedTelegramCloud = FakeStorageBackend();
      await sharedTelegramCloud.initialize();
      sharedTelegramCloud.setAuthenticated();
    });

    test('Full lifecycle: Device A setup -> Telegram backup -> Device B fresh restore', () async {
      // -------------------------------------------------------------
      // DEVICE A: Initial Setup & File Creation
      // -------------------------------------------------------------
      final dbA = FiloDatabase.openInMemory();
      final fileRepoA = FileRepository(database: dbA);
      final authRepoA = AuthRepository(storageBackend: sharedTelegramCloud);

      const passphrase = 'UltraSecureMasterPassphrase2026!';
      final recoveryKey = await authRepoA.setupNewVault(passphrase: passphrase);
      expect(recoveryKey.split('-').length, 8);

      final masterKeyA = await authRepoA.unlockWithPassphrase(passphrase);
      expect(masterKeyA.length, 32);

      // Create folder and file with chunk in Device A
      final folder = await fileRepoA.createFolder(name: 'Financial Records');
      final file = await fileRepoA.createFileNode(
        name: 'Tax_Return_2025.pdf',
        sizeBytes: 1024 * 750,
        parentId: folder.id,
        mimeType: 'application/pdf',
        contentHash: 'sha256_dummy_tax_hash',
      );

      final chunk = FileChunk(
        id: 'chunk_tax_1',
        nodeId: file.id,
        chunkIndex: 0,
        remoteMessageId: 'msg_tg_101',
        remoteFileId: 'file_tg_tax_101',
        sizeBytes: 1024 * 750,
        sha256Hash: 'chunk_sha256_tax',
        ivHex: '11223344556677889900aabb',
      );
      await fileRepoA.saveFileChunks([chunk]);

      // Device A backs up index to channel 'filo'
      final syncServiceA = IndexSyncService(
        database: dbA,
        storageBackend: sharedTelegramCloud,
        authRepository: authRepoA,
      );

      final messageId = await syncServiceA.backupIndexToCloud(masterKey: masterKeyA);
      expect(messageId.isNotEmpty, true);

      // Verify channel 'filo' has pinned index.filo
      final channel = await sharedTelegramCloud.getOrCreateVaultChannel(AppConfig.vaultChannelTitle);
      final pinned = await sharedTelegramCloud.getPinnedMessage(channelId: channel.channelId);
      expect(pinned, isNotNull);
      expect(pinned?.caption, 'index.filo');

      // -------------------------------------------------------------
      // DEVICE B: Fresh App Installation / Cross-Device Reinstall
      // -------------------------------------------------------------
      FlutterSecureStorage.setMockInitialValues({});
      final dbB = FiloDatabase.openInMemory();
      final authRepoB = AuthRepository(storageBackend: sharedTelegramCloud);
      final syncServiceB = IndexSyncService(
        database: dbB,
        storageBackend: sharedTelegramCloud,
        authRepository: authRepoB,
      );

      // Device B starts with empty vault
      expect(await authRepoB.hasConfiguredVault(), false);
      expect(await dbB.getNodeCount(), 0);

      // Device B detects vault in channel 'filo' BEFORE entering master key
      final cloudBundle = await syncServiceB.fetchCloudVaultKeyBundle();
      expect(cloudBundle, isNotNull);
      expect(cloudBundle!['version'], 1);
      expect(cloudBundle['vaultBundle'], isNotNull);
      expect(cloudBundle['catalogCiphertextHex'], isNotNull);

      // Import bundle into Device B's keystore
      await authRepoB.importVaultKeyBundle(cloudBundle);
      expect(await authRepoB.hasConfiguredVault(), true);

      // Device B unlocks using passphrase
      final masterKeyB = await authRepoB.unlockWithPassphrase(passphrase);
      expect(HashUtils.constantTimeCompare(masterKeyA, masterKeyB), true);

      // Device B restores database from cloud
      final restored = await syncServiceB.restoreIndexFromCloud(masterKey: masterKeyB);
      expect(restored, true);

      // Verify reconstructed database on Device B
      final nodesB = await dbB.listNodes();
      expect(nodesB.length, 1);
      expect(nodesB.first.name, 'Financial Records');

      final filesB = await dbB.listNodes(parentId: folder.id);
      expect(filesB.length, 1);
      expect(filesB.first.name, 'Tax_Return_2025.pdf');

      final chunksB = await dbB.getChunksForNode(file.id);
      expect(chunksB.length, 1);
      expect(chunksB.first.remoteFileId, 'file_tg_tax_101');

      dbA.close();
      dbB.close();
    });

    test('Emergency Recovery: Restore vault using 24-word recovery key when passphrase is forgotten', () async {
      final dbA = FiloDatabase.openInMemory();
      final authRepoA = AuthRepository(storageBackend: sharedTelegramCloud);
      const passphrase = 'ForgottenPassphrase123!';

      final recoveryKey = await authRepoA.setupNewVault(passphrase: passphrase);
      final masterKeyA = await authRepoA.unlockWithPassphrase(passphrase);

      final syncServiceA = IndexSyncService(
        database: dbA,
        storageBackend: sharedTelegramCloud,
        authRepository: authRepoA,
      );
      await syncServiceA.backupIndexToCloud(masterKey: masterKeyA);

      // Device C: User forgot passphrase, unlocks with recoveryKey
      final dbC = FiloDatabase.openInMemory();
      final authRepoC = AuthRepository(storageBackend: sharedTelegramCloud);
      final syncServiceC = IndexSyncService(
        database: dbC,
        storageBackend: sharedTelegramCloud,
        authRepository: authRepoC,
      );

      final cloudBundle = await syncServiceC.fetchCloudVaultKeyBundle();
      expect(cloudBundle, isNotNull);
      await authRepoC.importVaultKeyBundle(cloudBundle!);

      // Unlock with recovery key
      final masterKeyC = await authRepoC.unlockWithRecoveryKey(recoveryKey);
      expect(HashUtils.constantTimeCompare(masterKeyA, masterKeyC), true);

      dbA.close();
      dbC.close();
    });

    test('Security: Incorrect passphrase fails to unwrap master key', () async {
      final authRepo = AuthRepository(storageBackend: sharedTelegramCloud);
      await authRepo.setupNewVault(passphrase: 'CorrectPassword123!');

      expect(
        () async => await authRepo.unlockWithPassphrase('WrongPassword999!'),
        throwsException,
      );
    });

    test('Sync: Automatic sync debounce delays backup to prevent Telegram flood-wait', () async {
      final db = FiloDatabase.openInMemory();
      final authRepo = AuthRepository(storageBackend: sharedTelegramCloud);
      final masterKey = CryptoEngine.generateMasterKey();

      final syncService = IndexSyncService(
        database: db,
        storageBackend: sharedTelegramCloud,
        authRepository: authRepo,
      );

      // Rapidly trigger 5 times
      for (int i = 0; i < 5; i++) {
        syncService.triggerAutoSync(
          masterKey: masterKey,
          delay: const Duration(milliseconds: 50),
        );
      }

      // Should not have uploaded immediately
      final channel = await sharedTelegramCloud.getOrCreateVaultChannel(AppConfig.vaultChannelTitle);
      var pinned = await sharedTelegramCloud.getPinnedMessage(channelId: channel.channelId);
      expect(pinned, isNull);

      // Wait for debounce duration and async backup execution
      await Future<void>.delayed(const Duration(milliseconds: 600));

      // Now it should be pinned
      pinned = await sharedTelegramCloud.getPinnedMessage(channelId: channel.channelId);
      expect(pinned, isNotNull);

      syncService.dispose();
      db.close();
    });

    test('Workspaces (Spaces) and tags survive backup and cross-device restore', () async {
      final dbA = FiloDatabase.openInMemory();
      final repoA = FileRepository(database: dbA);
      final masterKey = CryptoEngine.generateMasterKey();
      final syncServiceA = IndexSyncService(
        database: dbA,
        storageBackend: sharedTelegramCloud,
      );

      // Ensure default spaces exist and create a custom space + folder inside it
      await repoA.getWorkspaces();
      const customSpace = Workspace(
        id: 'travel_2026',
        name: 'Travel 2026',
        description: 'Tickets and visas',
        icon: Icons.folder_outlined,
      );
      await repoA.createWorkspace(customSpace);
      await repoA.createFolder(
        name: 'Boarding Passes',
        workspaceId: 'travel_2026',
        tags: const ['important', 'travel'],
      );

      await syncServiceA.backupIndexToCloud(masterKey: masterKey);

      // Restore on fresh Device B
      final dbB = FiloDatabase.openInMemory();
      final repoB = FileRepository(database: dbB);
      final syncServiceB = IndexSyncService(
        database: dbB,
        storageBackend: sharedTelegramCloud,
      );

      final restored = await syncServiceB.checkAndAutoRestore(masterKey: masterKey);
      expect(restored, isTrue);

      final workspacesB = await repoB.getWorkspaces();
      expect(workspacesB.any((w) => w.id == 'travel_2026' && w.name == 'Travel 2026'), isTrue);

      final foldersB = await repoB.getNodes(workspaceId: 'travel_2026');
      expect(foldersB.length, 1);
      expect(foldersB.first.name, 'Boarding Passes');
      expect(foldersB.first.tags, ['important', 'travel']);

      syncServiceA.dispose();
      syncServiceB.dispose();
      dbA.close();
      dbB.close();
    });

    test('flushPendingSync pushes changes immediately without waiting for debounce', () async {
      final db = FiloDatabase.openInMemory();
      final repo = FileRepository(database: db);
      final masterKey = CryptoEngine.generateMasterKey();
      final syncService = IndexSyncService(
        database: db,
        storageBackend: sharedTelegramCloud,
      );

      await repo.createFolder(name: 'Instant Flush');
      // Schedule with long 10-second debounce, then flush immediately
      syncService.triggerAutoSync(
        masterKey: masterKey,
        delay: const Duration(seconds: 10),
      );
      await syncService.flushPendingSync();

      final channel = await sharedTelegramCloud.getOrCreateVaultChannel(AppConfig.vaultChannelTitle);
      final pinned = await sharedTelegramCloud.getPinnedMessage(channelId: channel.channelId);
      expect(pinned, isNotNull);

      // Clean DB should pull that flushed folder
      final db2 = FiloDatabase.openInMemory();
      final syncService2 = IndexSyncService(
        database: db2,
        storageBackend: sharedTelegramCloud,
      );
      final restored = await syncService2.checkAndAutoRestore(masterKey: masterKey);
      expect(restored, isTrue);
      expect((await db2.listNodes()).first.name, 'Instant Flush');

      syncService.dispose();
      syncService2.dispose();
      db.close();
      db2.close();
    });

    test('Auto-sync pushes dirty local edits and second device automatically pulls newer snapshot', () async {
      final masterKey = CryptoEngine.generateMasterKey();

      // Device A creates initial state and backs up
      final dbA = FiloDatabase.openInMemory();
      final repoA = FileRepository(database: dbA);
      final syncA = IndexSyncService(database: dbA, storageBackend: sharedTelegramCloud);
      await repoA.createFolder(name: 'Initial Folder');
      await syncA.backupIndexToCloud(masterKey: masterKey);

      // Device B restores initial state
      final dbB = FiloDatabase.openInMemory();
      final syncB = IndexSyncService(database: dbB, storageBackend: sharedTelegramCloud);
      expect(await syncB.checkAndAutoRestore(masterKey: masterKey), isTrue);
      expect((await dbB.listNodes()).length, 1);

      // Device A adds a second folder and syncs
      await repoA.createFolder(name: 'From Device A');
      await syncA.backupIndexToCloud(masterKey: masterKey);

      // Device B runs checkAndAutoRestore with clean local state -> pulls Device A update
      expect(await syncB.checkAndAutoRestore(masterKey: masterKey), isTrue);
      final nodesB = await dbB.listNodes();
      expect(nodesB.map((n) => n.name), containsAll(['Initial Folder', 'From Device A']));

      // Now Device B makes an offline dirty edit -> checkAndAutoRestore pushes instead of overwriting
      await FileRepository(database: dbB).createFolder(name: 'Offline Local');
      syncB.triggerAutoSync(masterKey: masterKey, delay: const Duration(seconds: 30));
      expect(await syncB.checkAndAutoRestore(masterKey: masterKey), isFalse);
      await syncB.flushPendingSync();

      // Device A pulls Device B's pushed change
      expect(await syncA.checkAndAutoRestore(masterKey: masterKey), isTrue);
      expect((await dbA.listNodes()).map((n) => n.name), contains('Offline Local'));

      syncA.dispose();
      syncB.dispose();
      dbA.close();
      dbB.close();
    });
  });
}
