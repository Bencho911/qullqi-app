import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/storage/prefs.dart';

/// Si la persona quiere entrar con huella o Face ID. Se recuerda.
final biometricsEnabledProvider =
    NotifierProvider<BiometricsEnabledNotifier, bool>(
      BiometricsEnabledNotifier.new,
    );

class BiometricsEnabledNotifier extends Notifier<bool> {
  static const _key = 'biometrics_enabled';

  @override
  bool build() => ref.read(sharedPreferencesProvider).getBool(_key) ?? false;

  Future<void> set({required bool enabled}) async {
    state = enabled;
    await ref.read(sharedPreferencesProvider).setBool(_key, enabled);
  }
}
