import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:filo/core/theme/filo_colors.dart';
import 'package:filo/features/auth/domain/auth_state.dart';
import 'package:filo/features/auth/presentation/providers/auth_provider.dart';
import 'package:filo/features/files/presentation/screens/file_browser_screen.dart';
import 'app_lock_screen.dart';
import 'passphrase_setup_screen.dart';
import 'welcome_screen.dart';

/// Central authentication gate routing between onboarding, login, unlock, and the main app.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authNotifierProvider);

    if (authState.isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(FiloColors.primary),
          ),
        ),
      );
    }

    // 1. User needs to connect Telegram
    if (!authState.isTelegramAuthenticated) {
      return const WelcomeScreen();
    }

    // 2. Telegram connected, but zero-knowledge vault not yet set up
    if (authState.vaultStatus == VaultSetupStatus.unconfigured) {
      return const PassphraseSetupScreen();
    }

    // 3. Vault configured, but app is locked
    if (authState.lockStatus == AppLockStatus.locked ||
        authState.vaultStatus == VaultSetupStatus.passphraseNeeded) {
      return const AppLockScreen();
    }

    // 4. Authenticated, configured, and unlocked -> Main File Browser
    return const FileBrowserScreen();
  }
}
