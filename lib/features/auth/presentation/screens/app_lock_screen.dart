import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../../shared/components/filo_logo_badge.dart';
import '../../../../shared/components/filo_toast.dart';
import '../providers/auth_provider.dart';

/// App lock screen presented when the application is locked by timeout or on app open.
class AppLockScreen extends ConsumerStatefulWidget {
  const AppLockScreen({super.key});

  @override
  ConsumerState<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends ConsumerState<AppLockScreen> {
  final _passphraseController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Auto-prompt biometrics if enabled
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptBiometricUnlock(userInitiated: false);
    });
  }

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _attemptBiometricUnlock({bool userInitiated = false}) async {
    final success = await ref.read(authNotifierProvider.notifier).unlockWithBiometrics();
    if (success && mounted) {
      HapticFeedback.mediumImpact();
      FiloToast.show(context, message: 'Vault Unlocked', type: FiloToastType.success);
    } else if (!success && userInitiated && mounted) {
      HapticFeedback.heavyImpact();
      final err = ref.read(authNotifierProvider).errorMessage;
      if (err != null) {
        FiloToast.show(context, message: err, type: FiloToastType.error);
      }
    }
  }

  Future<void> _handleUnlockWithPassphrase() async {
    final pwd = _passphraseController.text;
    if (pwd.isEmpty) {
      HapticFeedback.selectionClick();
      FiloToast.show(context, message: 'Please enter your passphrase', type: FiloToastType.error);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).unlockWithPassphrase(pwd);
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        setState(() => _isLoading = false);
        FiloToast.show(context, message: 'Incorrect passphrase', type: FiloToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: FiloSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 1),

              // Flagship Logo Badge with ambient glow
              const Center(
                child: FiloLogoBadge(
                  size: 80,
                  showGlow: true,
                ),
              ),
              const SizedBox(height: FiloSpacing.xl),

              Text(
                '${AppConfig.appName} is Locked',
                textAlign: TextAlign.center,
                style: FiloTypography.title1.copyWith(
                  color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                  letterSpacing: -0.6,
                ),
              ),
              const SizedBox(height: FiloSpacing.xs),
              Text(
                'Enter your master passphrase to decrypt your local index.',
                textAlign: TextAlign.center,
                style: FiloTypography.body.copyWith(
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: FiloSpacing.xxl),

              // Passphrase input
              TextField(
                controller: _passphraseController,
                obscureText: true,
                autofocus: !authState.isBiometricEnabled,
                onSubmitted: (_) => _handleUnlockWithPassphrase(),
                decoration: InputDecoration(
                  labelText: 'Master Passphrase',
                  filled: true,
                  fillColor: isDark ? FiloColors.darkSurfaceSecondary : FiloColors.lightSurfaceSecondary,
                  border: OutlineInputBorder(
                    borderRadius: FiloRadius.roundedMd,
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: FiloSpacing.lg),

              // Unlock Button
              FiloButton(
                label: 'Unlock Vault',
                isLoading: _isLoading,
                onPressed: _handleUnlockWithPassphrase,
                size: FiloButtonSize.large,
                isFullWidth: true,
              ),

              // Biometric Unlock if enabled
              if (authState.isBiometricEnabled) ...[
                const SizedBox(height: FiloSpacing.md),
                FiloButton(
                  label: 'Unlock with Biometrics',
                  variant: FiloButtonVariant.secondary,
                  icon: const Icon(Icons.fingerprint_rounded, size: 22),
                  onPressed: () => _attemptBiometricUnlock(userInitiated: true),
                  size: FiloButtonSize.large,
                  isFullWidth: true,
                ),
              ],

              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
