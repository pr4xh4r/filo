import 'package:flutter/material.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_button.dart';
import 'telegram_login_screen.dart';

/// Welcomes users with an uncompromising zero-knowledge privacy commitment.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: FiloSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 1),

              // App Icon / Logo Shield
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: FiloColors.primary.withValues(alpha: 0.1),
                    borderRadius: FiloRadius.roundedXl,
                    border: Border.all(
                      color: FiloColors.primary.withValues(alpha: 0.25),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.shield_outlined,
                    color: FiloColors.primary,
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(height: FiloSpacing.xl),

              // Title & Subtitle
              Text(
                'Your Telegram.\nYour Private Cloud.',
                textAlign: TextAlign.center,
                style: FiloTypography.largeTitle.copyWith(
                  color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: FiloSpacing.md),
              Text(
                '${AppConfig.appName} transforms your Telegram account into an encrypted personal cloud drive. Zero servers, zero telemetry.',
                textAlign: TextAlign.center,
                style: FiloTypography.body.copyWith(
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: FiloSpacing.xxl),

              // Pillars of Trust
              _buildFeatureRow(
                icon: Icons.lock_person_rounded,
                title: 'Zero-Knowledge by Default',
                description: 'Files are encrypted on your phone before uploading. Even Telegram cannot read your data.',
                isDark: isDark,
              ),
              const SizedBox(height: FiloSpacing.lg),
              _buildFeatureRow(
                icon: Icons.cloud_off_rounded,
                title: 'No Developer Servers',
                description: 'We run no servers and store zero credentials. You maintain 100% data ownership.',
                isDark: isDark,
              ),
              const SizedBox(height: FiloSpacing.lg),
              _buildFeatureRow(
                icon: Icons.key_rounded,
                title: 'Argon2id & AES-256-GCM',
                description: 'State-of-the-art authenticated cryptography protects every chunk.',
                isDark: isDark,
              ),

              const Spacer(flex: 2),

              // Call to Action Button
              FiloButton(
                label: 'Connect with Telegram',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const TelegramLoginScreen(),
                    ),
                  );
                },
                size: FiloButtonSize.large,
                isFullWidth: true,
              ),
              const SizedBox(height: FiloSpacing.md),

              // Legal / Independence Disclaimer
              Text(
                'Not affiliated with or endorsed by Telegram FZ-LLC.',
                textAlign: TextAlign.center,
                style: FiloTypography.caption.copyWith(
                  color: isDark ? FiloColors.darkTextTertiary : FiloColors.lightTextTertiary,
                ),
              ),
              const SizedBox(height: FiloSpacing.md),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureRow({
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(FiloSpacing.sm),
          decoration: BoxDecoration(
            color: isDark ? FiloColors.darkSurfaceSecondary : FiloColors.lightSurfaceSecondary,
            borderRadius: FiloRadius.roundedMd,
          ),
          child: Icon(icon, color: FiloColors.primary, size: 22),
        ),
        const SizedBox(width: FiloSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
