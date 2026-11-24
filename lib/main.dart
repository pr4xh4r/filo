import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'core/config/app_config.dart';
import 'core/database/filo_database.dart';
import 'core/theme/filo_colors.dart';
import 'core/theme/filo_theme.dart';
import 'features/auth/presentation/screens/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Multi-tier sqlite3 dynamic library initialization
  ensureSqliteInitialized();
  try {
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
  } catch (_) {
    // Non-fatal if platform channel is unavailable during startup
  }

  // Edge-to-edge transparent system navigation
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    const ProviderScope(
      child: FiloApp(),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App switcher privacy shield: hide contents when app is inactive or paused
    setState(() {
      _isBackgrounded = state == AppLifecycleState.inactive ||
          state == AppLifecycleState.paused;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Edge-to-edge system navigation & status bar (Ethereal Dawn Light)
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: FiloColors.lightBackground,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: FiloTheme.lightTheme,
      themeMode: ThemeMode.light,
      builder: (context, child) {
        // Obfuscate screen in OS task switcher for privacy
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
    );
  }
}
