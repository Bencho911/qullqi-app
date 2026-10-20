import 'package:inti/core/api/api_client.dart';
import 'package:inti/core/session/session.dart';
import 'package:inti/features/auth/data/auth_repository.dart';

/// Registro e ingreso contra el backend. Guarda los tokens al terminar.
class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this.api);

  final ApiClient api;
  String? _signUpId;

  @override
  Future<void> startSignUp({
    required String fullName,
    required String email,
    required String password,
    required bool hasBusiness,
  }) => _guard(() async {
    final json = await api.post('/v1/auth/sign-up', {
      'fullName': fullName.trim(),
      'email': email.trim(),
      'password': password,
      'hasBusiness': hasBusiness,
    });
    _signUpId = (json! as Map)['signUpId']! as String;
  });

  @override
  Future<void> sendCode(String phone) => _guard(() async {
    await api.post('/v1/auth/sign-up/${_pending()}/code', {
      'phone': _digits(phone),
    });
  });

  @override
  Future<AppUser> verifyCode(String code) => _guard(() async {
    final json = await api.post('/v1/auth/sign-up/${_pending()}/verify', {
      'code': code,
    });
    _signUpId = null;
    return await _open(json);
  });

  @override
  Future<AppUser> signIn({required String email, required String password}) =>
      _guard(() async {
        final json = await api.post('/v1/auth/sign-in', {
          'email': email.trim(),
          'password': password,
        });
        return await _open(json);
      });

  /// El backend todavía no envía correos.
  @override
  Future<void> sendPasswordReset(String email) async => throw const AuthFailure(
    'Recuperar la contraseña todavía no está disponible.',
  );

  String _pending() {
    final id = _signUpId;
    if (id == null) throw const AuthFailure('Empieza el registro de nuevo.');
    return id;
  }

  Future<AppUser> _open(Object? json) async {
    final session = (json! as Map).cast<String, Object?>();
    await api.openSession(session);
    return appUserFromJson((session['user']! as Map).cast<String, Object?>());
  }

  /// Los errores del backend llegan a la pantalla como [AuthFailure].
  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on ApiException catch (e) {
      throw AuthFailure(e.message);
    }
  }
}

String _digits(String phone) {
  final d = phone.replaceAll(RegExp(r'\D'), '');
  return d.length == 12 && d.startsWith('57') ? d.substring(2) : d;
}

/// "+57 310 555 0142", como lo muestra la app.
String _displayPhone(String digits) => digits.length == 10
    ? '+57 ${digits.substring(0, 3)} ${digits.substring(3, 6)} '
          '${digits.substring(6)}'
    : digits;

AppUser appUserFromJson(Map<String, Object?> j) => AppUser(
  fullName: j['fullName']! as String,
  email: j['email']! as String,
  phone: _displayPhone(j['phone']! as String),
  hasBusiness: j['hasBusiness']! as bool,
);
