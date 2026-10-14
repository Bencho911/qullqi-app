import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inti/core/storage/prefs.dart';

/// Tema elegido por la persona (claro, oscuro o el del teléfono). Se recuerda.
/// Sin elegir, la app abre en claro.
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';

  @override
  ThemeMode build() {
    final saved = ref.read(sharedPreferencesProvider).getString(_key);
    return ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      // Claro de entrada; "Automático" y "Oscuro" se eligen en el perfil.
      orElse: () => ThemeMode.light,
    );
  }

  Future<void> select(ThemeMode mode) async {
    state = mode;
    await ref.read(sharedPreferencesProvider).setString(_key, mode.name);
  }
}
