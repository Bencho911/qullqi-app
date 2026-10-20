import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:inti/core/api/api_client.dart';
import 'package:inti/core/api/token_store.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/accounts/data/api_accounts_repository.dart';
import 'package:inti/features/accounts/domain/account.dart';
import 'package:inti/features/auth/data/api_auth_repository.dart';
import 'package:inti/features/auth/data/auth_repository.dart';
import 'package:inti/features/transactions/data/api_transactions_repository.dart';
import 'package:inti/features/transactions/domain/transaction.dart';

/// Backend falso: responde según método y ruta, y anota cada llamada.
class FakeBackend {
  final calls = <http.Request>[];
  final routes = <String, http.Response Function(http.Request)>{};

  void on(String method, String path, Object? body, {int status = 200}) =>
      routes['$method $path'] = (_) => http.Response(
        body == null ? '' : jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  MockClient get client => MockClient((req) async {
    calls.add(req);
    final handler = routes['${req.method} ${req.url.path}'];
    return handler?.call(req) ?? http.Response('{"message":"no"}', 404);
  });

  Map<String, Object?> bodyOf(String method, String path) => (jsonDecode(
    calls.lastWhere((c) => c.method == method && c.url.path == path).body,
  ) as Map).cast<String, Object?>();
}

Map<String, Object?> session({String access = 'a1', String refresh = 'r1'}) => {
  'accessToken': access,
  'refreshToken': refresh,
  'user': {
    'id': 'u1',
    'fullName': 'Ana Rojas',
    'email': 'ana@correo.co',
    'phone': '3105550142',
    'hasBusiness': true,
    'plan': 'free',
  },
};

Map<String, Object?> accountJson({
  String id = 'acc-1',
  int balance = 850000,
  String kind = 'wallet',
}) => {
  'id': id,
  'institution': 'Nequi',
  'institutionId': 'nequi',
  'kind': kind,
  'last4': '',
  'ownership': 'personal',
  'balance': balance,
  'status': 'manual',
  'lastSync': '2026-10-20T15:00:00.000Z',
  'nickname': null,
  'creditLimit': null,
  'statementBalance': null,
  'minimumPayment': null,
  'paymentDue': null,
  'interestRate': null,
  'paymentsEnabled': false,
  'currency': 'COP',
  'rate': 1,
};

void main() {
  late FakeBackend backend;
  late MemoryTokenStore tokens;
  late ApiClient api;

  setUp(() {
    backend = FakeBackend();
    tokens = MemoryTokenStore();
    api = ApiClient(
      baseUrl: Uri.parse('http://api.test'),
      tokens: tokens,
      client: backend.client,
    );
  });

  group('ApiClient', () {
    test('renueva el token una sola vez y repite la llamada', () async {
      tokens.tokens = const ApiTokens(access: 'viejo', refresh: 'r0');
      var refreshes = 0;
      backend.routes['GET /v1/accounts'] = (req) =>
          req.headers['authorization'] == 'Bearer nuevo'
          ? http.Response('[]', 200)
          : http.Response('{"message":"Unauthorized"}', 401);
      backend.routes['POST /v1/auth/refresh'] = (req) {
        refreshes++;
        return http.Response(jsonEncode(session(access: 'nuevo')), 200);
      };

      // Dos llamadas a la vez comparten la renovación.
      final results = await Future.wait([
        api.get('/v1/accounts'),
        api.get('/v1/accounts'),
      ]);
      expect(results, [<Object?>[], <Object?>[]]);
      expect(refreshes, 1);
      expect(tokens.tokens?.refresh, 'r1');
    });

    test('si la renovación falla, borra los tokens', () async {
      tokens.tokens = const ApiTokens(access: 'a', refresh: 'r');
      backend
        ..on('GET', '/v1/accounts', {'message': 'Unauthorized'}, status: 401)
        ..on('POST', '/v1/auth/refresh', {'message': 'x'}, status: 401);
      await expectLater(
        api.get('/v1/accounts'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
      expect(tokens.tokens, isNull);
    });

    test('usa el primer mensaje de validación del backend', () async {
      backend.on('POST', '/v1/accounts', {
        'message': ['El celular debe tener 10 dígitos.'],
      }, status: 400);
      await expectLater(
        api.post('/v1/accounts', <String, Object?>{}),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            'El celular debe tener 10 dígitos.',
          ),
        ),
      );
    });
  });

  group('ApiAuthRepository', () {
    test('registro en tres pasos guarda la sesión', () async {
      backend
        ..on('POST', '/v1/auth/sign-up', {'signUpId': 's1'}, status: 201)
        ..on('POST', '/v1/auth/sign-up/s1/code', null, status: 204)
        ..on('POST', '/v1/auth/sign-up/s1/verify', session(), status: 201);
      final repo = ApiAuthRepository(api);

      await repo.startSignUp(
        fullName: ' Ana Rojas ',
        email: 'ana@correo.co',
        password: 'clave-segura-1',
        hasBusiness: true,
      );
      await repo.sendCode('310 555 0142');
      final user = await repo.verifyCode('123456');

      expect(backend.bodyOf('POST', '/v1/auth/sign-up/s1/code'), {
        'phone': '3105550142',
      });
      expect(user.fullName, 'Ana Rojas');
      expect(user.phone, '+57 310 555 0142');
      expect(user.hasBusiness, isTrue);
      expect(tokens.tokens?.access, 'a1');
    });

    test('los errores llegan como AuthFailure con el texto del backend', () {
      backend.on('POST', '/v1/auth/sign-in', {
        'message': 'Correo o contraseña incorrectos.',
      }, status: 401);
      expect(
        ApiAuthRepository(api).signIn(email: 'a@b.co', password: 'x'),
        throwsA(
          isA<AuthFailure>().having(
            (e) => e.message,
            'message',
            'Correo o contraseña incorrectos.',
          ),
        ),
      );
    });
  });

  group('ApiAccountsRepository', () {
    test(
      'lee las cuentas y vuelve a leer al registrar un movimiento',
      () async {
        var balance = 850000;
        backend.routes['GET /v1/accounts'] = (_) =>
            http.Response(jsonEncode([accountJson(balance: balance)]), 200);
        final repo = ApiAccountsRepository(api);
        final seen = <List<Account>>[];
        final sub = repo.watch().listen(seen.add);
        await pumpEventQueue();

        balance = 800000;
        await repo.applyDelta('acc-1', -50000);
        await pumpEventQueue();
        await sub.cancel();

        expect(seen.map((l) => l.single.balance), [850000, 800000]);
        expect(seen.first.single.kind, AccountKind.wallet);
        expect(seen.first.single.badge, 'NQ');
        expect(seen.first.single.status, ConnectionStatus.manual);
      },
    );

    test('al agregar a mano no manda los últimos 4 vacíos', () async {
      backend
        ..on('POST', '/v1/accounts', accountJson(kind: 'cash'), status: 201)
        ..on('GET', '/v1/accounts', [accountJson(kind: 'cash')]);
      final account = await ApiAccountsRepository(api).addManual(
        name: 'Efectivo',
        kind: AccountKind.cash,
        balance: 100000,
        ownership: Ownership.personal,
      );
      expect(account.kind, AccountKind.cash);
      expect(backend.bodyOf('POST', '/v1/accounts'), {
        'name': 'Efectivo',
        'kind': 'cash',
        'balance': 100000,
        'ownership': 'personal',
        'currency': 'COP',
      });
    });
  });

  group('ApiTransactionsRepository', () {
    test('deshacer con el id local borra el del servidor', () async {
      backend
        ..on('POST', '/v1/transactions', {'id': 'srv-9'}, status: 201)
        ..on('GET', '/v1/transactions', <Object?>[])
        ..on('DELETE', '/v1/transactions/srv-9', null, status: 204);
      final repo = ApiTransactionsRepository(api);
      await repo.add(
        Transaction(
          id: 'm-local-1',
          title: 'Éxito',
          amount: 50000,
          kind: TransactionKind.expense,
          accountId: 'acc-1',
          categoryId: 'mercado',
          ownership: Ownership.personal,
          date: DateTime.utc(2026, 10, 20, 15),
          source: TransactionSource.manual,
        ),
      );
      await repo.delete('m-local-1');

      expect(backend.bodyOf('POST', '/v1/transactions'), {
        'accountId': 'acc-1',
        'title': 'Éxito',
        'amount': 50000,
        'kind': 'expense',
        'categoryId': 'mercado',
        'ownership': 'personal',
        'date': '2026-10-20T15:00:00.000Z',
        'source': 'manual',
        'needsReview': false,
      });
      expect(
        backend.calls.where((c) => c.method == 'DELETE').single.url.path,
        '/v1/transactions/srv-9',
      );
    });

    test('convierte la respuesta del servidor', () {
      final t = transactionFromJson({
        'id': 't1',
        'title': 'Netflix',
        'amount': 45000,
        'kind': 'expense',
        'accountId': 'card-1',
        'counterAccountId': null,
        'categoryId': 'suscripciones',
        'ownership': 'personal',
        'date': '2026-10-20T15:00:00.000Z',
        'needsReview': false,
        'note': null,
        'source': 'imported',
      });
      expect(t.signedAmount, -45000);
      expect(t.source, TransactionSource.imported);
      expect(t.canDelete, isTrue);
    });
  });
}
