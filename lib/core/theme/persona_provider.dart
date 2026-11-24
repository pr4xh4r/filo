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
