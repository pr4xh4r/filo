import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_button.dart';
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

class _AppLockScreenState extends ConsumerState<AppLockScreen>
    with SingleTickerProviderStateMixin {
  final _passphraseController = TextEditingController();
  bool _obscurePassphrase = true;
  bool _isLoading = false;
  String? _errorMessage;
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -10.0), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10.0, end: 10.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10.0, end: -6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6.0, end: 6.0), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6.0, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeInOut));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptBiometricUnlock(userInitiated: false);
    });
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _passphraseController.dispose();
    super.dispose();
  }

  Future<void> _attemptBiometricUnlock({bool userInitiated = false}) async {
    final success =
        await ref.read(authNotifierProvider.notifier).unlockWithBiometrics();
    if (success && mounted) {
      HapticFeedback.mediumImpact();
      FiloToast.show(context, message: 'Space Unlocked', type: FiloToastType.success);
    } else if (!success && userInitiated && mounted) {
      HapticFeedback.heavyImpact();
      final err = ref.read(authNotifierProvider).errorMessage;
      if (err != null) {
        FiloToast.show(context, message: err, type: FiloToastType.error);
      }
    }
  }

  Future<void> _handleUnlockWithPassphrase() async {
    final pwd = _passphraseController.text.trim();
    if (pwd.isEmpty) {
      HapticFeedback.selectionClick();
      setState(() => _errorMessage = 'Please enter your passphrase');
      _shakeController.forward(from: 0.0);
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authNotifierProvider.notifier).unlockWithPassphrase(pwd);
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        setState(() {
          _isLoading = false;
          _errorMessage = 'Incorrect passphrase. Please try again.';
        });
        _shakeController.forward(from: 0.0);
        _passphraseController.clear();
      }
    }
  }

  void _showRecoveryKeyDialog() {
    final controller = TextEditingController();
    final newPassphraseController = TextEditingController();
    bool obscureNewPassphrase = true;

    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              elevation: 0,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      gradient: isDark
                          ? const LinearGradient(
                              colors: [Color(0xFF1E1E2C), Color(0xFF26263A)],
                            )
                          : const LinearGradient(
                              colors: [Color(0xFFFFF9F7), Color(0xFFFBF4FF)],
                            ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.85),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 500,
                        maxHeight: MediaQuery.of(ctx).size.height * 0.88,
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: FiloColors.accentCoral.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.vpn_key_outlined,
                                    color: FiloColors.accentCoral,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Emergency Recovery',
                                    style: FiloTypography.title3.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontFamily: FiloTypography.fontFamily,
                                      color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Enter the 64-character recovery key generated when your space was created.',
                              style: FiloTypography.caption.copyWith(
                                fontFamily: FiloTypography.fontFamily,
                                color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.white.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.12)
                                      : Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              child: TextField(
                                controller: controller,
                                autofocus: true,
                                style: TextStyle(
                                  fontFamily: 'JetBrainsMono',
                                  fontSize: 12.5,
                                  color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Recovery Key (A1B2-C3D4-...)',
                                  hintStyle: TextStyle(
                                    fontFamily: FiloTypography.fontFamily,
                                    color: isDark ? Colors.white38 : FiloColors.lightTextTertiary,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'New Passphrase (optional):',
                              style: TextStyle(
                                fontFamily: FiloTypography.fontFamily,
                                color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.white.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.12)
                                      : Colors.black.withValues(alpha: 0.08),
                                ),
                              ),
                              child: TextField(
                                controller: newPassphraseController,
                                obscureText: obscureNewPassphrase,
                                textAlignVertical: TextAlignVertical.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Set fresh passphrase (min 8 chars)',
                                  hintStyle: TextStyle(
                                    fontFamily: FiloTypography.fontFamily,
                                    color: isDark ? Colors.white38 : FiloColors.lightTextTertiary,
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      obscureNewPassphrase
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 19,
                                      color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                                    ),
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      setDialogState(() => obscureNewPassphrase = !obscureNewPassphrase);
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: Text(
                                    'Cancel',
                                    style: TextStyle(
                                      fontFamily: FiloTypography.fontFamily,
                                      color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FiloButton(
                                  label: 'Recover',
                                  size: FiloButtonSize.small,
                                  onPressed: () async {
                                    final key = controller.text.trim();
                                    if (key.isEmpty) return;
                                    final newPwd = newPassphraseController.text.trim();
                                    Navigator.of(ctx).pop();
                                    setState(() => _isLoading = true);
                                    try {
                                      if (newPwd.isNotEmpty) {
                                        if (newPwd.length < 8) {
                                          throw Exception('New passphrase must be at least 8 characters');
                                        }
                                        await ref.read(authNotifierProvider.notifier).resetPassphraseWithRecoveryKey(
                                              recoveryKey: key,
                                              newPassphrase: newPwd,
                                            );
                                      } else {
                                        await ref.read(authNotifierProvider.notifier).unlockWithRecoveryKey(key);
                                      }
                                      if (mounted) {
                                        FiloToast.show(context, message: 'Filo unlocked successfully', type: FiloToastType.success);
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
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final authState = ref.watch(authNotifierProvider);

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: FiloAmbientBackground(
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.symmetric(
                    horizontal: FiloSpacing.xl,
                    vertical: isLandscape ? FiloSpacing.sm : FiloSpacing.md,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: isLandscape ? 12 : 36),

                      // Flagship Logo Badge with ambient glow
                      Center(
                        child: FiloLogoBadge(
                          size: isLandscape ? 48 : 72,
                          showGlow: true,
                        ),
                      ),
                      SizedBox(height: isLandscape ? 12 : FiloSpacing.xl),

                      // Editorial Title
                      Text(
                        'Filo Locked',
                        textAlign: TextAlign.center,
                        style: FiloTypography.editorial(
                          fontSize: isLandscape ? 28 : 38,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1.2,
                          color: isDark
                              ? FiloColors.darkTextPrimary
                              : FiloColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Enter your passphrase to view your files',
                        textAlign: TextAlign.center,
                        style: FiloTypography.body.copyWith(
                          fontSize: isLandscape ? 13 : 15,
                          color: isDark
                              ? FiloColors.darkTextSecondary
                              : FiloColors.lightTextSecondary,
                        ),
                      ),

                      SizedBox(height: isLandscape ? 14 : 28),

                // Key Input Field with Shake Animation & Error Border
                AnimatedBuilder(
                  animation: _shakeAnimation,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(_shakeAnimation.value, 0),
                      child: child,
                    );
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: FiloRadius.roundedXl,
                      border: Border.all(
                        color: _errorMessage != null
                            ? FiloColors.destructive
                            : (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08)),
                        width: _errorMessage != null ? 1.6 : 1.0,
                      ),
                      boxShadow: _errorMessage != null
                          ? [
                              BoxShadow(
                                color: FiloColors.destructive.withValues(alpha: 0.25),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: FiloGlass(
                      borderRadius: FiloRadius.roundedXl,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                      child: TextField(
                        controller: _passphraseController,
                        obscureText: _obscurePassphrase,
                        autofocus: false,
                        textAlignVertical: TextAlignVertical.center,
                        style: FiloTypography.title3.copyWith(
                          color: isDark
                              ? FiloColors.darkTextPrimary
                              : FiloColors.lightTextPrimary,
                        ),
                        decoration: InputDecoration(
                          filled: false,
                          fillColor: Colors.transparent,
                          hintText: 'Enter your passphrase',
                          hintStyle: FiloTypography.body.copyWith(
                            color: isDark
                                ? FiloColors.darkTextTertiary
                                : FiloColors.lightTextTertiary,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassphrase
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                              color: isDark
                                  ? FiloColors.darkTextTertiary
                                  : FiloColors.lightTextTertiary,
                            ),
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              setState(() => _obscurePassphrase = !_obscurePassphrase);
                            },
                          ),
                        ),
                        onChanged: (_) {
                          if (_errorMessage != null) {
                            setState(() => _errorMessage = null);
                          }
                        },
                        onSubmitted: (_) => _handleUnlockWithPassphrase(),
                      ),
                    ),
                  ),
                ),

                // Prominent Inline Error Feedback
                if (_errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: FiloColors.destructive.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: FiloColors.destructive.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 16, color: FiloColors.destructive),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: FiloColors.destructive,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

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
                              'Unlock',
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
                              'Use Biometrics',
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

                      SizedBox(height: isLandscape ? 8 : FiloSpacing.md),
                      Center(
                        child: TextButton(
                          onPressed: _showRecoveryKeyDialog,
                          child: Text(
                            'Forgot key? Use Recovery Key',
                            style: FiloTypography.caption.copyWith(
                              color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                            ),
                          ),
                        ),
                      ),

                      SizedBox(height: isLandscape ? 12 : 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
