import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/core/storage/prefs.dart';

/// Vista activa (Todo / Personal / Negocio). Se recuerda entre aperturas.
/// Sin negocio, la vista es siempre Personal.
final scopeProvider = NotifierProvider<ScopeNotifier, Scope>(ScopeNotifier.new);

class ScopeNotifier extends Notifier<Scope> {
  static const _key = 'scope';

  @override
  Scope build() {
    if (!ref.watch(currentUserProvider).hasBusiness) return Scope.personal;
    final saved = ref.read(sharedPreferencesProvider).getString(_key);
    return Scope.values.firstWhere(
      (s) => s.name == saved,
      orElse: () => Scope.all,
    );
  }

  Future<void> select(Scope scope) async {
    if (!ref.read(currentUserProvider).hasBusiness) return;
    state = scope;
    await ref.read(sharedPreferencesProvider).setString(_key, scope.name);
  }
}
