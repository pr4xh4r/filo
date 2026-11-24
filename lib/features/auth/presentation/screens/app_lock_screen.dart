import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_glass.dart';
import '../../../../shared/components/filo_logo_badge.dart';
import '../../../../shared/components/filo_toast.dart';
import '../providers/auth_provider.dart';

/// App lock screen presented when the application is locked.
///
/// Features:
/// - CRED obsidian aesthetic with soft liquid glass materials
/// - Human, confident copywriting
/// - Auto-prompt and one-tap biometric unlock (Face ID / Fingerprint)
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
    final success =
        await ref.read(authNotifierProvider.notifier).unlockWithBiometrics();
    if (success && mounted) {
      HapticFeedback.mediumImpact();
      FiloToast.show(context, message: 'vault unlocked', type: FiloToastType.success);
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
      FiloToast.show(context, message: 'enter your vault key', type: FiloToastType.error);
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
        FiloToast.show(context, message: 'incorrect key', type: FiloToastType.error);
      }
    }
  }

  void _showRecoveryKeyDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? FiloColors.darkSurface : Colors.white,
          title: Text(
            'Emergency Recovery',
            style: TextStyle(
              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter the 64-character recovery key generated when your vault was created.',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 12,
                  color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. A1B2-C3D4-...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final key = controller.text.trim();
                if (key.isEmpty) return;
                Navigator.of(ctx).pop();
                setState(() => _isLoading = true);
                try {
                  await ref.read(authNotifierProvider.notifier).unlockWithRecoveryKey(key);
                  if (mounted) {
                    FiloToast.show(context, message: 'Vault recovered successfully', type: FiloToastType.success);
                  }
                } catch (e) {
                  if (mounted) {
                    FiloToast.show(context, message: 'Recovery failed: $e', type: FiloToastType.error);
                  }
                } finally {
                  if (mounted) {
                    setState(() => _isLoading = false);
                  }
                }
              },
              child: const Text('Recover'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      body: FiloAmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: FiloSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 2),

                // Flagship Logo Badge with ambient glow
                const Center(
                  child: FiloLogoBadge(
                    size: 72,
                    showGlow: true,
                  ),
                ),
                const SizedBox(height: FiloSpacing.xl),

                // Editorial Title
                Text(
                  'vault locked',
                  textAlign: TextAlign.center,
                  style: FiloTypography.editorial(
                    fontSize: 38,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.2,
                    color: isDark
                        ? FiloColors.darkTextPrimary
                        : FiloColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'enter your key to view your files',
                  textAlign: TextAlign.center,
                  style: FiloTypography.body.copyWith(
                    color: isDark
                        ? FiloColors.darkTextSecondary
                        : FiloColors.lightTextSecondary,
                  ),
                ),

                const Spacer(flex: 1),

                // Vault Key Input Field (Liquid Glass)
                FiloGlass(
                  borderRadius: FiloRadius.roundedXl,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                  child: TextField(
                    controller: _passphraseController,
                    obscureText: true,
                    autofocus: false,
                    style: FiloTypography.title3.copyWith(
                      color: isDark
                          ? FiloColors.darkTextPrimary
                          : FiloColors.lightTextPrimary,
                    ),
                    decoration: InputDecoration(
                      filled: false,
                      fillColor: Colors.transparent,
                      hintText: 'enter your key',
                      hintStyle: FiloTypography.body.copyWith(
                        color: isDark
                            ? FiloColors.darkTextTertiary
                            : FiloColors.lightTextTertiary,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onSubmitted: (_) => _handleUnlockWithPassphrase(),
                  ),
                ),

                const SizedBox(height: FiloSpacing.md),

                // Primary Unlock CTA
                GestureDetector(
                  onTapDown: (_) => HapticFeedback.lightImpact(),
                  onTap: _isLoading ? null : _handleUnlockWithPassphrase,
                  child: Container(
                    height: 58,
                    decoration: BoxDecoration(
                      color: FiloColors.primary,
                      borderRadius: FiloRadius.roundedXl,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFFD7CA).withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: FiloColors.primary.withValues(alpha: 0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              'unlock',
                              style: FiloTypography.title3.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.3,
                              ),
                            ),
                    ),
                  ),
                ),

                // One-tap Biometrics Button
                if (authState.isBiometricEnabled) ...[
                  const SizedBox(height: FiloSpacing.lg),
                  Center(
                    child: GestureDetector(
                      onTap: () =>
                          _attemptBiometricUnlock(userInitiated: true),
                      child: FiloGlass(
                        borderRadius: BorderRadius.circular(100),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.fingerprint_rounded,
                              size: 22,
                              color: isDark
                                  ? FiloColors.accentOrchid
                                  : FiloColors.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'use biometrics',
                              style: FiloTypography.callout.copyWith(
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? FiloColors.darkTextPrimary
                                    : FiloColors.lightTextPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: FiloSpacing.md),
                Center(
                  child: TextButton(
                    onPressed: _showRecoveryKeyDialog,
                    child: Text(
                      'forgot key? use recovery key',
                      style: FiloTypography.caption.copyWith(
                        color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
