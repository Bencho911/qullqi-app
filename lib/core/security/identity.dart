import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Comprueba que quien usa el teléfono es la persona dueña de la cuenta:
/// biometría del sistema (huella, Face ID) y un PIN de 6 dígitos de Inti.
abstract interface class IdentityVerifier {
  /// Si el teléfono tiene huella o Face ID configurados.
  Future<bool> hasBiometrics();

  /// Pide la huella o el rostro. `true` si se reconoció.
  Future<bool> verifyBiometrics(String reason);

  /// Si ya hay un PIN creado en este teléfono.
  Future<bool> hasPin();

  /// Guarda el PIN (reemplaza el anterior).
  Future<void> setPin(String pin);

  /// Revisa el PIN de 6 dígitos de Inti.
  Future<bool> checkPin(String pin);

  /// Borra el PIN (al cerrar sesión).
  Future<void> clearPin();
}

/// Intentos de PIN antes de bloquear un rato.
const int maxPinAttempts = 3;

/// Largo del PIN.
const int pinLength = 6;

/// Implementación del teléfono. Las pruebas la reemplazan por
/// [MockIdentityVerifier].
final identityVerifierProvider = Provider<IdentityVerifier>(
  (ref) => DeviceIdentityVerifier(),
);

/// Biometría real (`local_auth`) y PIN guardado cifrado
/// (`flutter_secure_storage`). El PIN nunca se guarda en claro: solo su
/// huella SHA-256 con sal.
class DeviceIdentityVerifier implements IdentityVerifier {
  DeviceIdentityVerifier({
    LocalAuthentication? auth,
    FlutterSecureStorage? storage,
  }) : _auth = auth ?? LocalAuthentication(),
       _storage = storage ?? const FlutterSecureStorage();

  final LocalAuthentication _auth;
  final FlutterSecureStorage _storage;

  static const _hashKey = 'pin_hash';
  static const _saltKey = 'pin_salt';

  @override
  Future<bool> hasBiometrics() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> verifyBiometrics(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
      );
    } on Exception {
      // Cancelado, bloqueado por intentos o sin biometría: se usa el PIN.
      return false;
    }
  }

  @override
  Future<bool> hasPin() async => await _storage.read(key: _hashKey) != null;

  @override
  Future<void> setPin(String pin) async {
    final salt = base64Encode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    await _storage.write(key: _saltKey, value: salt);
    await _storage.write(key: _hashKey, value: _hash(pin, salt));
  }

  @override
  Future<bool> checkPin(String pin) async {
    final salt = await _storage.read(key: _saltKey);
    final hash = await _storage.read(key: _hashKey);
    if (salt == null || hash == null) return false;
    return _hash(pin, salt) == hash;
  }

  @override
  Future<void> clearPin() async {
    await _storage.delete(key: _hashKey);
    await _storage.delete(key: _saltKey);
  }

  static String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();
}

/// Simulación para pruebas y demostraciones: la biometría siempre reconoce
/// y el PIN de prueba es 123456 (hasta que se cree otro).
class MockIdentityVerifier implements IdentityVerifier {
  MockIdentityVerifier({required this.latency, this.withPin = true});

  final Duration latency;
  final bool withPin;

  static const demoPin = '123456';

  late String? _pin = withPin ? demoPin : null;

  @override
  Future<bool> hasBiometrics() async => true;

  @override
  Future<bool> verifyBiometrics(String reason) async {
    await Future<void>.delayed(latency);
    return true;
  }

  @override
  Future<bool> hasPin() async => _pin != null;

  @override
  Future<void> setPin(String pin) async => _pin = pin;

  @override
  Future<bool> checkPin(String pin) async {
    await Future<void>.delayed(latency ~/ 2);
    return pin == _pin;
  }

  @override
  Future<void> clearPin() async => _pin = null;
}
