import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferencias del teléfono. Se carga en `main` antes de arrancar la app y
/// se inyecta con `overrides`, así ningún widget espera un `Future`.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw StateError(
    'sharedPreferencesProvider debe sobrescribirse en ProviderScope.',
  ),
);
