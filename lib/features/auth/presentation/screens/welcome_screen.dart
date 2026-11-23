import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/filo_glass.dart';
import '../../../../shared/components/filo_logo_badge.dart';
import 'telegram_login_screen.dart';

/// Flagship First-Run Welcome Screen.
///
/// Designed with CRED luxury obsidian typography and iOS 18 liquid glass materials.
/// Plain, human copywriting with zero technical jargon.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  bool _isButtonPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.85, curve: Curves.easeOutCubic),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.1, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onGetStarted() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (context, animation, secondaryAnimation) =>
            const TelegramLoginScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.04, 0.0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: FiloAmbientBackground(
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FiloSpacing.xl,
                  vertical: FiloSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: FiloSpacing.sm),

                    // Top App Logo & Subtle Pill Badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const FiloLogoBadge(size: 48, showGlow: true),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : Colors.black.withValues(alpha: 0.08),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            '✦ private vault',
                            style: FiloTypography.caption.copyWith(
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? FiloColors.accentOrchid
                                  : FiloColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const Spacer(flex: 2),

                    // Editorial Headlines (CRED aesthetic: lowercase elegance)
                    Text(
                      'welcome to filo.',
                      style: FiloTypography.editorial(
                        fontSize: 42,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -1.4,
                        color: isDark
                            ? FiloColors.darkTextPrimary
                            : FiloColors.lightTextPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'your unlimited cloud.',
                      style: FiloTypography.largeTitle.copyWith(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.0,
                        color: isDark
                            ? FiloColors.darkTextSecondary
                            : FiloColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: FiloSpacing.md),
                    Text(
                      'all your photos, videos, and files stored securely in your telegram. no servers. no bills. just sit back.',
                      style: FiloTypography.body.copyWith(
                        fontSize: 16,
                        height: 1.45,
                        color: isDark
                            ? FiloColors.darkTextSecondary.withValues(alpha: 0.8)
                            : FiloColors.lightTextSecondary,
                      ),
                    ),

                    const Spacer(flex: 3),

                    // 3 Liquid Frosted Glass Benefit Highlights (Image 5 aesthetic)
                    _buildFrostedBenefit(
                      icon: Icons.all_inclusive_rounded,
                      title: 'unlimited storage',
                      subtitle: 'powered by your telegram cloud',
                      isDark: isDark,
                    ),
                    const SizedBox(height: FiloSpacing.sm),
                    _buildFrostedBenefit(
                      icon: Icons.shield_outlined,
                      title: 'locked on your device',
                      subtitle: 'only you hold the key to your files',
                      isDark: isDark,
                    ),
                    const SizedBox(height: FiloSpacing.sm),
                    _buildFrostedBenefit(
                      icon: Icons.bolt_rounded,
                      title: 'fast & lightweight',
                      subtitle: 'instant access from all your devices',
                      isDark: isDark,
                    ),

                    const Spacer(flex: 3),

                    // Primary Interactive CTA Button (Emil Kowalski press scale)
                    GestureDetector(
                      onTapDown: (_) {
                        setState(() => _isButtonPressed = true);
                        HapticFeedback.lightImpact();
                      },
                      onTapUp: (_) => setState(() => _isButtonPressed = false),
                      onTapCancel: () =>
                          setState(() => _isButtonPressed = false),
                      onTap: _onGetStarted,
                      child: AnimatedScale(
                        scale: _isButtonPressed ? 0.97 : 1.0,
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOutCubic,
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: FiloColors.brandGradient,
                            ),
                            borderRadius: FiloRadius.roundedXl,
                            boxShadow: [
                              BoxShadow(
                                color: FiloColors.brandIndigo
                                    .withValues(alpha: isDark ? 0.45 : 0.35),
                                blurRadius: 24,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'get started',
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
        ),
      ),
    );
  }

  Widget _buildFrostedBenefit({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return FiloGlass(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: FiloRadius.roundedLg,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  FiloColors.brandOrchid.withValues(alpha: 0.18),
                  FiloColors.brandIndigo.withValues(alpha: 0.18),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: isDark ? FiloColors.accentOrchid : FiloColors.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: FiloTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    color: isDark
                        ? FiloColors.darkTextPrimary
                        : FiloColors.lightTextPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: FiloTypography.caption.copyWith(
                    color: isDark
                        ? FiloColors.darkTextSecondary
                        : FiloColors.lightTextSecondary,
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
