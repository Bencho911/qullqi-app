import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/storage/prefs.dart';

/// Horarios en que los avisos del teléfono no suenan.
enum QuietHours {
  off('Sin horario', null, null),
  night('10 p. m. a 7 a. m.', 22, 7),
  early('9 p. m. a 8 a. m.', 21, 8);

  QuietHours(this.label, this.fromHour, this.toHour);

  final String label;

  /// Hora (0 a 23) en que empieza el silencio.
  final int? fromHour;

  /// Hora en que termina.
  final int? toHour;

  /// Si a la hora de [t] los avisos van callados.
  bool contains(DateTime t) {
    final from = fromHour;
    final to = toHour;
    if (from == null || to == null) return false;
    final h = t.hour;
    return from > to ? (h >= from || h < to) : (h >= from && h < to);
  }
}

/// Cómo quiere la persona recibir los avisos en el teléfono.
@immutable
class PushPrefs {
  const PushPrefs({this.enabled = false, this.quiet = QuietHours.off});

  final bool enabled;
  final QuietHours quiet;

  /// Si un aviso que llega a las [t] debe sonar.
  bool shouldRing(DateTime t) => enabled && !quiet.contains(t);

  PushPrefs copyWith({bool? enabled, QuietHours? quiet}) =>
      PushPrefs(enabled: enabled ?? this.enabled, quiet: quiet ?? this.quiet);
}

/// Preferencias de los avisos del teléfono. Se recuerdan en el dispositivo;
/// cuando haya backend se envían junto con el token del dispositivo.
final pushPrefsProvider = NotifierProvider<PushPrefsNotifier, PushPrefs>(
  PushPrefsNotifier.new,
);

class PushPrefsNotifier extends Notifier<PushPrefs> {
  static const _enabledKey = 'push_enabled';
  static const _quietKey = 'push_quiet';

  @override
  PushPrefs build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final quiet = QuietHours.values.firstWhere(
      (q) => q.name == prefs.getString(_quietKey),
      orElse: () => QuietHours.off,
    );
    return PushPrefs(
      enabled: prefs.getBool(_enabledKey) ?? false,
      quiet: quiet,
    );
  }

  Future<void> setEnabled({required bool enabled}) async {
    state = state.copyWith(enabled: enabled);
    await ref.read(sharedPreferencesProvider).setBool(_enabledKey, enabled);
  }

  Future<void> setQuiet(QuietHours quiet) async {
    state = state.copyWith(quiet: quiet);
    await ref.read(sharedPreferencesProvider).setString(_quietKey, quiet.name);
  }
}
