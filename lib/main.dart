import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'core/config/app_config.dart';
import 'core/database/filo_database.dart';
import 'core/theme/filo_colors.dart';
import 'core/theme/filo_theme.dart';
import 'core/theme/theme_provider.dart';
import 'features/auth/domain/auth_state.dart';
import 'features/auth/presentation/providers/auth_provider.dart';
import 'features/auth/presentation/screens/auth_gate.dart';
import 'features/transfer/presentation/providers/transfer_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Multi-tier sqlite3 dynamic library initialization
  ensureSqliteInitialized();
  try {
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
  } catch (_) {
    // Non-fatal if platform channel is unavailable during startup
  }

  // BUG 2 FIX: Open a persistent file-backed SQLite DB instead of in-memory.
  // Data now survives app restarts.
  final appDir = await getApplicationDocumentsDirectory();
  final dbPath = p.join(appDir.path, 'filo_index.db');
  final database = await FiloDatabase.openFile(dbPath);

  // BUG 29 FIX: Removed the duplicate SystemUI call that was here before.
  // The build() method handles it reactively per theme — no need to set it twice.

  runApp(
    ProviderScope(
      overrides: [
        // BUG 2 FIX: Inject the file-backed DB into the provider tree
        databaseProvider.overrideWithValue(database),
      ],
      child: const FiloApp(),
    ),
  );
}

class FiloApp extends ConsumerStatefulWidget {
  const FiloApp({super.key});

  @override
  ConsumerState<FiloApp> createState() => _FiloAppState();
}

class _FiloAppState extends ConsumerState<FiloApp> with WidgetsBindingObserver {
  bool _isBackgrounded = false;

  // BUG 23 FIX: Track last user activity for auto-lock enforcement
  DateTime _lastActiveTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startAutoLockWatchdog();
  }

  /// Periodically checks whether the inactivity timeout has been exceeded.
  void _startAutoLockWatchdog() {
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(seconds: 30));
      if (!mounted) return false;
      _maybeAutoLock();
      return true;
    });
  }

  void _maybeAutoLock() {
    // Background transfer resilience: do not lock while files are actively transferring
    final activeTransfers = ref.read(activeTransfersProvider);
    if (activeTransfers.isNotEmpty) return;

    final authState = ref.read(authNotifierProvider);
    // Don't lock if already locked, or if timeout is 0 (background-only mode)
    if (authState.lockStatus == AppLockStatus.locked) return;
    if (authState.autoLockTimeoutMinutes == 0) return;

    final elapsed = DateTime.now().difference(_lastActiveTime);
    if (elapsed >= Duration(minutes: authState.autoLockTimeoutMinutes)) {
      ref.read(authNotifierProvider.notifier).lockVault();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _isBackgrounded = state == AppLifecycleState.inactive ||
          state == AppLifecycleState.paused;
    });

    // Lock on background when timeout == 0 (immediate lock),
    // but keep session active if files are actively uploading/downloading in background
    if (state == AppLifecycleState.paused) {
      final activeTransfers = ref.read(activeTransfersProvider);
      final hasActiveTransfers = activeTransfers.isNotEmpty;

      final authState = ref.read(authNotifierProvider);
      if (authState.autoLockTimeoutMinutes == 0 &&
          authState.lockStatus == AppLockStatus.unlocked &&
          !hasActiveTransfers) {
        ref.read(authNotifierProvider.notifier).lockVault();
      }
    }

    // Reset activity timer on resume so we don't lock instantly after foregrounding
    if (state == AppLifecycleState.resumed) {
      _lastActiveTime = DateTime.now();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    // BUG 29 FIX: Single SystemUI call, reactive to theme — not duplicated in main()
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor:
            isDark ? FiloColors.darkBackground : FiloColors.lightBackground,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return Listener(
      // BUG 23 FIX: Every touch resets the inactivity timer
      onPointerDown: (_) => _lastActiveTime = DateTime.now(),
      child: MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: FiloTheme.lightTheme,
        darkTheme: FiloTheme.darkTheme,
        themeMode: themeMode,
        builder: (context, child) {
          if (_isBackgrounded) {
            return const Material(
              color: Colors.black,
              child: Center(
                child: Icon(
                  Icons.lock_rounded,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            );
          }
          return child!;
        },
        home: const AuthGate(),
      ),
    );
  }
}
