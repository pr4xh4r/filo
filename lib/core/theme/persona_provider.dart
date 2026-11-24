import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// User persona preferences for character-driven illustrations.
enum FiloPersona {
  female,
  male,
}

class PersonaNotifier extends StateNotifier<FiloPersona> {
  PersonaNotifier() : super(FiloPersona.female);

  void setPersona(FiloPersona persona) {
    state = persona;
  }

  void toggle() {
    state = state == FiloPersona.female ? FiloPersona.male : FiloPersona.female;
  }
}

final personaProvider = StateNotifierProvider<PersonaNotifier, FiloPersona>((ref) {
  return PersonaNotifier();
});

/// Centralized asset helper for Filo illustrations.
class FiloIllustrations {
  FiloIllustrations._();

  static const String welcome = 'assets/illustrations/welcome_ethereal_lineart.png';
  static const String security = 'assets/illustrations/security_ethereal_lineart.png';
  static const String recovery = 'assets/illustrations/recovery_phrase_capsule.png';
  static const String transfer = 'assets/illustrations/transfer_upload_stream.png';
  static const String starred = 'assets/illustrations/starred_favorites_empty.png';

  static String emptyVault(FiloPersona persona) {
    return persona == FiloPersona.male
        ? 'assets/illustrations/empty_vault_male_ethereal_lineart.png'
        : 'assets/illustrations/empty_vault_ethereal_lineart.png';
  }

  static String trash(FiloPersona persona) {
    return persona == FiloPersona.male
        ? 'assets/illustrations/trash_male_ethereal_lineart.png'
        : 'assets/illustrations/trash_clean_slate.png';
  }
}

/// Adaptive illustration widget:
/// - Renders transparent editorial line-art with NO background box/vignette.
/// - In Dark Mode, automatically inverts black lines into luminous celestial silver-white.
/// - In Light Mode, preserves fine midnight ink contours.
class FiloIllustrationView extends StatelessWidget {
  final String assetName;
  final double? maxHeight;
  final double? maxWidth;
  final BoxFit fit;

  const FiloIllustrationView({
    super.key,
    required this.assetName,
    this.maxHeight,
    this.maxWidth,
    this.fit = BoxFit.contain,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget image = Image.asset(
      assetName,
      fit: fit,
    );

    if (isDark) {
      // Invert ink contours for dark mode: black becomes bright luminous silver/white
      image = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          -1, 0, 0, 0, 255,
          0, -1, 0, 0, 255,
          0, 0, -1, 0, 255,
          0, 0, 0, 1, 0,
        ]),
        child: image,
      );
    }

    if (maxHeight != null || maxWidth != null) {
      return Container(
        constraints: BoxConstraints(
          maxHeight: maxHeight ?? double.infinity,
          maxWidth: maxWidth ?? double.infinity,
        ),
        child: image,
      );
    }

    return image;
  }
}
