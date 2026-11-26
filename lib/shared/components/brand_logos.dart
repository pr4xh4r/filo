import 'package:flutter/material.dart';

/// Official Telegram brand logo rendered using the authentic circular app icon asset.
class TelegramBrandLogo extends StatelessWidget {
  final double size;

  const TelegramBrandLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Image.asset(
        'assets/icon/tg.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
