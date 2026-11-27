import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filo/core/database/filo_database.dart';
import 'package:filo/core/theme/filo_theme.dart';
import 'package:filo/features/auth/domain/auth_state.dart';
import 'package:filo/features/auth/presentation/providers/auth_provider.dart';
import 'package:filo/features/files/data/file_repository.dart';
import 'package:filo/features/settings/presentation/screens/settings_screen.dart';
import 'package:filo/features/settings/presentation/widgets/export_everything_sheet.dart';
import 'package:filo/features/storage/data/fake_storage_backend.dart';
import 'package:filo/features/transfer/data/transfer_manager.dart';
import 'package:filo/features/transfer/domain/vault_export_service.dart';
import 'package:filo/features/transfer/presentation/providers/export_provider.dart';

class _WidgetTestExportBridge extends ExportPlatformBridge {
  final Directory workDir;
  _WidgetTestExportBridge(this.workDir);

  @override
  Future<Directory> getExportWorkingDirectory() async => workDir;

  @override
  Future<int?> getAvailableStorageBytes(String path) async =>
      20 * 1024 * 1024 * 1024;
}

class _UnlockedAuthNotifier extends AuthNotifier {
  final Uint8List _initialKey;

  _UnlockedAuthNotifier({
    required super.repository,
    required super.database,
    required Uint8List masterKey,
  })  : _initialKey = masterKey,
        super(useNativeAndroidBiometricsOverride: false) {
    state = FiloAuthState(
      isTelegramAuthenticated: true,
      vaultStatus: VaultSetupStatus.ready,
      lockStatus: AppLockStatus.unlocked,
      masterKey: _initialKey,
      isLoading: false,
    );
  }

  @override
  Future<void> initialize() async {}
}

void main() {
  late FiloDatabase db;
  late FakeStorageBackend storage;

  setUp(() async {
    db = FiloDatabase.openInMemory();
    storage = FakeStorageBackend();
    await storage.initialize();
    storage.setAuthenticated();
  });

  tearDown(() {
    db.close();
  });

  testWidgets('SettingsScreen opens ExportEverythingSheet with vault summary',
      (tester) async {
    final repo = FileRepository(database: db);
    await repo.createFileNode(
      name: 'backup_item.bin',
      sizeBytes: 2048,
    );

    final masterKey = Uint8List.fromList(List<int>.filled(32, 7));
    final transferManager = TransferManager(
      storageBackend: storage,
      fileRepository: repo,
    );
    addTearDown(transferManager.dispose);

    final tempDir = Directory.systemTemp.createTempSync('filo_sheet_test_');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          storageBackendProvider.overrideWithValue(storage),
          authNotifierProvider.overrideWith((ref) {
            return _UnlockedAuthNotifier(
              repository: ref.read(authRepositoryProvider),
              database: db,
              masterKey: masterKey,
            );
          }),
          vaultExportServiceProvider.overrideWithValue(
            VaultExportService(
              fileRepository: repo,
              storageBackend: storage,
              transferManager: transferManager,
              platformBridge: _WidgetTestExportBridge(tempDir),
            ),
          ),
        ],
        child: MaterialApp(
          theme: FiloTheme.lightTheme,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Export Everything'), 200);
    await tester.ensureVisible(find.text('Export Everything'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export Everything'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(find.byType(ExportEverythingSheet), findsOneWidget);
    expect(find.textContaining('1 files • 2.0 KB'), findsOneWidget);
    expect(find.text('Start Full Export'), findsOneWidget);
  });
}
