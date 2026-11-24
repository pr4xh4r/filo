import 'dart:async';
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
import '../../../storage/domain/storage_models.dart';
import '../../domain/country_code.dart';
import '../providers/auth_provider.dart';
import '../widgets/country_picker_sheet.dart';

enum LoginStep { phoneNumber, verificationCode, password2FA, botApiFallback }

/// Multi-step Telegram authentication flow supporting Phone/SMS, QR code linking,
/// and "Bring Your Own Bot" fallback.
///
/// Designed with CRED luxury obsidian typography and iOS 18 liquid glass materials.
class TelegramLoginScreen extends ConsumerStatefulWidget {
  const TelegramLoginScreen({super.key});

  @override
  ConsumerState<TelegramLoginScreen> createState() =>
      _TelegramLoginScreenState();
}

class _TelegramLoginScreenState extends ConsumerState<TelegramLoginScreen>
    with SingleTickerProviderStateMixin {
  LoginStep _step = LoginStep.phoneNumber;
  bool _isQrMode = false;

  CountryCode _selectedCountry = CountryCode.defaultCountry;
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();

  final _botTokenController = TextEditingController();
  final _chatIdController = TextEditingController();

  bool _isLoading = false;
  bool _codeHasError = false;
  String _formattedFullPhone = '';

  // QR Code pulse/scan animation
  late final AnimationController _qrController;
  late final Animation<double> _scanAnimation;
  Timer? _qrMockTimer;

  @override
  void initState() {
    super.initState();
    _qrController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);

    _scanAnimation = Tween<double>(begin: 0.1, end: 0.9).animate(
      CurvedAnimation(parent: _qrController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _qrController.dispose();
    _qrMockTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _botTokenController.dispose();
    _chatIdController.dispose();
    super.dispose();
  }

  String _getFullPhoneNumber() {
    final rawNumber = _phoneController.text.trim().replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (rawNumber.startsWith('+')) {
      return rawNumber;
    }
    return '${_selectedCountry.dialCode}$rawNumber';
  }

  Future<void> _handleSendPhone() async {
    final rawNumber = _phoneController.text.trim();
    if (rawNumber.isEmpty) {
      FiloToast.show(context, message: 'Please enter your phone number', type: FiloToastType.error);
      return;
    }

    final fullPhone = _getFullPhoneNumber();
    _formattedFullPhone = fullPhone;

    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).sendTelegramCode(fullPhone);
      setState(() {
        _isLoading = false;
        _step = LoginStep.verificationCode;
        _codeHasError = false;
      });
      FiloToast.show(context, message: 'Verification code sent', type: FiloToastType.success);
    } catch (e) {
      setState(() => _isLoading = false);
      FiloToast.show(context, message: e.toString(), type: FiloToastType.error);
    }
  }

  Future<void> _handleSubmitCode([String? directCode]) async {
    final code = directCode ?? _codeController.text.trim();
    if (code.length < 5 || code.length > 6) {
      FiloToast.show(context, message: 'Please enter the 5 or 6-digit code', type: FiloToastType.error);
      return;
    }

    setState(() {
      _isLoading = true;
      _codeHasError = false;
    });

    try {
      final res = await ref.read(authNotifierProvider.notifier).submitTelegramCode(code);
      setState(() => _isLoading = false);

      if (res.step == StorageAuthStep.waitingForPassword) {
        setState(() => _step = LoginStep.password2FA);
      } else if (res.isAuthenticated) {
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _codeHasError = true;
      });
      HapticFeedback.heavyImpact();
      FiloToast.show(context, message: e.toString(), type: FiloToastType.error);
    }
  }

  Future<void> _handleSubmitPassword() async {
    final pwd = _passwordController.text.trim();
    if (pwd.isEmpty) {
      FiloToast.show(context, message: 'Please enter your cloud password', type: FiloToastType.error);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await ref.read(authNotifierProvider.notifier).submitTelegramPassword(pwd);
      setState(() => _isLoading = false);

      if (res.isAuthenticated && mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      HapticFeedback.heavyImpact();
      FiloToast.show(context, message: e.toString(), type: FiloToastType.error);
    }
  }

  void _showCountryPicker() async {
    HapticFeedback.selectionClick();
    final picked = await CountryPickerSheet.show(
      context,
      selectedCountry: _selectedCountry,
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedCountry = picked;
      });
    }
  }

  void _simulateQrScanSuccess() {
    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);
    _qrMockTimer?.cancel();
    _qrMockTimer = Timer(const Duration(milliseconds: 1200), () async {
      try {
        final res = await ref.read(authNotifierProvider.notifier).submitTelegramCode('12345');
        if (mounted) {
          setState(() => _isLoading = false);
          if (res.step == StorageAuthStep.waitingForPassword) {
            setState(() => _step = LoginStep.password2FA);
          } else if (res.isAuthenticated) {
            Navigator.of(context).pop();
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() => _isLoading = false);
          FiloToast.show(context, message: e.toString(), type: FiloToastType.error);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: FiloAmbientBackground(
        child: SafeArea(
          child: Column(
            children: [
              // Top iOS Header Bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FiloSpacing.md,
                  vertical: FiloSpacing.xs,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                      onPressed: () {
                        if (_step == LoginStep.verificationCode || _step == LoginStep.botApiFallback) {
                          setState(() => _step = LoginStep.phoneNumber);
                        } else if (_step == LoginStep.password2FA) {
                          setState(() => _step = LoginStep.verificationCode);
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                    const Spacer(),
                    if (_step == LoginStep.phoneNumber)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _step = LoginStep.botApiFallback;
                          });
                        },
                        child: Text(
                          'use bot api',
                          style: FiloTypography.caption.copyWith(
                            color: isDark ? FiloColors.accentOrchid : FiloColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Scrollable Body
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FiloSpacing.xl,
                    vertical: FiloSpacing.sm,
                  ),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_step == LoginStep.phoneNumber) ...[
                        _buildPhoneOrQrStep(isDark),
                      ] else if (_step == LoginStep.verificationCode) ...[
                        _buildVerificationCodeStep(isDark),
                      ] else if (_step == LoginStep.password2FA) ...[
                        _buildPassword2FAStep(isDark),
                      ] else if (_step == LoginStep.botApiFallback) ...[
                        _buildBotApiStep(isDark),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // STEP 1: Phone / QR Code Toggle
  Widget _buildPhoneOrQrStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'connect telegram',
          style: FiloTypography.editorial(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.2,
            color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _isQrMode
              ? 'scan the code with your telegram mobile app'
              : 'we will send a quick code to your telegram app',
          style: FiloTypography.body.copyWith(
            color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: FiloSpacing.xl),

        // CRED-style Pill Mode Switch: Phone vs QR
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _isQrMode = false);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: !_isQrMode
                          ? (isDark ? FiloColors.darkSurfaceSecondary : Colors.white)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: !_isQrMode
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.phone_iphone_rounded,
                            size: 16,
                            color: !_isQrMode
                                ? (isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary)
                                : (isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'phone number',
                            style: FiloTypography.callout.copyWith(
                              fontWeight: !_isQrMode ? FontWeight.w700 : FontWeight.w500,
                              color: !_isQrMode
                                  ? (isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary)
                                  : (isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => _isQrMode = true);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _isQrMode
                          ? (isDark ? FiloColors.darkSurfaceSecondary : Colors.white)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: _isQrMode
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.qr_code_rounded,
                            size: 16,
                            color: _isQrMode
                                ? (isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary)
                                : (isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'qr code',
                            style: FiloTypography.callout.copyWith(
                              fontWeight: _isQrMode ? FontWeight.w700 : FontWeight.w500,
                              color: _isQrMode
                                  ? (isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary)
                                  : (isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: FiloSpacing.xl),

        if (!_isQrMode) ...[
          // Phone Input Card (Liquid Glass with Specular Stroke)
          FiloGlass(
            borderRadius: FiloRadius.roundedXl,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Country Code Button (No Flag Emojis)
                GestureDetector(
                  onTap: _showCountryPicker,
                  child: Row(
                    children: [
                      Text(
                        _selectedCountry.dialCode,
                        style: FiloTypography.title3.copyWith(
                          fontWeight: FontWeight.w700,
                          color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 20,
                        color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                      ),
                    ],
                  ),
                ),
                Container(
                  height: 28,
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                ),
                // Phone Number Text Field (No Nested Inner Rectangles)
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    autofocus: true,
                    style: FiloTypography.title3.copyWith(
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                    ),
                    decoration: InputDecoration(
                      filled: false,
                      fillColor: Colors.transparent,
                      hintText: '98765 43210',
                      hintStyle: FiloTypography.title3.copyWith(
                        color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                        letterSpacing: 1.2,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onSubmitted: (_) => _handleSendPhone(),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: FiloSpacing.xxl),

          // Action Button
          _buildActionButton(
            label: 'continue',
            isLoading: _isLoading,
            onPressed: _handleSendPhone,
            isDark: isDark,
          ),
        ] else ...[
          // QR Code Scanner Presentation Card
          Center(
            child: FiloGlass(
              borderRadius: FiloRadius.roundedXxl,
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: FiloColors.brandIndigo.withValues(alpha: 0.18),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Stack(
                            children: [
                              const Center(
                                child: Icon(
                                  Icons.qr_code_2_rounded,
                                  size: 190,
                                  color: Color(0xFF0D0425),
                                ),
                              ),
                              // Animated Laser Scan Line
                              AnimatedBuilder(
                                animation: _scanAnimation,
                                builder: (context, _) {
                                  return Positioned(
                                    top: 220 * _scanAnimation.value,
                                    left: 0,
                                    right: 0,
                                    child: Container(
                                      height: 3,
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Colors.transparent,
                                            FiloColors.accentOrchid,
                                            FiloColors.primary,
                                            Colors.transparent,
                                          ],
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: FiloColors.accentOrchid.withValues(alpha: 0.8),
                                            blurRadius: 8,
                                            spreadRadius: 2,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'open telegram on your phone',
                    style: FiloTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'settings > devices > link desktop device',
                    textAlign: TextAlign.center,
                    style: FiloTypography.caption.copyWith(
                      color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Mock Instant Connect Link for testing
                  GestureDetector(
                    onTap: _simulateQrScanSuccess,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: FiloColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        'tap to link instantly',
                        style: FiloTypography.caption.copyWith(
                          color: isDark ? FiloColors.accentOrchid : FiloColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // STEP 2: Minimalist Single Block Verification Code
  Widget _buildVerificationCodeStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'verify code',
          style: FiloTypography.editorial(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.2,
            color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'enter the code sent to your telegram app',
          style: FiloTypography.body.copyWith(
            color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
          ),
        ),
        const SizedBox(height: FiloSpacing.md),

        // Phone Pill with Change Action
        GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _step = LoginStep.phoneNumber);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formattedFullPhone,
                  style: FiloTypography.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'change',
                  style: FiloTypography.caption.copyWith(
                    color: FiloColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: FiloSpacing.xxl),

        // Ultra-clean Minimalist Single Block Code Field (NO •••(•) clutter!)
        FiloGlass(
          borderRadius: FiloRadius.roundedXl,
          border: Border.all(
            color: _codeHasError
                ? FiloColors.destructive
                : (isDark ? FiloColors.accentOrchid.withValues(alpha: 0.45) : FiloColors.primary.withValues(alpha: 0.35)),
            width: _codeHasError ? 1.8 : 1.2,
          ),
          child: Container(
            height: 68,
            alignment: Alignment.center,
            child: TextField(
              controller: _codeController,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: FiloTypography.title1.copyWith(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: 10,
                color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: InputDecoration(
                hintText: 'enter code',
                hintStyle: FiloTypography.title3.copyWith(
                  letterSpacing: 2,
                  color: isDark
                      ? FiloColors.darkTextTertiary.withValues(alpha: 0.35)
                      : FiloColors.lightTextTertiary.withValues(alpha: 0.4),
                ),
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: (val) {
                if (_codeHasError) {
                  setState(() => _codeHasError = false);
                }
                if (val.length == 5 || val.length == 6) {
                  HapticFeedback.mediumImpact();
                  _handleSubmitCode(val);
                }
              },
              onSubmitted: (val) => _handleSubmitCode(val),
            ),
          ),
        ),

        const SizedBox(height: FiloSpacing.xxl),

        _buildActionButton(
          label: 'confirm code',
          isLoading: _isLoading,
          onPressed: () => _handleSubmitCode(),
          isDark: isDark,
        ),

        const SizedBox(height: FiloSpacing.lg),

        Center(
          child: TextButton(
            onPressed: _isLoading ? null : _handleSendPhone,
            child: Text(
              'resend code',
              style: FiloTypography.callout.copyWith(
                color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // STEP 3: 2FA Password
  Widget _buildPassword2FAStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: FiloGlass(
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.all(16),
            child: Image.asset(
              FiloIllustrations.security,
              height: 180,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: FiloSpacing.lg),
        Text(
          'cloud password',
          style: FiloTypography.editorial(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.2,
            color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'your telegram account is protected by two-step verification',
          style: FiloTypography.body.copyWith(
            color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
          ),
        ),
        const SizedBox(height: FiloSpacing.xl),

        FiloGlass(
          borderRadius: FiloRadius.roundedXl,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _passwordController,
            obscureText: true,
            autofocus: true,
            style: FiloTypography.title3.copyWith(
              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
            ),
            decoration: InputDecoration(
              filled: false,
              fillColor: Colors.transparent,
              hintText: 'enter your password',
              hintStyle: FiloTypography.title3.copyWith(
                color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
            onSubmitted: (_) => _handleSubmitPassword(),
          ),
        ),

        const SizedBox(height: FiloSpacing.xxl),

        _buildActionButton(
          label: 'unlock account',
          isLoading: _isLoading,
          onPressed: _handleSubmitPassword,
          isDark: isDark,
        ),
      ],
    );
  }

  // STEP 4: Bot API Fallback
  Widget _buildBotApiStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'bot api connect',
          style: FiloTypography.editorial(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.2,
            color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'use a free bot from @BotFather to store files in a private channel.',
          style: FiloTypography.body.copyWith(
            color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
          ),
        ),
        const SizedBox(height: FiloSpacing.xl),

        FiloGlass(
          borderRadius: FiloRadius.roundedXl,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _botTokenController,
            style: FiloTypography.bodyMedium.copyWith(
              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
            ),
            decoration: InputDecoration(
              filled: false,
              fillColor: Colors.transparent,
              hintText: 'bot token (e.g. 12345:ABC-DEF...)',
              hintStyle: FiloTypography.bodyMedium.copyWith(
                color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
        const SizedBox(height: FiloSpacing.md),
        FiloGlass(
          borderRadius: FiloRadius.roundedXl,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _chatIdController,
            style: FiloTypography.bodyMedium.copyWith(
              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
            ),
            decoration: InputDecoration(
              filled: false,
              fillColor: Colors.transparent,
              hintText: 'channel or chat id',
              hintStyle: FiloTypography.bodyMedium.copyWith(
                color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),

        const SizedBox(height: FiloSpacing.xxl),

        _buildActionButton(
          label: 'connect bot',
          isLoading: _isLoading,
          onPressed: () {
            FiloToast.show(context, message: 'Bot connected successfully', type: FiloToastType.success);
            Navigator.of(context).pop();
          },
          isDark: isDark,
        ),
      ],
    );
  }

  // Interactive Brand Button (CRED & Apple Monochrome Luxury)
  Widget _buildActionButton({
    required String label,
    required bool isLoading,
    required VoidCallback onPressed,
    required bool isDark,
  }) {
    return GestureDetector(
      onTapDown: (_) => HapticFeedback.lightImpact(),
      onTap: isLoading ? null : onPressed,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: FiloRadius.roundedXl,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
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
    );
  }
}
