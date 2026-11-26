import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/crypto/qr_encoder.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../core/theme/persona_provider.dart';
import '../../../../shared/components/filo_glass.dart';
import '../../../../shared/components/filo_qr_scanner_screen.dart';
import '../../../../shared/components/filo_sheet.dart';
import '../../../../shared/components/filo_toast.dart';
import '../../../files/presentation/screens/file_browser_screen.dart';
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
  String? _errorMessage;

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

    setState(() => _errorMessage = null);

    if (pwd.length < 8) {
      HapticFeedback.heavyImpact();
      setState(() => _errorMessage = 'Passphrase must be at least 8 characters long.');
      FiloToast.show(context, message: 'Passphrase must be at least 8 characters long', type: FiloToastType.error);
      return;
    }

    if (pwd != confirm) {
      HapticFeedback.heavyImpact();
      setState(() => _errorMessage = 'Passphrases do not match. Please re-enter.');
      FiloToast.show(context, message: 'Passphrases do not match', type: FiloToastType.error);
      return;
    }

    if (!_confirmedLossRisk) {
      HapticFeedback.mediumImpact();
      setState(() => _errorMessage = 'Please confirm you saved your key by checking the box.');
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
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
      FiloToast.show(context, message: e.toString(), type: FiloToastType.error);
    }
  }

  Future<void> _handleRestoreFromCloud() async {
    setState(() => _isLoading = true);
    try {
      final found = await ref.read(authNotifierProvider.notifier).checkForCloudVault();
      if (!mounted) return;
      if (found) {
        FiloToast.show(context, message: 'Existing space detected! Please enter your passphrase.', type: FiloToastType.success);
      } else {
        FiloToast.show(context, message: 'No existing backup found in Telegram.', type: FiloToastType.info);
      }
    } catch (e) {
      if (mounted) {
        FiloToast.show(context, message: 'Cloud check error: $e', type: FiloToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handlePastePairingToken() async {
    final scanned = await FiloQrScannerScreen.open(
      context,
      title: 'Scan Pairing QR',
      hint: 'Scan the QR code from your existing device to pair',
    );
    if (!mounted || scanned == null) return;

    String? token = scanned;
    if (scanned == 'MANUAL_ENTRY') {
      final tokenController = TextEditingController();
      final isDark = Theme.of(context).brightness == Brightness.dark;
      token = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: isDark ? FiloColors.darkSurface : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            'Pair Space with Token',
            style: FiloTypography.title3.copyWith(
              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Paste the pairing token or QR payload exported from your other device:',
                style: FiloTypography.caption.copyWith(
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? FiloColors.darkSurfaceSecondary : const Color(0xFFF5F5F7),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? FiloColors.darkBorder : const Color(0xFFE5E5EA),
                  ),
                ),
                child: TextField(
                  controller: tokenController,
                  maxLines: 3,
                  style: FiloTypography.monospace.copyWith(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: 'Paste pairing code here',
                    border: InputBorder.none,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(tokenController.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: FiloColors.primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Import', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    if (token == null || token.isEmpty) return;

    try {
      final data = QrEncoder.parsePairingToken(token);
      final repo = ref.read(authRepositoryProvider);
      final hasVault = await repo.hasConfiguredVault();
      if (hasVault && mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Replace Existing Keys?'),
            content: const Text(
              'Importing this pairing token will replace the existing space configuration on this device. '
              'Are you sure you want to proceed?',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: FiloColors.destructive),
                child: const Text('Replace & Pair', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
      await repo.importVaultKeyBundle(data);
      if (!mounted) return;
      ref.read(authNotifierProvider.notifier).initialize();
      FiloToast.show(context, message: 'Device paired! Please enter your passphrase.', type: FiloToastType.success);
    } catch (e) {
      if (mounted) {
        final cleanMsg = e.toString().replaceAll('Exception: ', '').replaceAll('FormatException: ', '');
        setState(() => _errorMessage = 'Pairing error: $cleanMsg');
        FiloToast.show(context, message: 'Pairing failed: $cleanMsg', type: FiloToastType.error);
      }
    }
  }

  void _showRecoveryKeySheet(String recoveryKey) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    FiloSheet.show(
      context: context,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Illustration / Icon Header
          Center(
            child: Container(
              height: isLandscape ? 60 : 110,
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: Image.asset(
                FiloIllustrations.recovery,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Handwritten Cursive Title
          Center(
            child: Text(
              'Emergency Recovery Key',
              textAlign: TextAlign.center,
              style: FiloTypography.handwriting(
                fontSize: isLandscape ? 22 : 26,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : FiloColors.lightTextPrimary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Save this in a secure place. If you ever forget your passphrase, this is the only way to recover your files.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: FiloTypography.fontFamily,
              fontSize: 12.5,
              height: 1.35,
              color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 18),

          // Recovery Key Box with Monospace font and inline copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.10),
                width: 1.0,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    recoveryKey,
                    style: TextStyle(
                      fontFamily: FiloTypography.monospaceFontFamily,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  color: FiloColors.primary,
                  tooltip: 'Copy Key',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: recoveryKey));
                    HapticFeedback.lightImpact();
                    FiloToast.show(context, message: 'Recovery key copied', type: FiloToastType.success);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Primary Gradient Action Button
          GestureDetector(
            onTap: () {
              HapticFeedback.mediumImpact();
              Navigator.of(context).pop();
              ref.read(authNotifierProvider.notifier).completeVaultSetup();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const FileBrowserScreen()),
                (route) => false,
              );
            },
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [FiloColors.primary, Color(0xFF1E293B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(100),
                boxShadow: [
                  BoxShadow(
                    color: FiloColors.primary.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  'Start Using Filo',
                  style: FiloTypography.callout.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final pwd = _passphraseController.text;
    final strength = _calculateStrength(pwd);

    return Scaffold(
      body: FiloAmbientBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: isLandscape ? FiloSpacing.xxl : FiloSpacing.xl,
                  vertical: isLandscape ? FiloSpacing.sm : FiloSpacing.lg,
                ),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (Navigator.of(context).canPop()) ...[
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 20,
                          color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(height: FiloSpacing.md),
                    ] else ...[
                      const SizedBox(height: FiloSpacing.sm),
                    ],

                    Text(
                      'Create Passphrase',
                      style: FiloTypography.editorial(
                        fontSize: isLandscape ? 28 : 36,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1.2,
                        color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                      ),
                    ),
                const SizedBox(height: 4),
                Text(
                  'Choose a secret key only you know. It protects every file on your phone.',
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
                    onChanged: (_) {
                      setState(() {
                        if (_errorMessage != null) _errorMessage = null;
                      });
                    },
                    style: FiloTypography.title3.copyWith(
                      color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                    ),
                    decoration: InputDecoration(
                      filled: false,
                      fillColor: Colors.transparent,
                      hintText: 'Choose your key (min 8 chars)',
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
                    onChanged: (_) {
                      if (_errorMessage != null) setState(() => _errorMessage = null);
                    },
                    decoration: InputDecoration(
                      filled: false,
                      fillColor: Colors.transparent,
                      hintText: 'Confirm your key',
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
                          'I understand nobody can recover my files if I lose this key.',
                          style: FiloTypography.caption.copyWith(
                            color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: FiloSpacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: FiloColors.destructive.withValues(alpha: 0.12),
                      borderRadius: FiloRadius.roundedLg,
                      border: Border.all(
                        color: FiloColors.destructive.withValues(alpha: 0.4),
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          size: 20,
                          color: FiloColors.destructive,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: FiloColors.destructive,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: FiloSpacing.lg),

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
                                  'Create Space',
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

                // Sleek Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: isDark ? Colors.white12 : Colors.black12)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        'OR RECOVER SPACE',
                        style: TextStyle(
                          fontFamily: FiloTypography.fontFamily,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: isDark ? Colors.white12 : Colors.black12)),
                  ],
                ),

                const SizedBox(height: FiloSpacing.md),

                // Option 1: Already have a space? Restore from Telegram
                GestureDetector(
                  onTap: _isLoading ? null : _handleRestoreFromCloud,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: FiloColors.primary.withValues(alpha: 0.14),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.cloud_download_rounded,
                            size: 19,
                            color: FiloColors.primary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Already have a space?',
                                style: TextStyle(
                                  fontFamily: FiloTypography.fontFamily,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Restore existing files and keys from Telegram',
                                style: TextStyle(
                                  fontFamily: FiloTypography.fontFamily,
                                  fontSize: 11.5,
                                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Option 2: Pair with token / QR code
                GestureDetector(
                  onTap: _isLoading ? null : _handlePastePairingToken,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.qr_code_2_rounded,
                            size: 19,
                            color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Pair with token',
                                style: TextStyle(
                                  fontFamily: FiloTypography.fontFamily,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Scan QR code or paste pairing token from another phone',
                                style: TextStyle(
                                  fontFamily: FiloTypography.fontFamily,
                                  fontSize: 11.5,
                                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: FiloSpacing.lg),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);
  }
}
