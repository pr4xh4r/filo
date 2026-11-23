import 'package:flutter/material.dart';
import '../../core/theme/filo_colors.dart';
import '../../core/theme/filo_typography.dart';

/// Captivating handwriting text animation.
///
/// Features:
/// - True cursive handwriting typography using bundled 'Caveat'
/// - Progressive character-by-character fluid cursive reveal
/// - Glowing pen cursor dot that glides along the text as it writes
/// - Smooth deceleration and auto-fade out of cursor when complete
class HandwritingText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration duration;
  final VoidCallback? onComplete;

  const HandwritingText({
    super.key,
    required this.text,
    this.style,
    this.duration = const Duration(milliseconds: 1400),
    this.onComplete,
  });

  @override
  State<HandwritingText> createState() => _HandwritingTextState();
}

class _HandwritingTextState extends State<HandwritingText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutCubic,
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final defaultStyle = FiloTypography.handwriting(
      fontSize: 44,
      fontWeight: FontWeight.w600,
      color: Colors.white,
    );

    final effectiveStyle = widget.style ?? defaultStyle;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final totalLength = widget.text.length;
        final currentCount = (_animation.value * totalLength).clamp(0, totalLength).toInt();
        final visibleText = widget.text.substring(0, currentCount);
        final isWriting = _controller.isAnimating && currentCount < totalLength;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              visibleText,
              style: effectiveStyle,
            ),
            if (isWriting)
              Padding(
                padding: const EdgeInsets.only(left: 2.0),
                child: Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    color: effectiveStyle.color ?? FiloColors.accentOrchid,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (effectiveStyle.color ?? FiloColors.accentOrchid).withValues(alpha: 0.6),
                        blurRadius: 6,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
