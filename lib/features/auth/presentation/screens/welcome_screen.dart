import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_spacing.dart';
import '../../../../core/theme/filo_typography.dart';
import '../../../../core/theme/persona_provider.dart';
import '../../../../shared/components/filo_background.dart';
import '../../../../shared/components/filo_glass.dart';
import '../../../../shared/components/handwriting_text.dart';
import 'telegram_login_screen.dart';

/// Flagship First-Run Welcome Screen (Ethereal Dawn & Editorial Line-Art).
///
/// Features:
/// - Seamless Ethereal Dawn ambient mesh background (apricot, champagne, arctic lavender)
/// - Sculpted frosted-glass hero card showcasing the editorial monoline illustration
/// - Animated cursive handwriting: "welcome to filo"
/// - Human, concise value proposition: "your unlimited cloud storage. all your data saved securely in telegram."
/// - Tactile pill action button with spring haptics
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
      begin: const Offset(0.0, 0.06),
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
    return Scaffold(
      body: FiloBackground(
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
                    const Spacer(flex: 1),

                    // Flagship Editorial Illustration with Ethereal Dawn Ambient Halo
                    const Center(
                      child: FiloIllustrationView(
                        assetName: FiloIllustrations.welcome,
                        maxHeight: 330,
                        maxWidth: 360,
                      ),
                    ),

                    const Spacer(flex: 1),

                    // Captivating Animated Handwriting
                    HandwritingText(
                      text: 'welcome to filo',
                      duration: const Duration(milliseconds: 1400),
                      style: FiloTypography.handwriting(
                        fontSize: 40,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.white
                            : FiloColors.lightTextPrimary,
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Clear, Human Value Proposition
                    Text(
                      'unlimited private storage for all your files,\nphotos, and documents — beautifully organized.',
                      style: FiloTypography.body.copyWith(
                        fontSize: 16,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? FiloColors.darkTextSecondary
                            : FiloColors.lightTextSecondary,
                      ),
                    ),

                    const SizedBox(height: FiloSpacing.xxl),

                    // Bottom Action Row: Coral Peach / Obsidian Pill Button
                    GestureDetector(
                      onTapDown: (_) => setState(() => _isButtonPressed = true),
                      onTapUp: (_) => setState(() => _isButtonPressed = false),
                      onTapCancel: () => setState(() => _isButtonPressed = false),
                      onTap: _onGetStarted,
                      child: AnimatedScale(
                        scale: _isButtonPressed ? 0.97 : 1.0,
                        duration: const Duration(milliseconds: 120),
                        child: Container(
                          width: double.infinity,
                          height: 58,
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
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'get started',
                                style: FiloTypography.callout.copyWith(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: 0.2,
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

                    const SizedBox(height: FiloSpacing.md),
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
