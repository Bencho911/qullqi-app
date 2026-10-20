import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import 'package:inti/core/api/api_config.dart';
import 'package:inti/core/api/token_store.dart';

/// El backend respondió con error. [message] viene en palabras de la persona
/// cuando el backend lo da; si no, es genérico.
class ApiException implements Exception {
  const ApiException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => message;
}

/// Llamadas JSON al backend con el token de la sesión. Si el token de
/// acceso venció, lo renueva una vez y repite la llamada.
class ApiClient {
  ApiClient({required this.baseUrl, required this.tokens, http.Client? client})
    : _http = client ?? http.Client();

  final Uri baseUrl;
  final TokenStore tokens;
  final http.Client _http;
  Future<bool>? _refreshing;

  static const _timeout = Duration(seconds: 20);

  Future<Object?> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<Object?> post(String path, [Object? body]) =>
      _send('POST', path, body: body);

  Future<Object?> patch(String path, Object body) =>
      _send('PATCH', path, body: body);

  Future<void> delete(String path) => _send('DELETE', path);

  /// Guarda los tokens que devolvió el registro o el ingreso.
  Future<void> openSession(Map<String, Object?> session) => tokens.write(
    ApiTokens(
      access: session['accessToken']! as String,
      refresh: session['refreshToken']! as String,
    ),
  );

  /// Cierra la sesión en el backend (si se puede) y borra los tokens.
  Future<void> closeSession() async {
    final current = await tokens.read();
    await tokens.clear();
    if (current == null) return;
    try {
      await _raw(
        'POST',
        '/v1/auth/sign-out',
        body: {'refreshToken': current.refresh},
      );
    } on Object {
      // Sin red el token igual vence solo.
    }
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    var res = await _raw(method, path, query: query, body: body, auth: true);
    if (res.statusCode == 401 && await _refresh()) {
      res = await _raw(method, path, query: query, body: body, auth: true);
    }
    return _decode(res);
  }

  Future<http.Response> _raw(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool auth = false,
  }) async {
    final uri = baseUrl.replace(
      path: '${baseUrl.path.replaceAll(RegExp(r'/$'), '')}$path',
      queryParameters: query,
    );
    final request = http.Request(method, uri)
      ..headers['accept'] = 'application/json';
    if (auth) {
      final t = await tokens.read();
      if (t != null) request.headers['authorization'] = 'Bearer ${t.access}';
    }
    if (body != null) {
      request
        ..headers['content-type'] = 'application/json'
        ..body = jsonEncode(body);
    }
    try {
      return await http.Response.fromStream(
        await _http.send(request).timeout(_timeout),
      );
    } on TimeoutException {
      throw const ApiException(0, 'El servidor no respondió a tiempo.');
    } on http.ClientException {
      throw const ApiException(0, 'No hay conexión con el servidor.');
    }
  }

  /// Renueva los tokens. Varias llamadas a la vez comparten una sola
  /// renovación, porque el token de refresco es de un solo uso.
  Future<bool> _refresh() => _refreshing ??= () async {
    try {
      final current = await tokens.read();
      if (current == null) return false;
      final res = await _raw(
        'POST',
        '/v1/auth/refresh',
        body: {'refreshToken': current.refresh},
      );
      if (res.statusCode != 200) {
        await tokens.clear();
        return false;
      }
      await openSession((jsonDecode(res.body) as Map).cast<String, Object?>());
      return true;
    } finally {
      _refreshing = null;
    }
  }();

  Object? _decode(http.Response res) {
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    Object? json;
    if (res.body.isNotEmpty) {
      try {
        json = jsonDecode(utf8.decode(res.bodyBytes));
      } on FormatException {
        json = null;
      }
    }
    if (ok) return json;
    throw ApiException(res.statusCode, _message(json, res.statusCode));
  }

  static String _message(Object? json, int status) {
    if (json is Map) {
      final m = json['message'];
      if (m is String && m.isNotEmpty) return m;
      if (m is List && m.isNotEmpty) return m.first.toString();
    }
    if (status == 401) return 'Tu sesión terminó. Ingresa de nuevo.';
    return 'Algo salió mal. Inténtalo de nuevo.';
  }

  void dispose() => _http.close();
}

/// Cliente del backend, o `null` si la app corre con datos de demostración.
final apiClientProvider = Provider<ApiClient?>((ref) {
  final base = ref.watch(apiBaseUrlProvider);
  if (base == null) return null;
  final client = ApiClient(baseUrl: base, tokens: SecureTokenStore());
  ref.onDispose(client.dispose);
  return client;
});
