import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tokens de la sesión con el backend.
class ApiTokens {
  const ApiTokens({required this.access, required this.refresh});

  final String access;
  final String refresh;
}

/// Dónde se guardan los tokens. En el teléfono, cifrados.
abstract interface class TokenStore {
  Future<ApiTokens?> read();
  Future<void> write(ApiTokens tokens);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _accessKey = 'api_access_token';
  static const _refreshKey = 'api_refresh_token';

  @override
  Future<ApiTokens?> read() async {
    final access = await _storage.read(key: _accessKey);
    final refresh = await _storage.read(key: _refreshKey);
    if (access == null || refresh == null) return null;
    return ApiTokens(access: access, refresh: refresh);
  }

  @override
  Future<void> write(ApiTokens tokens) async {
    await _storage.write(key: _accessKey, value: tokens.access);
    await _storage.write(key: _refreshKey, value: tokens.refresh);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
  }
}

/// Para pruebas.
class MemoryTokenStore implements TokenStore {
  ApiTokens? tokens;

  @override
  Future<ApiTokens?> read() async => tokens;

  @override
  Future<void> write(ApiTokens t) async => tokens = t;

  @override
  Future<void> clear() async => tokens = null;
}
