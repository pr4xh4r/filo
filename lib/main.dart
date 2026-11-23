import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/config/app_config.dart';
import 'core/theme/filo_theme.dart';
import 'features/auth/presentation/screens/auth_gate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: FiloTheme.lightTheme,
      darkTheme: FiloTheme.darkTheme,
      themeMode: ThemeMode.system,
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
