import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:filo/core/database/filo_database.dart';
import 'package:filo/core/theme/filo_theme.dart';
import 'package:filo/features/auth/domain/auth_state.dart';
import 'package:filo/features/auth/presentation/providers/auth_provider.dart';
import 'package:filo/features/settings/presentation/screens/settings_screen.dart';
import 'package:filo/features/storage/data/fake_storage_backend.dart';

// Valid 1x1 transparent PNG bytes
final Uint8List _transparentPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  late FiloDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = FiloDatabase.openInMemory();
    tempDir = await Directory.systemTemp.createTemp('filo_profile_test_');
  });

  tearDown(() async {
    db.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('SettingsScreen displays Telegram profile with username, display name, and monogram fallback', (tester) async {
    final fakeStorage = FakeStorageBackend();
    fakeStorage.displayName = 'Prakhar Sharma';
    fakeStorage.testUsername = 'pr4xh4r';

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          storageBackendProvider.overrideWithValue(fakeStorage),
          authNotifierProvider.overrideWith((ref) => _CustomAuthNotifier(
                FiloAuthState(
                  isTelegramAuthenticated: true,
                  telegramUserId: '987654321',
                  telegramUserName: 'pr4xh4r',
                  telegramDisplayName: 'Prakhar Sharma',
                  lockStatus: AppLockStatus.unlocked,
                  vaultStatus: VaultSetupStatus.ready,
                ),
              )),
        ],
        child: MaterialApp(
          theme: FiloTheme.lightTheme,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Prakhar Sharma'), findsOneWidget);
    expect(find.text('@pr4xh4r'), findsOneWidget);
    expect(find.text('Telegram ID: 987654321'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('P'), findsOneWidget);
    expect(find.byKey(const ValueKey('telegram_avatar_fallback')), findsOneWidget);
  });

  testWidgets('SettingsScreen displays avatar container when photo file exists', (tester) async {
    final fakeStorage = FakeStorageBackend();
    final testAvatarFile = File('${tempDir.path}/test_avatar.png');
    testAvatarFile.writeAsBytesSync(_transparentPng);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          storageBackendProvider.overrideWithValue(fakeStorage),
          authNotifierProvider.overrideWith((ref) => _CustomAuthNotifier(
                FiloAuthState(
                  isTelegramAuthenticated: true,
                  telegramUserId: '123456789',
                  telegramUserName: 'johndoe',
                  telegramDisplayName: 'John Doe',
                  telegramProfilePhotoPath: testAvatarFile.path,
                  lockStatus: AppLockStatus.unlocked,
                  vaultStatus: VaultSetupStatus.ready,
                ),
              )),
        ],
        child: MaterialApp(
          theme: FiloTheme.lightTheme,
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('John Doe'), findsOneWidget);
    expect(find.text('@johndoe'), findsOneWidget);
    expect(find.text('Telegram ID: 123456789'), findsOneWidget);
    expect(find.byKey(const ValueKey('telegram_avatar_image')), findsOneWidget);
  });
}

class _CustomAuthNotifier extends StateNotifier<FiloAuthState> implements AuthNotifier {
  _CustomAuthNotifier(super.state);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
