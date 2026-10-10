import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/storage/prefs.dart';
import 'package:qullqi/features/notifications/domain/notice.dart';

export 'package:qullqi/features/notifications/domain/notice.dart'
    show NoticeKind;

/// Avisos encendidos. Por defecto todos; se recuerda en el teléfono.
/// Los avisos de seguridad no se pueden apagar.
final noticePrefsProvider =
    NotifierProvider<NoticePrefsNotifier, Set<NoticeKind>>(
      NoticePrefsNotifier.new,
    );

class NoticePrefsNotifier extends Notifier<Set<NoticeKind>> {
  static const _key = 'notices_off';

  @override
  Set<NoticeKind> build() {
    final off =
        ref.read(sharedPreferencesProvider).getStringList(_key) ?? const [];
    return NoticeKind.values.where((k) => !off.contains(k.name)).toSet();
  }

  Future<void> toggle(NoticeKind kind, {required bool on}) async {
    state = on ? {...state, kind} : ({...state}..remove(kind));
    await ref.read(sharedPreferencesProvider).setStringList(_key, [
      for (final k in NoticeKind.values)
        if (!state.contains(k)) k.name,
    ]);
  }
}
