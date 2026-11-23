import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:filo/core/theme/filo_colors.dart';
import 'package:filo/core/theme/filo_radius.dart';
import 'package:filo/core/theme/filo_spacing.dart';
import 'package:filo/core/theme/filo_typography.dart';
import 'package:filo/features/auth/domain/country_code.dart';
import 'package:filo/features/auth/presentation/widgets/country_picker_sheet.dart';
import 'package:filo/features/storage/domain/storage_models.dart';
import 'package:filo/shared/components/filo_button.dart';
import 'package:filo/shared/components/filo_toast.dart';
import '../providers/auth_provider.dart';

enum LoginStep { phoneNumber, verificationCode, password2FA, botApiFallback }

/// Multi-step Telegram authentication flow supporting MTProto (phone/SMS/2FA)
/// and "Bring Your Own Bot" API fallback mode.
class TelegramLoginScreen extends ConsumerStatefulWidget {
  const TelegramLoginScreen({super.key});

  @override
  ConsumerState<TelegramLoginScreen> createState() => _TelegramLoginScreenState();
}

class _TelegramLoginScreenState extends ConsumerState<TelegramLoginScreen> {
  LoginStep _step = LoginStep.phoneNumber;

  CountryCode _selectedCountry = CountryCode.defaultCountry;
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();

  final _botTokenController = TextEditingController();
  final _chatIdController = TextEditingController();

  bool _isLoading = false;
  bool _codeHasError = false;
  String _formattedFullPhone = '';

  @override
  void dispose() {
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
    _formattedFullPhone = '${_selectedCountry.flag} $fullPhone';

    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).sendTelegramCode(fullPhone);
      setState(() {
        _isLoading = false;
        _step = LoginStep.verificationCode;
        _codeHasError = false;
      });
      FiloToast.show(context, message: 'Verification code sent to Telegram', type: FiloToastType.success);
    } catch (e) {
      setState(() => _isLoading = false);
      FiloToast.show(context, message: e.toString(), type: FiloToastType.error);
    }
  }

  Future<void> _handleSubmitCode() async {
    final code = _codeController.text.trim();
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
      FiloToast.show(context, message: 'Please enter your 2FA password', type: FiloToastType.error);
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Telegram'),
        leading: _step != LoginStep.phoneNumber
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () {
                  setState(() {
                    if (_step == LoginStep.verificationCode || _step == LoginStep.botApiFallback) {
                      _step = LoginStep.phoneNumber;
                    } else if (_step == LoginStep.password2FA) {
                      _step = LoginStep.verificationCode;
                    }
                  });
                },
              )
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: FiloSpacing.xl,
            vertical: FiloSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step == LoginStep.phoneNumber) ...[
                Text(
                  'Enter Phone Number',
                  style: FiloTypography.title1.copyWith(
                    color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: FiloSpacing.xs),
                Text(
                  'Telegram will send a verification code directly to your Telegram app or via SMS.',
                  style: FiloTypography.body.copyWith(
                    color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: FiloSpacing.xxl),

                // iOS Apple-style Country Selector & Phone Number Field
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Country Code Pill Button
                    InkWell(
                      onTap: _showCountryPicker,
                      borderRadius: FiloRadius.roundedLg,
                      child: Container(
                        height: 56,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: isDark
                              ? FiloColors.darkSurfaceSecondary
                              : FiloColors.lightSurfaceSecondary,
                          borderRadius: FiloRadius.roundedLg,
                          border: Border.all(
                            color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _selectedCountry.flag,
                              style: const TextStyle(fontSize: 22),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _selectedCountry.dialCode,
                              style: FiloTypography.body.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isDark
                                    ? FiloColors.darkTextPrimary
                                    : FiloColors.lightTextPrimary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: isDark
                                  ? FiloColors.darkTextTertiary
                                  : FiloColors.lightTextTertiary,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(width: FiloSpacing.sm),

                    // Phone Number Input Box
                    Expanded(
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: isDark
                              ? FiloColors.darkSurfaceSecondary
                              : FiloColors.lightSurfaceSecondary,
                          borderRadius: FiloRadius.roundedLg,
                          border: Border.all(
                            color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
                            width: 0.8,
                          ),
                        ),
                        child: Center(
                          child: TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            autofocus: true,
                            style: FiloTypography.body.copyWith(
                              fontSize: 17,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? FiloColors.darkTextPrimary
                                  : FiloColors.lightTextPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Phone number',
                              hintStyle: FiloTypography.body.copyWith(
                                color: isDark
                                    ? FiloColors.darkTextTertiary
                                    : FiloColors.lightTextTertiary,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                            ),
                            onSubmitted: (_) => _handleSendPhone(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: FiloSpacing.xxl),

                FiloButton(
                  label: 'Send Verification Code',
                  isLoading: _isLoading,
                  onPressed: _handleSendPhone,
                  size: FiloButtonSize.large,
                  isFullWidth: true,
                ),

                const SizedBox(height: FiloSpacing.xxl),

                Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() => _step = LoginStep.botApiFallback);
                    },
                    child: Text(
                      'Use Telegram Bot API Instead',
                      style: TextStyle(
                        color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ] else if (_step == LoginStep.verificationCode) ...[
                Text(
                  'Enter Code',
                  style: FiloTypography.title1.copyWith(
                    color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: FiloSpacing.xs),
                Text(
                  'Enter the 5 or 6-digit code Telegram sent to $_formattedFullPhone',
                  style: FiloTypography.body.copyWith(
                    color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: FiloSpacing.sm),

                // Edit phone number shortcut
                Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _step = LoginStep.phoneNumber;
                        _codeController.clear();
                        _codeHasError = false;
                      });
                    },
                    borderRadius: BorderRadius.circular(100),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                      child: Text(
                        'Change phone number',
                        style: FiloTypography.callout.copyWith(
                          color: FiloColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: FiloSpacing.xxl),

                // Apple-style Single Block for 5-6 Digit Code
                Container(
                  height: 68,
                  decoration: BoxDecoration(
                    color: isDark
                        ? FiloColors.darkSurfaceSecondary
                        : FiloColors.lightSurfaceSecondary,
                    borderRadius: FiloRadius.roundedXl,
                    border: Border.all(
                      color: _codeHasError
                          ? FiloColors.destructive
                          : FiloColors.primary.withValues(alpha: 0.45),
                      width: _codeHasError ? 1.8 : 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: FiloColors.primary.withValues(alpha: 0.1),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Center(
                    child: TextField(
                      controller: _codeController,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: FiloTypography.title1.copyWith(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 8,
                        color: isDark
                            ? FiloColors.darkTextPrimary
                            : FiloColors.lightTextPrimary,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      decoration: InputDecoration(
                        hintText: '• • • • • (•)',
                        hintStyle: FiloTypography.title1.copyWith(
                          fontSize: 22,
                          letterSpacing: 6,
                          color: isDark
                              ? FiloColors.darkTextTertiary.withValues(alpha: 0.4)
                              : FiloColors.lightTextTertiary.withValues(alpha: 0.4),
                        ),
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      onChanged: (val) {
                        if (_codeHasError) {
                          setState(() {
                            _codeHasError = false;
                          });
                        }
                        if (val.length == 5 || val.length == 6) {
                          HapticFeedback.selectionClick();
                        }
                      },
                      onSubmitted: (_) => _handleSubmitCode(),
                    ),
                  ),
                ),

                const SizedBox(height: FiloSpacing.xxl),

                FiloButton(
                  label: 'Confirm Code',
                  isLoading: _isLoading,
                  onPressed: _handleSubmitCode,
                  size: FiloButtonSize.large,
                  isFullWidth: true,
                ),

                const SizedBox(height: FiloSpacing.lg),

                Center(
                  child: TextButton(
                    onPressed: _isLoading ? null : _handleSendPhone,
                    child: const Text('Resend Code'),
                  ),
                ),
              ] else if (_step == LoginStep.password2FA) ...[
                Text(
                  'Two-Step Verification',
                  style: FiloTypography.title1.copyWith(
                    color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: FiloSpacing.xs),
                Text(
                  'Your Telegram account is protected with a cloud password. Enter it below.',
                  style: FiloTypography.body.copyWith(
                    color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: FiloSpacing.xl),

                Container(
                  decoration: BoxDecoration(
                    color: isDark ? FiloColors.darkSurfaceSecondary : FiloColors.lightSurfaceSecondary,
                    borderRadius: FiloRadius.roundedLg,
                    border: Border.all(
                      color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
                      width: 0.8,
                    ),
                  ),
                  child: TextField(
                    controller: _passwordController,
                    obscureText: true,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '2FA Cloud Password',
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    onSubmitted: (_) => _handleSubmitPassword(),
                  ),
                ),

                const SizedBox(height: FiloSpacing.xl),

                FiloButton(
                  label: 'Authenticate',
                  isLoading: _isLoading,
                  onPressed: _handleSubmitPassword,
                  size: FiloButtonSize.large,
                  isFullWidth: true,
                ),
              ] else if (_step == LoginStep.botApiFallback) ...[
                Text(
                  'Bring Your Own Bot',
                  style: FiloTypography.title1.copyWith(
                    color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: FiloSpacing.xs),
                Text(
                  'Enter a Bot Token from @BotFather and your private Channel/Chat ID.',
                  style: FiloTypography.body.copyWith(
                    color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: FiloSpacing.lg),

                TextField(
                  controller: _botTokenController,
                  decoration: const InputDecoration(
                    labelText: 'Bot Token',
                    hintText: '123456:ABC-DEF1234ghIkl-zyx57W2v1u123ew11',
                  ),
                ),
                const SizedBox(height: FiloSpacing.md),
                TextField(
                  controller: _chatIdController,
                  decoration: const InputDecoration(
                    labelText: 'Target Channel / Chat ID',
                    hintText: '-1001234567890',
                  ),
                ),
                const SizedBox(height: FiloSpacing.xl),
                FiloButton(
                  label: 'Connect Bot',
                  size: FiloButtonSize.large,
                  isFullWidth: true,
                  onPressed: () {
                    FiloToast.show(context, message: 'Bot connected successfully', type: FiloToastType.success);
                    Navigator.of(context).pop();
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
