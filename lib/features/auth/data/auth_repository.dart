import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inti/core/data/latency.dart';
import 'package:inti/core/session/session.dart';

/// Algo salió mal al registrarse o ingresar; el mensaje es para la persona.
class AuthFailure implements Exception {
  const AuthFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Cuentas de Inti en el backend. La app solo depende de esta interfaz.
abstract interface class AuthRepository {
  /// Empieza el registro. Lanza [AuthFailure] si el correo ya existe.
  Future<void> startSignUp({
    required String fullName,
    required String email,
    required String password,
    required bool hasBusiness,
  });

  /// Envía el código por SMS al celular (10 dígitos, empieza por 3).
  Future<void> sendCode(String phone);

  /// Verifica el código y crea la cuenta. Lanza [AuthFailure] si no es.
  Future<AppUser> verifyCode(String code);

  /// Ingresa con correo y contraseña.
  Future<AppUser> signIn({required String email, required String password});

  /// Envía el enlace para crear una contraseña nueva.
  Future<void> sendPasswordReset(String email);
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => MockAuthRepository(latency: ref.watch(mockLatencyProvider)),
);

/// Simulación con reglas de prueba:
/// - El código SMS correcto es 123456.
/// - La contraseña "error1234" falla al ingresar.
/// - El correo "ya@existe.co" ya está registrado.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository({required this.latency});

  final Duration latency;

  static const demoCode = '123456';

  String? _name;
  String? _email;
  bool _business = false;
  String? _phone;

  @override
  Future<void> startSignUp({
    required String fullName,
    required String email,
    required String password,
    required bool hasBusiness,
  }) async {
    await Future<void>.delayed(latency);
    if (email.trim().toLowerCase() == 'ya@existe.co') {
      throw const AuthFailure(
        'Ya hay una cuenta con ese correo. Ingresa o recupera tu contraseña.',
      );
    }
    _name = fullName.trim();
    _email = email.trim();
    _business = hasBusiness;
  }

  @override
  Future<void> sendCode(String phone) async {
    await Future<void>.delayed(latency);
    _phone = phone;
  }

  @override
  Future<AppUser> verifyCode(String code) async {
    await Future<void>.delayed(latency);
    if (code != demoCode) {
      throw const AuthFailure('El código no coincide. Revisa el SMS.');
    }
    return AppUser(
      fullName: _name ?? 'Camilo Restrepo Gómez',
      email: _email ?? 'camilo.restrepo@inti.app',
      phone: '+57 ${_phone ?? '310 555 0142'}',
      hasBusiness: _business,
    );
  }

  @override
  Future<AppUser> signIn({
    required String email,
    required String password,
  }) async {
    await Future<void>.delayed(latency);
    if (password == 'error1234') {
      throw const AuthFailure('El correo o la contraseña no coinciden.');
    }
    return AppUser(
      fullName: 'Camilo Restrepo Gómez',
      email: email.trim(),
      phone: '+57 310 555 0142',
      hasBusiness: true,
    );
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    await Future<void>.delayed(latency);
  }
}
