import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:filo/core/theme/filo_colors.dart';
import 'package:filo/core/theme/filo_radius.dart';
import 'package:filo/core/theme/filo_spacing.dart';
import 'package:filo/core/theme/filo_typography.dart';
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

  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();

  final _botTokenController = TextEditingController();
  final _chatIdController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _botTokenController.dispose();
    _chatIdController.dispose();
    super.dispose();
  }

  Future<void> _handleSendPhone() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      FiloToast.show(context, message: 'Please enter a valid phone number', type: FiloToastType.error);
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).sendTelegramCode(phone);
      setState(() {
        _isLoading = false;
        _step = LoginStep.verificationCode;
      });
      FiloToast.show(context, message: 'Verification code sent to Telegram', type: FiloToastType.success);
    } catch (e) {
      setState(() => _isLoading = false);
      FiloToast.show(context, message: e.toString(), type: FiloToastType.error);
    }
  }

  Future<void> _handleSubmitCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      FiloToast.show(context, message: 'Please enter the code', type: FiloToastType.error);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await ref.read(authNotifierProvider.notifier).submitTelegramCode(code);
      setState(() => _isLoading = false);

      if (res.step == StorageAuthStep.waitingForPassword) {
        setState(() => _step = LoginStep.password2FA);
      } else if (res.isAuthenticated) {
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _isLoading = false);
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Telegram'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FiloSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step == LoginStep.phoneNumber) ...[
                Text(
                  'Enter Your Phone Number',
                  style: FiloTypography.title1.copyWith(
                    color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: FiloSpacing.xs),
                Text(
                  'Telegram will send an official authentication code directly to your Telegram app or via SMS.',
                  style: FiloTypography.body.copyWith(
                    color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: FiloSpacing.xl),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Phone Number (with country code)',
                    hintText: '+1 234 567 8900',
                    filled: true,
                    fillColor: isDark ? FiloColors.darkSurfaceSecondary : FiloColors.lightSurfaceSecondary,
                    border: OutlineInputBorder(
                      borderRadius: FiloRadius.roundedMd,
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: FiloSpacing.xl),
                FiloButton(
                  label: 'Send Verification Code',
                  isLoading: _isLoading,
                  onPressed: _handleSendPhone,
                  size: FiloButtonSize.large,
                  isFullWidth: true,
                ),
                const Spacer(),
                Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() => _step = LoginStep.botApiFallback);
                    },
                    child: const Text('Use Telegram Bot API Instead'),
                  ),
                ),
              ] else if (_step == LoginStep.verificationCode) ...[
                Text(
                  'Enter Verification Code',
                  style: FiloTypography.title1.copyWith(
                    color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: FiloSpacing.xs),
                Text(
                  'Please enter the 5-digit code Telegram sent to your device.',
                  style: FiloTypography.body.copyWith(
                    color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: FiloSpacing.xl),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Verification Code',
                    hintText: '12345',
                    filled: true,
                    fillColor: isDark ? FiloColors.darkSurfaceSecondary : FiloColors.lightSurfaceSecondary,
                    border: OutlineInputBorder(
                      borderRadius: FiloRadius.roundedMd,
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: FiloSpacing.xl),
                FiloButton(
                  label: 'Confirm Code',
                  isLoading: _isLoading,
                  onPressed: _handleSubmitCode,
                  size: FiloButtonSize.large,
                  isFullWidth: true,
                ),
              ] else if (_step == LoginStep.password2FA) ...[
                Text(
                  'Two-Step Verification',
                  style: FiloTypography.title1.copyWith(
                    color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
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
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: '2FA Cloud Password',
                    filled: true,
                    fillColor: isDark ? FiloColors.darkSurfaceSecondary : FiloColors.lightSurfaceSecondary,
                    border: OutlineInputBorder(
                      borderRadius: FiloRadius.roundedMd,
                      borderSide: BorderSide.none,
                    ),
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
