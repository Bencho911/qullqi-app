import 'dart:async';

import 'package:inti/core/api/api_client.dart';
import 'package:inti/core/money/currency.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart';
import 'package:inti/features/accounts/domain/account.dart';
import 'package:inti/features/accounts/domain/institution.dart';

/// Cuentas guardadas en el backend. El saldo lo calcula el servidor: cada
/// movimiento ya lo actualiza allá, así que aquí solo se vuelve a leer.
class ApiAccountsRepository implements AccountsRepository {
  ApiAccountsRepository(this.api);

  final ApiClient api;
  final _changes = StreamController<List<Account>>.broadcast();
  List<Account>? _last;

  @override
  Stream<List<Account>> watch() {
    unawaited(_reload().catchError(_changes.addError));
    return _last == null ? _changes.stream : _startWith(_last!);
  }

  Stream<List<Account>> _startWith(List<Account> first) async* {
    yield first;
    yield* _changes.stream;
  }

  Future<void> _reload() async {
    final json = await api.get('/v1/accounts');
    _last = [
      for (final a in (json! as List).cast<Map<String, Object?>>())
        accountFromJson(a),
    ];
    _changes.add(List.unmodifiable(_last!));
  }

  /// Sin conexión bancaria todavía: actualizar es volver a leer.
  @override
  Future<void> sync() => _reload();

  @override
  Future<void> applyDelta(String accountId, int delta) => _reload();

  @override
  Future<Account> connect(
    Institution institution, {
    required bool payments,
  }) async => throw ConnectionFailure(
    'La conexión automática con ${institution.name} llega pronto. '
    'Mientras tanto puedes agregarla a mano.',
  );

  @override
  Future<void> reconnect(String accountId) async =>
      throw const ConnectionFailure('La conexión automática llega pronto.');

  @override
  Future<Account> addManual({
    required String name,
    required AccountKind kind,
    required int balance,
    required Ownership ownership,
    String last4 = '',
    Currency currency = Currency.cop,
  }) async {
    final json = await api.post('/v1/accounts', {
      'name': name.trim(),
      'kind': _kindToJson[kind],
      'balance': balance,
      'ownership': ownership.name,
      if (last4.isNotEmpty) 'last4': last4,
      'currency': currency.code,
    });
    final account = accountFromJson((json! as Map).cast<String, Object?>());
    await _reload();
    return account;
  }

  @override
  Future<void> remove(String accountId) async {
    await api.delete('/v1/accounts/$accountId');
    await _reload();
  }

  @override
  Future<void> setPaymentsEnabled(
    String accountId, {
    required bool enabled,
  }) async => throw const ConnectionFailure(
    'Mover plata desde Inti necesita la conexión con el banco, que llega '
    'pronto.',
  );

  void dispose() => unawaited(_changes.close());
}

const Map<AccountKind, String> _kindToJson = {
  AccountKind.savings: 'savings',
  AccountKind.checking: 'checking',
  AccountKind.wallet: 'wallet',
  AccountKind.cash: 'cash',
  AccountKind.creditCard: 'credit_card',
};

const Map<String, ConnectionStatus> _statusFromJson = {
  'connected': ConnectionStatus.connected,
  'needs_reconnect': ConnectionStatus.needsReconnect,
  'manual': ConnectionStatus.manual,
};

Account accountFromJson(Map<String, Object?> j) {
  final institutionId = j['institutionId'] as String?;
  final code = j['currency']! as String;
  return Account(
    id: j['id']! as String,
    institution: j['institution']! as String,
    badge: institutionId == null
        ? null
        : Institutions.byId(institutionId)?.badge,
    kind: _kindToJson.entries.firstWhere((e) => e.value == j['kind']).key,
    last4: j['last4']! as String,
    ownership: Ownership.values.byName(j['ownership']! as String),
    balance: (j['balance']! as num).toInt(),
    status: _statusFromJson[j['status']]!,
    lastSync: DateTime.parse(j['lastSync']! as String).toLocal(),
    nickname: j['nickname'] as String?,
    creditLimit: (j['creditLimit'] as num?)?.toInt(),
    statementBalance: (j['statementBalance'] as num?)?.toInt(),
    minimumPayment: (j['minimumPayment'] as num?)?.toInt(),
    paymentDue: j['paymentDue'] == null
        ? null
        : DateTime.parse(j['paymentDue']! as String),
    interestRate: (j['interestRate'] as num?)?.toDouble(),
    paymentsEnabled: j['paymentsEnabled']! as bool,
    currency: Currency.values.firstWhere((c) => c.code == code),
    rate: (j['rate']! as num).toDouble(),
  );
}
