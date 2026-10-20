import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inti/core/api/api_client.dart';
import 'package:inti/core/storage/prefs.dart';

/// Persona con sesión iniciada.
@immutable
class AppUser {
  const AppUser({
    required this.fullName,
    required this.email,
    required this.phone,
    required this.hasBusiness,
  });

  factory AppUser.fromJson(Map<String, Object?> j) => AppUser(
    fullName: j['fullName']! as String,
    email: j['email']! as String,
    phone: j['phone']! as String,
    hasBusiness: j['hasBusiness']! as bool,
  );

  final String fullName;
  final String email;
  final String phone;

  /// Si es independiente o tiene negocio. Sin negocio la app es solo
  /// personal y no muestra el selector de vista.
  final bool hasBusiness;

  String get firstName => fullName.split(' ').first;

  String get initials => fullName
      .split(' ')
      .where((p) => p.isNotEmpty)
      .take(2)
      .map((p) => p[0].toUpperCase())
      .join();

  AppUser copyWith({String? fullName, String? phone, bool? hasBusiness}) =>
      AppUser(
        fullName: fullName ?? this.fullName,
        email: email,
        phone: phone ?? this.phone,
        hasBusiness: hasBusiness ?? this.hasBusiness,
      );

  Map<String, Object?> toJson() => {
    'fullName': fullName,
    'email': email,
    'phone': phone,
    'hasBusiness': hasBusiness,
  };
}

enum SessionStatus {
  /// Sin sesión: bienvenida, registro o ingreso.
  signedOut,

  /// Con sesión, pero hay que desbloquear con huella o PIN.
  locked,

  /// Dentro de la app.
  unlocked,
}

@immutable
class SessionState {
  const SessionState(this.status, [this.user]);

  final SessionStatus status;
  final AppUser? user;
}

/// Si al abrir la app con sesión se pide desbloquear. Las pruebas lo
/// apagan para empezar dentro de la app.
final lockOnStartProvider = Provider<bool>((ref) => true);

/// Sesión de la persona. Se recuerda en el teléfono; el token real del
/// backend irá en el almacenamiento cifrado.
final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);

class SessionNotifier extends Notifier<SessionState> {
  static const _key = 'session_user';

  @override
  SessionState build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    if (raw == null) return const SessionState(SessionStatus.signedOut);
    try {
      final user = AppUser.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
      return SessionState(
        ref.read(lockOnStartProvider)
            ? SessionStatus.locked
            : SessionStatus.unlocked,
        user,
      );
    } on Object {
      return const SessionState(SessionStatus.signedOut);
    }
  }

  /// Entra a la app (después de crear el PIN o de desbloquear).
  Future<void> open(AppUser user) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(_key, jsonEncode(user.toJson()));
    state = SessionState(SessionStatus.unlocked, user);
  }

  /// Guarda cambios de la persona (nombre, celular, negocio).
  Future<void> update(AppUser user) async {
    if (state.user == null) return;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_key, jsonEncode(user.toJson()));
    state = SessionState(state.status, user);
  }

  /// Bloquea (al volver de segundo plano).
  void lock() {
    if (state.status == SessionStatus.unlocked) {
      state = SessionState(SessionStatus.locked, state.user);
    }
  }

  void unlock() {
    if (state.user != null) {
      state = SessionState(SessionStatus.unlocked, state.user);
    }
  }

  Future<void> signOut() async {
    await ref.read(apiClientProvider)?.closeSession();
    await ref.read(sharedPreferencesProvider).remove(_key);
    state = const SessionState(SessionStatus.signedOut);
  }
}

/// Persona con sesión. Fuera de la sesión no se usa (el router lo impide).
final currentUserProvider = Provider<AppUser>(
  (ref) =>
      ref.watch(sessionProvider).user ??
      const AppUser(
        fullName: 'Invitado',
        email: '',
        phone: '',
        hasBusiness: false,
      ),
);
