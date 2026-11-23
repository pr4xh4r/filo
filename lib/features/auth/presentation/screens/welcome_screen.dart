import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../shared/components/diamond_pattern_painter.dart';
import '../../../../shared/components/filo_logo_badge.dart';
import '../../../../shared/components/handwriting_text.dart';
import 'telegram_login_screen.dart';

/// Flagship First-Run Welcome Screen.
///
/// Designed to match Screen 1 of the reference design:
/// - Top 52%: Radiant sunset/violet gradient with diamond geometric lattice overlay
/// - Animated cursive handwriting welcome: "welcome to filo."
/// - Bottom 48%: High-contrast typography ("your unlimited cloud. built around you.")
/// - Bottom action row: "get started" + circular dark button with arrow `→`
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
      backgroundColor: isDark ? FiloColors.darkBackground : FiloColors.lightBackground,
      body: SafeArea(
        top: false,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Column(
              children: [
                // TOP 52%: Radiant Hero Gradient with Diamond Pattern & Handwriting
                Expanded(
                  flex: 52,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? FiloColors.heroGradientDark
                            : FiloColors.heroGradient,
                      ),
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(36),
                        bottomRight: Radius.circular(36),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isDark ? Colors.black : FiloColors.primary)
                              .withValues(alpha: isDark ? 0.4 : 0.25),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: DiamondPatternOverlay(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(36),
                        bottomRight: Radius.circular(36),
                      ),
                      opacity: isDark ? 0.12 : 0.18,
                      spacing: 24.0,
                      diamondSize: 9.0,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: FiloSpacing.xl,
                            vertical: FiloSpacing.md,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Top Bar: Logo & Private Vault Pill
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const FiloLogoBadge(size: 44, showGlow: true),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(100),
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.35),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.lock_outline_rounded, size: 13, color: Colors.white),
                                        SizedBox(width: 5),
                                        Text(
                                          'private vault',
                                          style: TextStyle(
                                            fontFamily: FiloTypography.fontFamily,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            letterSpacing: 0.3,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),

                              const Spacer(),

                              // Captivating Animated Handwriting Text
                              const HandwritingText(
                                text: 'welcome to filo.',
                                duration: Duration(milliseconds: 1400),
                              ),

                              const SizedBox(height: 6),

                              Text(
                                'your unlimited cloud.',
                                style: FiloTypography.editorial(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.8,
                                  color: Colors.white,
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

                // BOTTOM 48%: High-Contrast Typography & Action Row
                Expanded(
                  flex: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FiloSpacing.xl,
                      vertical: FiloSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: FiloSpacing.sm),

                        // Subtle Category Pill
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.black.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'personal storage',
                                    style: FiloTypography.caption.copyWith(
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3,
                                      color: isDark
                                          ? FiloColors.darkTextPrimary
                                          : FiloColors.lightTextPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.cloud_done_rounded, size: 14, color: FiloColors.success),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: FiloSpacing.sm),

                        Text(
                          'built around you.',
                          style: FiloTypography.title1.copyWith(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            color: FiloColors.lightTextPrimary,
                          ),
                        ),

                        const SizedBox(height: 12),

                        Text(
                          'all your photos, videos, and files stored securely in your telegram. no servers. no bills. just sit back.',
                          style: FiloTypography.body.copyWith(
                            color: FiloColors.lightTextSecondary,
                            height: 1.55,
                            fontSize: 16,
                          ),
                        ),

                        const Spacer(flex: 3),

                        // Bottom Action Row (Screen 1 style: "Get Started" + Dark Circle Button)
                        GestureDetector(
                          onTapDown: (_) => setState(() => _isButtonPressed = true),
                          onTapUp: (_) => setState(() => _isButtonPressed = false),
                          onTapCancel: () => setState(() => _isButtonPressed = false),
                          onTap: _onGetStarted,
                          child: AnimatedScale(
                            scale: _isButtonPressed ? 0.98 : 1.0,
                            duration: const Duration(milliseconds: 140),
                            curve: Curves.easeOutCubic,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: FiloSpacing.lg,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? FiloColors.darkSurfaceSecondary
                                    : FiloColors.lightSurface,
                                borderRadius: BorderRadius.circular(100),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.12)
                                      : Colors.black.withValues(alpha: 0.08),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'get started',
                                    style: FiloTypography.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      color: isDark
                                          ? FiloColors.darkTextPrimary
                                          : FiloColors.lightTextPrimary,
                                    ),
                                  ),
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white : Colors.black,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: (isDark ? Colors.white : Colors.black)
                                              .withValues(alpha: 0.25),
                                          blurRadius: 10,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.arrow_forward_rounded,
                                      color: isDark ? Colors.black : Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: FiloSpacing.sm),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
