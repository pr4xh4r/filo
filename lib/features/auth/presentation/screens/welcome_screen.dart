import 'package:flutter/material.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_button.dart';
import '../../../../shared/components/filo_logo_badge.dart';
import 'telegram_login_screen.dart';

/// Welcomes users with an uncompromising zero-knowledge privacy commitment.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: FiloSpacing.xl,
            vertical: FiloSpacing.lg,
          ),
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: FiloSpacing.md),

              // Unique Flagship App Logo Badge
              const Center(
                child: FiloLogoBadge(
                  size: 88,
                  showGlow: true,
                ),
              ),
              const SizedBox(height: FiloSpacing.lg),

              // Title & Subtitle with iOS SF Typography
              Text(
                'Your Telegram.\nYour Private Cloud.',
                textAlign: TextAlign.center,
                style: FiloTypography.largeTitle.copyWith(
                  color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                  letterSpacing: -0.8,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: FiloSpacing.sm),
              Text(
                '${AppConfig.appName} transforms your Telegram storage into an encrypted personal vault. Zero servers, zero telemetry.',
                textAlign: TextAlign.center,
                style: FiloTypography.body.copyWith(
                  color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                  letterSpacing: -0.2,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: FiloSpacing.xl),

              // Apple Squircle Pillars of Trust
              _buildFeatureCard(
                icon: Icons.lock_person_rounded,
                title: 'Zero-Knowledge by Default',
                description: 'Files are encrypted on your phone before uploading. Even Telegram cannot read your data.',
                isDark: isDark,
              ),
              const SizedBox(height: FiloSpacing.sm),
              _buildFeatureCard(
                icon: Icons.cloud_off_rounded,
                title: 'No Developer Servers',
                description: 'We run zero servers and store zero keys. You maintain 100% cryptographic sovereignty.',
                isDark: isDark,
              ),
              const SizedBox(height: FiloSpacing.sm),
              _buildFeatureCard(
                icon: Icons.key_rounded,
                title: 'Argon2id & AES-256-GCM',
                description: 'Military-grade authenticated encryption protects every byte and chunk.',
                isDark: isDark,
              ),

              const SizedBox(height: FiloSpacing.xl),

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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String description,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(FiloSpacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? FiloColors.darkSurface.withValues(alpha: 0.7)
            : FiloColors.lightSurface.withValues(alpha: 0.85),
        borderRadius: FiloRadius.roundedXl,
        border: Border.all(
          color: isDark ? FiloColors.darkBorder : FiloColors.lightBorder,
          width: 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: FiloColors.primary.withValues(alpha: 0.12),
              borderRadius: FiloRadius.roundedLg,
            ),
            child: Icon(
              icon,
              color: FiloColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: FiloSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: FiloTypography.title3.copyWith(
                    color: isDark ? FiloColors.darkTextPrimary : FiloColors.lightTextPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: FiloTypography.subheadline.copyWith(
                    color: isDark ? FiloColors.darkTextSecondary : FiloColors.lightTextSecondary,
                    height: 1.3,
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
