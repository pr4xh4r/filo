import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/filo_colors.dart';
import '../../../../core/theme/filo_radius.dart';
import '../../../../core/theme/filo_typography.dart';

/// Apple iOS-style discrete digit verification code input.
///
/// Features:
/// - 5 individual rounded squircle boxes with specular borders & focus glow.
/// - Fluid spring scale pop animation per digit.
/// - Invisible native TextField overlay for full OS auto-fill, SMS paste, and keyboard support.
/// - Auto-submits on completion.
class IosVerificationCodeInput extends StatefulWidget {
  final int length;
  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;
  final ValueChanged<String>? onChanged;
  final bool hasError;

  const IosVerificationCodeInput({
    super.key,
    this.length = 5,
    required this.controller,
    this.onCompleted,
    this.onChanged,
    this.hasError = false,
  });

  @override
  State<IosVerificationCodeInput> createState() => _IosVerificationCodeInputState();
}

class _IosVerificationCodeInputState extends State<IosVerificationCodeInput> {
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCodeChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    final text = widget.controller.text;
    widget.onChanged?.call(text);
    if (text.length == widget.length) {
      widget.onCompleted?.call(text);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final code = widget.controller.text;
    final isSix = widget.length >= 6;
    final boxWidth = isSix ? 46.0 : 52.0;
    final boxHeight = isSix ? 56.0 : 62.0;
    final fontSize = isSix ? 22.0 : 26.0;
    final radius = isSix ? BorderRadius.circular(14) : FiloRadius.roundedLg;

    return Stack(
      alignment: Alignment.center,
      children: [
        // 1. Invisible real text field handling system keyboard, paste, and auto-fill
        Opacity(
          opacity: 0.0,
          child: SizedBox(
            height: boxHeight,
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(widget.length),
              ],
            ),
          ),
        ),

        // 2. Visible Apple-style Discrete Digit Squircle Boxes
        GestureDetector(
          onTap: () {
            _focusNode.requestFocus();
          },
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(widget.length, (index) {
              final isEntered = index < code.length;
              final isCurrent = index == code.length;
              final char = isEntered ? code[index] : '';

              final borderColor = widget.hasError
                  ? FiloColors.destructive
                  : (isCurrent && _focusNode.hasFocus)
                      ? FiloColors.primary
                      : isEntered
                          ? FiloColors.primary.withValues(alpha: 0.5)
                          : (isDark ? FiloColors.darkBorder : FiloColors.lightBorder);

              final fillColor = isDark
                  ? (isCurrent
                      ? FiloColors.darkSurfaceSecondary
                      : FiloColors.darkSurface)
                  : (isCurrent
                      ? FiloColors.lightSurfaceSecondary
                      : FiloColors.lightSurface);

              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: boxWidth,
                height: boxHeight,
                decoration: BoxDecoration(
                  color: fillColor,
                  borderRadius: radius,
                  border: Border.all(
                    color: borderColor,
                    width: (isCurrent && _focusNode.hasFocus) || widget.hasError ? 1.8 : 1.0,
                  ),
                  boxShadow: (isCurrent && _focusNode.hasFocus)
                      ? [
                          BoxShadow(
                            color: FiloColors.primary.withValues(alpha: 0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(
                        scale: animation,
                        child: child,
                      );
                    },
                    child: isEntered
                        ? Text(
                            char,
                            key: ValueKey('char_$index$char'),
                            style: FiloTypography.title1.copyWith(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w700,
                              color: isDark
                                  ? FiloColors.darkTextPrimary
                                  : FiloColors.lightTextPrimary,
                            ),
                          )
                        : (isCurrent && _focusNode.hasFocus)
                            ? _BlinkingCursor(isDark: isDark)
                            : const SizedBox.shrink(),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _BlinkingCursor extends StatefulWidget {
  final bool isDark;

  const _BlinkingCursor({required this.isDark});

  @override
  State<_BlinkingCursor> createState() => _BlinkingCursorState();
}

class _BlinkingCursorState extends State<_BlinkingCursor>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 2.2,
        height: 24,
        decoration: BoxDecoration(
          color: FiloColors.primary,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
