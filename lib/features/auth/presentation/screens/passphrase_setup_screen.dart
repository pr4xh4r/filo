import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../core/theme/persona_provider.dart';
import '../../../../shared/components/filo_glass.dart';
import '../../../../shared/components/filo_toast.dart';
import '../providers/auth_provider.dart';

/// Passphrase setup screen with human, jargon-free copywriting and CRED/iOS 18 liquid glass aesthetics.
class PassphraseSetupScreen extends ConsumerStatefulWidget {
  const PassphraseSetupScreen({super.key});

  @override
  ConsumerState<PassphraseSetupScreen> createState() =>
      _PassphraseSetupScreenState();
}

class _PassphraseSetupScreenState extends ConsumerState<PassphraseSetupScreen> {
  final _passphraseController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassphrase = true;
  bool _confirmedLossRisk = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _passphraseController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  int _calculateStrength(String text) {
    if (text.isEmpty) return 0;
    int score = 0;
    if (text.length >= 8) score++;
    if (text.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(text) && RegExp(r'[a-z]').hasMatch(text)) score++;
    if (RegExp(r'[0-9]').hasMatch(text)) score++;
    if (RegExp(r'[!@#\$&*~-]').hasMatch(text)) score++;
    return score.clamp(1, 4);
  }

  Color _getStrengthColor(int score) {
    switch (score) {
      case 1:
        return FiloColors.destructive;
      case 2:
        return FiloColors.warning;
      case 3:
        return FiloColors.info;
      case 4:
        return FiloColors.success;
      default:
        return Colors.transparent;
    }
  }

  String _getStrengthLabel(int score) {
    switch (score) {
      case 1:
        return 'weak';
      case 2:
        return 'okay';
      case 3:
        return 'strong';
      case 4:
        return 'bulletproof';
      default:
        return '';
    }
  }

  Future<void> _handleSetupVault() async {
    final pwd = _passphraseController.text;
    final confirm = _confirmController.text;

    if (pwd.length < 8) {
      FiloToast.show(context, message: 'Your key must be at least 8 characters long', type: FiloToastType.error);
      return;
    }

    if (pwd != confirm) {
      FiloToast.show(context, message: 'Keys do not match', type: FiloToastType.error);
      return;
    }

    if (!_confirmedLossRisk) {
      FiloToast.show(context, message: 'Please confirm you saved your key', type: FiloToastType.warning);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final recoveryKey = await ref.read(authNotifierProvider.notifier).setupNewVault(pwd);
      setState(() => _isLoading = false);
      if (mounted) {
        _showRecoveryKeySheet(recoveryKey);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      FiloToast.show(context, message: e.toString(), type: FiloToastType.error);
    }
  }

  void _showRecoveryKeySheet(String recoveryKey) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return FiloGlass(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Container(
                  height: 150,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Image.asset(
                    FiloIllustrations.recovery,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'emergency recovery key',
                style: FiloTypography.editorial(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.8,
                  color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'save this in a secure place. if you ever forget your vault key, this is the only way to recover your files.',
                style: FiloTypography.body.copyWith(
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? FiloColors.darkSurfaceSecondary : FiloColors.lightSurfaceSecondary,
                  borderRadius: FiloRadius.roundedLg,
                  border: Border.all(
                    color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
                    width: 0.8,
                  ),
                ),
                child: SelectableText(
                  recoveryKey,
                  style: FiloTypography.monospace.copyWith(
                    color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: FiloRadius.roundedLg,
                        ),
                        side: BorderSide(
                          color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.2),
                        ),
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: recoveryKey));
                        HapticFeedback.lightImpact();
                        FiloToast.show(context, message: 'Recovery key copied', type: FiloToastType.success);
                      },
                      child: Text(
                        'copy key',
                        style: FiloTypography.callout.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: FiloColors.brandGradient,
                          ),
                          borderRadius: FiloRadius.roundedLg,
                        ),
                        child: Center(
                          child: Text(
                            'done',
                            style: FiloTypography.callout.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pwd = _passphraseController.text;
    final strength = _calculateStrength(pwd);

    return Scaffold(
      body: FiloAmbientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: FiloSpacing.xl,
              vertical: FiloSpacing.lg,
            ),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: FiloSpacing.sm),

                Text(
                  'create vault key',
                  style: FiloTypography.editorial(
                    fontSize: 36,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -1.2,
                    color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'choose a secret key only you know. it protects every file on your phone.',
                  style: FiloTypography.body.copyWith(
                    color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: FiloSpacing.xl),

                // Vault Key Input Field (Liquid Glass)
                FiloGlass(
                  borderRadius: FiloRadius.roundedXl,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _passphraseController,
                    obscureText: _obscurePassphrase,
                    onChanged: (_) => setState(() {}),
                    style: FiloTypography.title3.copyWith(
                      color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                    ),
                    decoration: InputDecoration(
                      filled: false,
                      fillColor: Colors.transparent,
                      hintText: 'choose your key (min 8 chars)',
                      hintStyle: FiloTypography.body.copyWith(
                        color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassphrase ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                        ),
                        onPressed: () => setState(() => _obscurePassphrase = !_obscurePassphrase),
                      ),
                    ),
                  ),
                ),

                if (pwd.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: strength / 4,
                            backgroundColor: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
                            valueColor: AlwaysStoppedAnimation<Color>(_getStrengthColor(strength)),
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _getStrengthLabel(strength),
                        style: FiloTypography.caption.copyWith(
                          color: _getStrengthColor(strength),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: FiloSpacing.md),

                // Confirm Key Input Field (Liquid Glass)
                FiloGlass(
                  borderRadius: FiloRadius.roundedXl,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: TextField(
                    controller: _confirmController,
                    obscureText: _obscurePassphrase,
                    style: FiloTypography.title3.copyWith(
                      color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                    ),
                    decoration: InputDecoration(
                      filled: false,
                      fillColor: Colors.transparent,
                      hintText: 'confirm your key',
                      hintStyle: FiloTypography.body.copyWith(
                        color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),

                const SizedBox(height: FiloSpacing.xl),

                // Confirmation Switch
                FiloGlass(
                  borderRadius: FiloRadius.roundedLg,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Switch.adaptive(
                        value: _confirmedLossRisk,
                        activeColor: FiloColors.primary,
                        onChanged: (val) {
                          HapticFeedback.selectionClick();
                          setState(() => _confirmedLossRisk = val);
                        },
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'i understand nobody can recover my files if i lose this key.',
                          style: FiloTypography.caption.copyWith(
                            color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: FiloSpacing.xxl),

                // CTA Button
                GestureDetector(
                  onTapDown: (_) => HapticFeedback.lightImpact(),
                  onTap: _isLoading ? null : _handleSetupVault,
                  child: Container(
                    height: 60,
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
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'create vault',
                                  style: FiloTypography.title3.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ],
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: FiloSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
