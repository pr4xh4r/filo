import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../../shared/components/filo_toast.dart';
import '../providers/auth_provider.dart';

/// Passphrase setup screen enforcing zero-knowledge confirmation and strength verification.
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
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Strong';
      default:
        return '';
    }
  }

  Future<void> _handleSetupVault() async {
    final pwd = _passphraseController.text;
    final confirm = _confirmController.text;

    if (pwd.length < 8) {
      FiloToast.show(context, message: 'Passphrase must be at least 8 characters long', type: FiloToastType.error);
      return;
    }

    if (pwd != confirm) {
      FiloToast.show(context, message: 'Passphrases do not match', type: FiloToastType.error);
      return;
    }

    if (!_confirmedLossRisk) {
      FiloToast.show(context, message: 'You must confirm that you understand the loss risk', type: FiloToastType.warning);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final recoveryKey = await ref.read(authNotifierProvider.notifier).setupNewVault(pwd);
      setState(() => _isLoading = false);

      if (mounted) {
        _showRecoveryKeyDialog(recoveryKey);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      FiloToast.show(context, message: e.toString(), type: FiloToastType.error);
    }
  }

  void _showRecoveryKeyDialog(String recoveryKey) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save Your Recovery Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'If you forget your passphrase, this 256-bit emergency recovery key is the ONLY way to access your files.',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: FiloSpacing.md),
              Container(
                padding: const EdgeInsets.all(FiloSpacing.md),
                decoration: BoxDecoration(
                  color: isDark ? FiloColors.darkSurfaceSecondary : FiloColors.lightSurfaceSecondary,
                  borderRadius: FiloRadius.roundedMd,
                  border: Border.all(color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder),
                ),
                child: SelectableText(
                  recoveryKey,
                  style: FiloTypography.monospace.copyWith(
                    color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: recoveryKey));
                FiloToast.show(context, message: 'Recovery key copied to clipboard', type: FiloToastType.success);
              },
              child: const Text('Copy Key'),
            ),
            FiloButton(
              label: 'I Have Saved It',
              size: FiloButtonSize.small,
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
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
      appBar: AppBar(
        title: const Text('Create Master Passphrase'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FiloSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Zero-Knowledge Passphrase',
                style: FiloTypography.title1.copyWith(
                  color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: FiloSpacing.xs),
              Text(
                'Your passphrase derives the master key (via Argon2id) used to encrypt every file on your device. We NEVER store this passphrase.',
                style: FiloTypography.body.copyWith(
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: FiloSpacing.xl),

              // Passphrase Field
              TextField(
                controller: _passphraseController,
                obscureText: _obscurePassphrase,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Passphrase',
                  filled: true,
                  fillColor: isDark ? FiloColors.darkSurfaceSecondary : FiloColors.lightSurfaceSecondary,
                  border: OutlineInputBorder(
                    borderRadius: FiloRadius.roundedMd,
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassphrase ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _obscurePassphrase = !_obscurePassphrase),
                  ),
                ),
              ),
              const SizedBox(height: FiloSpacing.sm),

              // Live Strength Meter
              if (pwd.isNotEmpty) ...[
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: strength / 4.0,
                          backgroundColor: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
                          valueColor: AlwaysStoppedAnimation<Color>(_getStrengthColor(strength)),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: FiloSpacing.md),
                    Text(
                      _getStrengthLabel(strength),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _getStrengthColor(strength),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FiloSpacing.lg),
              ] else
                const SizedBox(height: FiloSpacing.md),

              // Confirm Field
              TextField(
                controller: _confirmController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Confirm Passphrase',
                  filled: true,
                  fillColor: isDark ? FiloColors.darkSurfaceSecondary : FiloColors.lightSurfaceSecondary,
                  border: OutlineInputBorder(
                    borderRadius: FiloRadius.roundedMd,
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: FiloSpacing.xl),

              // Explicit Confirmation Warning
              Container(
                padding: const EdgeInsets.all(FiloSpacing.md),
                decoration: BoxDecoration(
                  color: isDark ? FiloColors.darkSurfaceSecondary : FiloColors.warningMuted,
                  borderRadius: FiloRadius.roundedMd,
                  border: Border.all(
                    color: FiloColors.warning.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: _confirmedLossRisk,
                      activeColor: FiloColors.primary,
                      onChanged: (val) {
                        setState(() => _confirmedLossRisk = val ?? false);
                      },
                    ),
                    const SizedBox(width: FiloSpacing.xs),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text(
                          'I understand that if I lose my passphrase, my files CANNOT be recovered by anyone, including the app developers.',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: FiloSpacing.xxl),

              // Create Vault Button
              FiloButton(
                label: 'Create Secure Vault',
                isLoading: _isLoading,
                onPressed: _confirmedLossRisk && pwd.isNotEmpty ? _handleSetupVault : null,
                size: FiloButtonSize.large,
                isFullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
