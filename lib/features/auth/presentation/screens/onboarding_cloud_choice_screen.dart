import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/crypto/qr_encoder.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/brand_logos.dart';
import '../../../../shared/components/filo_background.dart';
import '../../../../shared/components/filo_qr_scanner_screen.dart';
import '../../../../shared/components/filo_toast.dart';
import '../../../../shared/components/handwriting_text.dart';
import '../../domain/auth_state.dart';
import '../providers/auth_provider.dart';
import 'passphrase_setup_screen.dart';
import 'telegram_login_screen.dart';

/// Flagship onboarding screen with real Telegram branding,
/// cloud storage architecture guidance, and fast Telegram connect -> passphrase flow.
class OnboardingCloudChoiceScreen extends ConsumerStatefulWidget {
  const OnboardingCloudChoiceScreen({super.key});

  @override
  ConsumerState<OnboardingCloudChoiceScreen> createState() =>
      _OnboardingCloudChoiceScreenState();
}

class _OnboardingCloudChoiceScreenState
    extends ConsumerState<OnboardingCloudChoiceScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnimation;
  bool _isActionPressed = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _handleContinue() async {
    HapticFeedback.mediumImpact();
    final authState = ref.read(authNotifierProvider);

    if (authState.isTelegramAuthenticated) {
      FiloToast.show(
        context,
        message: 'Telegram connected! Next, create your secret passphrase.',
        type: FiloToastType.success,
      );
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const PassphraseSetupScreen()),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => const TelegramLoginScreen()),
      );
    }
  }

  Future<void> _handleQrPairing() async {
    final scannedData = await FiloQrScannerScreen.open(
      context,
      title: 'Pair Second Device',
      hint: 'Scan the QR code displayed on your primary device running Filo',
    );
    if (!mounted || scannedData == null) return;

    if (scannedData == 'MANUAL_ENTRY') {
      _showManualTokenDialog();
      return;
    }

    await _pairWithToken(scannedData);
  }

  void _showManualTokenDialog() {
    final tokenController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Pairing Token'),
        content: TextField(
          controller: tokenController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'filo://vault?bundle=... or JSON',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: FiloColors.primary),
            onPressed: () async {
              final token = tokenController.text.trim();
              if (token.isEmpty) return;
              Navigator.of(ctx).pop();
              await _pairWithToken(token);
            },
            child: const Text('Pair', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _pairWithToken(String token) async {
    try {
      final data = QrEncoder.parsePairingToken(token);
      final repo = ref.read(authRepositoryProvider);
      await repo.importVaultKeyBundle(data);
      if (!mounted) return;
      ref.read(authNotifierProvider.notifier).initialize();
      FiloToast.show(
        context,
        message: 'Paired successfully! Set up your space.',
        type: FiloToastType.success,
      );
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const PassphraseSetupScreen()),
      );
    } catch (e) {
      if (mounted) {
        final cleanMsg = e.toString().replaceAll('Exception: ', '').replaceAll('FormatException: ', '');
        FiloToast.show(context, message: 'Pairing failed: $cleanMsg', type: FiloToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      body: FiloBackground(
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isLandscape ? FiloSpacing.xxl : FiloSpacing.xl,
                    vertical: isLandscape ? FiloSpacing.sm : FiloSpacing.md,
                  ),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Back button
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
                      const SizedBox(height: 16),

                  // Cursive Handwriting Headline
                  HandwritingText(
                    text: 'Connect Telegram',
                    duration: const Duration(milliseconds: 1100),
                    style: FiloTypography.handwriting(
                      fontSize: 36,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Filo turns Telegram into your private, unlimited cloud drive.',
                    style: TextStyle(
                      fontFamily: FiloTypography.fontFamily,
                      fontSize: 14,
                      color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                    ),
                  ),

                  const SizedBox(height: 26),

                  // Step 1: Provider Card
                  Text(
                    '1. CLOUD STORAGE PLATFORM',
                    style: TextStyle(
                      fontFamily: FiloTypography.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Real Telegram Brand Card
                  _buildTelegramCard(
                    isDark: isDark,
                    authState: authState,
                  ),

                  const SizedBox(height: 26),

                  // Step 2: Storage Architecture Guidance
                  Text(
                    '2. HOW FILO STORES YOUR FILES IN TELEGRAM',
                    style: TextStyle(
                      fontFamily: FiloTypography.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Guidance 1: Encrypted
                  _buildGuidanceCard(
                    title: 'Encrypted',
                    badge: 'Unlimited',
                    description:
                        'This data is encrypted and will only be decrypted by Filo. Even Telegram cannot see your files.',
                    icon: Icons.lock_outline_rounded,
                    isDark: isDark,
                  ),

                  const SizedBox(height: 10),

                  // Guidance 2: Viewable Anywhere
                  _buildGuidanceCard(
                    title: 'Viewable Anywhere',
                    badge: '2 GB / 4 GB Premium',
                    description:
                        'This data will be viewable anywhere. Up to 2 GB per file (or 4 GB per file if you have Telegram Premium).',
                    icon: Icons.visibility_outlined,
                    isDark: isDark,
                  ),

                  const SizedBox(height: 28),

                  // Primary Action Button
                  GestureDetector(
                    onTapDown: (_) => setState(() => _isActionPressed = true),
                    onTapUp: (_) => setState(() => _isActionPressed = false),
                    onTapCancel: () => setState(() => _isActionPressed = false),
                    onTap: _handleContinue,
                    child: AnimatedScale(
                      scale: _isActionPressed ? 0.97 : 1.0,
                      duration: const Duration(milliseconds: 120),
                      child: Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [FiloColors.primary, Color(0xFF1E293B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: FiloRadius.roundedFull,
                          boxShadow: [
                            BoxShadow(
                              color: FiloColors.primary.withValues(alpha: 0.25),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const TelegramBrandLogo(size: 22),
                            const SizedBox(width: 10),
                            Text(
                              authState.isTelegramAuthenticated
                                  ? 'Continue with Telegram'
                                  : 'Connect Telegram',
                              style: FiloTypography.callout.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Cross-device pairing link
                  Center(
                    child: GestureDetector(
                      onTap: _handleQrPairing,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.black.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.qr_code_scanner_rounded,
                              size: 15,
                              color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Pairing a second device? Scan QR code',
                              style: TextStyle(
                                fontFamily: FiloTypography.fontFamily,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: FiloSpacing.md),
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

  Widget _buildTelegramCard({
    required bool isDark,
    required FiloAuthState authState,
  }) {
    final isConnected = authState.isTelegramAuthenticated;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF262638) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: FiloColors.primary,
          width: 2.0,
        ),
        boxShadow: [
          BoxShadow(
            color: FiloColors.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TelegramBrandLogo(size: 38),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Telegram Cloud Storage',
                      style: TextStyle(
                        fontFamily: FiloTypography.fontFamily,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Unlimited Cloud Storage',
                      style: TextStyle(
                        fontFamily: FiloTypography.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.check_circle_rounded,
                size: 20,
                color: Colors.white,
              ),
            ],
          ),
          if (isConnected) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF2AABEE).withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF2AABEE).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_circle_rounded,
                    size: 16,
                    color: Color(0xFF2AABEE),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      authState.telegramUserName != null && authState.telegramUserName!.isNotEmpty
                          ? 'Session active: @${authState.telegramUserName}'
                          : (authState.telegramDisplayName != null
                              ? 'Session active: ${authState.telegramDisplayName}'
                              : 'Session active: Telegram User'),
                      style: const TextStyle(
                        fontFamily: FiloTypography.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Text(
                    '✓ Ready',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2AABEE),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildGuidanceCard({
    required String title,
    required String badge,
    required String description,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
          width: 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: FiloColors.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 18,
              color: FiloColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: FiloTypography.fontFamily,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: isDark ? Colors.white : FiloColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: FiloColors.primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        badge,
                        style: const TextStyle(
                          fontFamily: FiloTypography.fontFamily,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: FiloColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: FiloTypography.fontFamily,
                    fontSize: 12,
                    height: 1.4,
                    color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
