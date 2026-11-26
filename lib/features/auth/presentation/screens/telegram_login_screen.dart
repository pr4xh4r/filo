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
import '../../domain/auth_state.dart';
import '../../domain/country_code.dart';
import '../providers/auth_provider.dart';
import '../widgets/country_picker_sheet.dart';
import 'passphrase_setup_screen.dart';

enum LoginStep { phoneNumber, verificationCode, password2FA }

/// Multi-step Telegram authentication flow supporting Phone/SMS.
///
/// Designed with CRED luxury obsidian typography and iOS 18 liquid glass materials.
class TelegramLoginScreen extends ConsumerStatefulWidget {
  const TelegramLoginScreen({super.key});

  @override
  ConsumerState<TelegramLoginScreen> createState() =>
      _TelegramLoginScreenState();
}

class _TelegramLoginScreenState extends ConsumerState<TelegramLoginScreen> {
  LoginStep _step = LoginStep.phoneNumber;

  CountryCode _selectedCountry = CountryCode.defaultCountry;
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _codeHasError = false;
  String? _phoneErrorMessage;
  String? _codeErrorMessage;
  String? _passwordErrorMessage;
  bool _obscurePassword = true;

  String _formattedFullPhone = '';

  @override
  void initState() {
    super.initState();

    _phoneController.addListener(() {
      if (_phoneErrorMessage != null) {
        setState(() => _phoneErrorMessage = null);
      }
    });
    _codeController.addListener(() {
      if (_codeErrorMessage != null || _codeHasError) {
        setState(() {
          _codeErrorMessage = null;
          _codeHasError = false;
        });
      }
    });
    _passwordController.addListener(() {
      if (_passwordErrorMessage != null) {
        setState(() => _passwordErrorMessage = null);
      }
    });
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _onLoginSuccess() {
    if (!mounted) return;
    FiloToast.show(
      context,
      message: 'Telegram connected! Next, create your secret passphrase.',
      type: FiloToastType.success,
    );
    final auth = ref.read(authNotifierProvider);
    if (auth.vaultStatus == VaultSetupStatus.unconfigured) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const PassphraseSetupScreen()),
        (route) => false,
      );
    } else {
      Navigator.of(context).pop();
    }
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
      HapticFeedback.heavyImpact();
      setState(() {
        _phoneErrorMessage = 'Please enter your phone number';
      });
      return;
    }

    final digitsOnly = rawNumber.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 7 || digitsOnly.length > 15) {
      HapticFeedback.heavyImpact();
      setState(() {
        _phoneErrorMessage =
            'Please enter a valid phone number with country code (e.g. ${_selectedCountry.dialCode} 9876543210)';
      });
      return;
    }

    final fullPhone = _getFullPhoneNumber();
    _formattedFullPhone = fullPhone;

    setState(() {
      _isLoading = true;
      _phoneErrorMessage = null;
    });
    try {
      await ref.read(authNotifierProvider.notifier).sendTelegramCode(fullPhone);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _step = LoginStep.verificationCode;
          _codeHasError = false;
          _codeErrorMessage = null;
        });
        FiloToast.show(context, message: 'Verification code sent', type: FiloToastType.success);
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        final rawStr = e.toString().replaceAll('Exception: ', '').replaceAll('TimeoutException: ', '');
        final cleanMsg = rawStr.contains('PHONE_NUMBER') || rawStr.contains('Invalid phone number')
            ? 'Invalid phone number. Please check your country code and digits.'
            : rawStr;
        setState(() {
          _isLoading = false;
          _phoneErrorMessage = cleanMsg;
        });
        FiloToast.show(context, message: cleanMsg, type: FiloToastType.error);
      }
    }
  }

  Future<void> _handleSubmitCode([String? directCode]) async {
    final code = directCode ?? _codeController.text.trim();
    if (code.length < 5 || code.length > 6) {
      HapticFeedback.heavyImpact();
      setState(() {
        _codeHasError = true;
        _codeErrorMessage = 'Please enter the complete 5 or 6-digit code';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _codeHasError = false;
      _codeErrorMessage = null;
    });

    try {
      final res = await ref.read(authNotifierProvider.notifier).submitTelegramCode(code);
      if (mounted) {
        setState(() => _isLoading = false);

        if (res.step == StorageAuthStep.waitingForPassword) {
          setState(() {
            _step = LoginStep.password2FA;
            _passwordErrorMessage = null;
          });
        } else if (res.isAuthenticated) {
          _onLoginSuccess();
        }
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        final rawStr = e.toString().replaceAll('Exception: ', '').replaceAll('TimeoutException: ', '');
        final cleanMsg = rawStr.contains('PHONE_CODE') || rawStr.contains('Invalid verification code')
            ? 'Incorrect verification code. Please check your Telegram app.'
            : rawStr;
        setState(() {
          _isLoading = false;
          _codeHasError = true;
          _codeErrorMessage = cleanMsg;
        });
        FiloToast.show(context, message: cleanMsg, type: FiloToastType.error);
      }
    }
  }

  Future<void> _handleSubmitPassword() async {
    final pwd = _passwordController.text.trim();
    if (pwd.isEmpty) {
      HapticFeedback.heavyImpact();
      setState(() {
        _passwordErrorMessage = 'Please enter your cloud password';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _passwordErrorMessage = null;
    });
    try {
      final res = await ref.read(authNotifierProvider.notifier).submitTelegramPassword(pwd);
      if (mounted) {
        setState(() => _isLoading = false);

        if (res.isAuthenticated) {
          _onLoginSuccess();
        }
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        final rawStr = e.toString().replaceAll('Exception: ', '').replaceAll('TimeoutException: ', '');
        final cleanMsg = rawStr.contains('PASSWORD') || rawStr.contains('Incorrect')
            ? 'Incorrect cloud password. Please try again.'
            : rawStr;
        setState(() {
          _isLoading = false;
          _passwordErrorMessage = cleanMsg;
        });
        FiloToast.show(context, message: cleanMsg, type: FiloToastType.error);
      }
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
        _phoneErrorMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    ref.listen<FiloAuthState>(authNotifierProvider, (prev, next) {
      if (next.isTelegramAuthenticated && (prev == null || !prev.isTelegramAuthenticated)) {
        _onLoginSuccess();
      }
    });

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
                        if (_step == LoginStep.verificationCode) {
                          setState(() => _step = LoginStep.phoneNumber);
                        } else if (_step == LoginStep.password2FA) {
                          setState(() => _step = LoginStep.verificationCode);
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                  ],
                ),
              ),

              // Scrollable Body
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: MediaQuery.of(context).orientation == Orientation.landscape
                        ? FiloSpacing.xxl
                        : FiloSpacing.xl,
                    vertical: MediaQuery.of(context).orientation == Orientation.landscape
                        ? FiloSpacing.xs
                        : FiloSpacing.sm,
                  ),
                  physics: const BouncingScrollPhysics(),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_step == LoginStep.phoneNumber) ...[
                            _buildPhoneStep(isDark),
                          ] else if (_step == LoginStep.verificationCode) ...[
                            _buildVerificationCodeStep(isDark),
                          ] else if (_step == LoginStep.password2FA) ...[
                            _buildPassword2FAStep(isDark),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // STEP 1: Phone Number Input
  Widget _buildPhoneStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connect Telegram',
          style: FiloTypography.editorial(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.2,
            color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'We will send a quick code to your Telegram app',
          style: FiloTypography.body.copyWith(
            color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
            height: 1.4,
          ),
        ),
        if (ref.watch(authNotifierProvider).isTelegramAuthenticated) ...[
          const SizedBox(height: FiloSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF2AABEE).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF2AABEE).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF2AABEE), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Telegram session active',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2AABEE),
                        ),
                      ),
                      Text(
                        'Account: @${ref.watch(authNotifierProvider).telegramUserName ?? "telegram_user"}',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _onLoginSuccess,
                  child: const Text('Use This', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                TextButton(
                  onPressed: () async {
                    HapticFeedback.mediumImpact();
                    await ref.read(authNotifierProvider.notifier).signOutTelegram();
                  },
                  child: Text(
                    'Sign Out',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: FiloSpacing.xl),

        // Phone Input Card (Liquid Glass with Specular Stroke and Error Highlight)
        FiloGlass(
          borderRadius: FiloRadius.roundedXl,
          border: Border.all(
            color: _phoneErrorMessage != null
                ? FiloColors.destructive
                : (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08)),
            width: _phoneErrorMessage != null ? 1.8 : 1.0,
          ),
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
              // Phone Number Text Field
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

        if (_phoneErrorMessage != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, size: 16, color: FiloColors.destructive),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _phoneErrorMessage!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: FiloColors.destructive,
                  ),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: FiloSpacing.xxl),

        // Action Button
        _buildActionButton(
          label: 'Continue',
          isLoading: _isLoading,
          onPressed: _handleSendPhone,
          isDark: isDark,
        ),
      ],
    );
  }

  // STEP 2: Minimalist Single Block Verification Code
  Widget _buildVerificationCodeStep(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verify Code',
          style: FiloTypography.editorial(
            fontSize: 36,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.2,
            color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Enter the code sent to your Telegram app',
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
                  'Change',
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
            color: (_codeHasError || _codeErrorMessage != null)
                ? FiloColors.destructive
                : (isDark ? FiloColors.accentOrchid.withValues(alpha: 0.45) : FiloColors.primary.withValues(alpha: 0.35)),
            width: (_codeHasError || _codeErrorMessage != null) ? 1.8 : 1.2,
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
                hintText: 'Enter code',
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
                if (_codeHasError || _codeErrorMessage != null) {
                  setState(() {
                    _codeHasError = false;
                    _codeErrorMessage = null;
                  });
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

        if (_codeErrorMessage != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, size: 16, color: FiloColors.destructive),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _codeErrorMessage!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: FiloColors.destructive,
                  ),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: FiloSpacing.xxl),

        _buildActionButton(
          label: 'Confirm Code',
          isLoading: _isLoading,
          onPressed: () => _handleSubmitCode(),
          isDark: isDark,
        ),

        const SizedBox(height: FiloSpacing.md),

        Center(
          child: TextButton(
            onPressed: _isLoading ? null : _handleSendPhone,
            child: Text(
              'Resend Code',
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
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Security illustration centered cleanly WITHOUT container/card background
        Center(
          child: Image.asset(
            FiloIllustrations.security,
            height: isLandscape ? 90 : 170,
            fit: BoxFit.contain,
          ),
        ),
        SizedBox(height: isLandscape ? FiloSpacing.xs : FiloSpacing.lg),
        Text(
          'Cloud Password',
          style: FiloTypography.editorial(
            fontSize: isLandscape ? 28 : 36,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.2,
            color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your Telegram account is protected by two-step verification',
          style: FiloTypography.body.copyWith(
            color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
          ),
        ),
        const SizedBox(height: FiloSpacing.xl),

        FiloGlass(
          borderRadius: FiloRadius.roundedXl,
          border: Border.all(
            color: _passwordErrorMessage != null
                ? FiloColors.destructive
                : (isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08)),
            width: _passwordErrorMessage != null ? 1.8 : 1.0,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofocus: true,
            style: FiloTypography.title3.copyWith(
              color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
            ),
            decoration: InputDecoration(
              filled: false,
              fillColor: Colors.transparent,
              hintText: 'Enter your password',
              hintStyle: FiloTypography.title3.copyWith(
                color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                  size: 20,
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
            ),
            onSubmitted: (_) => _handleSubmitPassword(),
          ),
        ),

        if (_passwordErrorMessage != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, size: 16, color: FiloColors.destructive),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _passwordErrorMessage!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: FiloColors.destructive,
                  ),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: FiloSpacing.xxl),

        _buildActionButton(
          label: 'Unlock Account',
          isLoading: _isLoading,
          onPressed: _handleSubmitPassword,
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
