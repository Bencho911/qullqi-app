import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/data/latency.dart';
import 'package:qullqi/core/data/live_stream.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/features/accounts/domain/account.dart';
import 'package:qullqi/features/accounts/domain/institution.dart';

/// Fuente de las cuentas de la persona. La implementación real hablará con
/// el agregador Open Finance; la app solo depende de esta interfaz.
abstract interface class AccountsRepository {
  /// Emite la lista actual y cada cambio.
  Stream<List<Account>> watch();

  /// Pide al banco los saldos de hoy.
  Future<void> sync();

  /// Refleja en el saldo un movimiento (registrado a mano o un traslado).
  /// `delta` negativo es plata que sale de la cuenta.
  Future<void> applyDelta(String accountId, int delta);

  /// Conecta una entidad por Open Finance. Devuelve la cuenta creada.
  /// Lanza [ConnectionFailure] si el banco no responde o la rechaza.
  Future<Account> connect(Institution institution, {required bool payments});

  /// Renueva el permiso de una cuenta cuyo acceso venció.
  Future<void> reconnect(String accountId);

  /// Agrega una cuenta registrada a mano (efectivo, cooperativas…).
  Future<Account> addManual({
    required String name,
    required AccountKind kind,
    required int balance,
    required Ownership ownership,
    String last4,
  });

  /// Quita la cuenta de Qullqi y revoca el permiso con el banco.
  Future<void> remove(String accountId);

  /// Activa o desactiva mover plata desde la cuenta (pide el permiso de
  /// pagos al banco al activarlo).
  Future<void> setPaymentsEnabled(String accountId, {required bool enabled});
}

/// El banco no completó la conexión.
class ConnectionFailure implements Exception {
  const ConnectionFailure(this.message);

  /// Qué pasó, en palabras de la persona.
  final String message;

  @override
  String toString() => message;
}

final accountsRepositoryProvider = Provider<AccountsRepository>((ref) {
  final repo = MockAccountsRepository(
    now: ref.watch(clockProvider),
    latency: ref.watch(mockLatencyProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

/// Cuentas de la persona, en vivo.
final accountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountsRepositoryProvider).watch(),
);

/// Datos de prueba en memoria, coherentes con el resto de la app.
class MockAccountsRepository implements AccountsRepository {
  MockAccountsRepository({required this.now, required this.latency})
    : _items = _seed(now());

  final DateTime Function() now;
  final Duration latency;
  List<Account> _items;
  final _changes = StreamController<List<Account>>.broadcast();

  @override
  Stream<List<Account>> watch() => liveStream(
    changes: _changes.stream,
    current: () => _items,
    latency: latency,
  );

  @override
  Future<void> sync() async {
    await Future<void>.delayed(latency * 2);
    final t = now();
    _items = [
      for (final a in _items)
        if (a.status == ConnectionStatus.connected)
          a.copyWith(lastSync: t)
        else
          a,
    ];
    _changes.add(_items);
  }

  @override
  Future<void> applyDelta(String accountId, int delta) async {
    _items = [
      for (final a in _items)
        if (a.id == accountId) a.applyDelta(delta) else a,
    ];
    _changes.add(_items);
  }

  int _seq = 0;

  void _emit() => _changes.add(List.unmodifiable(_items));

  @override
  Future<Account> connect(
    Institution institution, {
    required bool payments,
  }) async {
    await Future<void>.delayed(latency * 3);
    if (!institution.available) {
      throw ConnectionFailure(
        '${institution.name} aún no tiene conexión automática.',
      );
    }
    // Simulación: Lulo Bank no responde (para ver el estado de error).
    if (institution.id == 'lulo') {
      throw const ConnectionFailure(
        'Lulo Bank no respondió. Puede ser algo temporal de su lado.',
      );
    }
    final account = Account(
      id: '${institution.id}-${_seq++}',
      institution: institution.name,
      badge: institution.badge,
      kind: institution.kind,
      last4: (1000 + institution.name.length * 731 % 9000).toString(),
      ownership: Ownership.personal,
      balance: 640000 + institution.name.length * 15000,
      status: ConnectionStatus.connected,
      lastSync: now(),
      paymentsEnabled: payments && institution.supportsPayments,
    );
    _items = [..._items, account];
    _emit();
    return account;
  }

  @override
  Future<void> reconnect(String accountId) async {
    await Future<void>.delayed(latency * 3);
    _items = [
      for (final a in _items)
        if (a.id == accountId)
          a.copyWith(status: ConnectionStatus.connected, lastSync: now())
        else
          a,
    ];
    _emit();
  }

  @override
  Future<Account> addManual({
    required String name,
    required AccountKind kind,
    required int balance,
    required Ownership ownership,
    String last4 = '',
  }) async {
    await Future<void>.delayed(latency);
    final account = Account(
      id: 'manual-${_seq++}',
      institution: name.trim(),
      kind: kind,
      last4: last4.isEmpty ? '0000' : last4,
      ownership: ownership,
      balance: balance,
      status: ConnectionStatus.manual,
      lastSync: now(),
    );
    _items = [..._items, account];
    _emit();
    return account;
  }

  @override
  Future<void> remove(String accountId) async {
    await Future<void>.delayed(latency);
    _items = _items.where((a) => a.id != accountId).toList();
    _emit();
  }

  @override
  Future<void> setPaymentsEnabled(
    String accountId, {
    required bool enabled,
  }) async {
    await Future<void>.delayed(latency);
    _items = [
      for (final a in _items)
        if (a.id == accountId) a.copyWith(paymentsEnabled: enabled) else a,
    ];
    _emit();
  }

  void dispose() => unawaited(_changes.close());

  static List<Account> _seed(DateTime now) {
    final today = dateOnly(now);
    return [
      Account(
        id: 'bancolombia',
        paymentsEnabled: true,
        badge: 'BC',
        institution: 'Bancolombia',
        kind: AccountKind.savings,
        last4: '4521',
        ownership: Ownership.personal,
        balance: 3200000,
        status: ConnectionStatus.connected,
        lastSync: now.subtract(const Duration(minutes: 5)),
      ),
      Account(
        id: 'nequi',
        paymentsEnabled: true,
        badge: 'NQ',
        institution: 'Nequi',
        kind: AccountKind.wallet,
        last4: '8901',
        ownership: Ownership.personal,
        balance: 850000,
        status: ConnectionStatus.connected,
        lastSync: now.subtract(const Duration(minutes: 12)),
      ),
      Account(
        id: 'davivienda',
        badge: 'DV',
        institution: 'Davivienda',
        kind: AccountKind.checking,
        last4: '7710',
        ownership: Ownership.business,
        balance: 2300000,
        status: ConnectionStatus.needsReconnect,
        lastSync: now.subtract(const Duration(days: 2)),
      ),
      Account(
        id: 'daviplata',
        paymentsEnabled: true,
        badge: 'DP',
        institution: 'Daviplata',
        kind: AccountKind.wallet,
        last4: '3320',
        ownership: Ownership.business,
        balance: 1450000,
        status: ConnectionStatus.connected,
        lastSync: now.subtract(const Duration(hours: 1)),
      ),
      Account(
        id: 'visa',
        badge: 'BC',
        institution: 'Bancolombia',
        nickname: 'Visa',
        kind: AccountKind.creditCard,
        last4: '4521',
        ownership: Ownership.personal,
        balance: 1320000,
        creditLimit: 5000000,
        statementBalance: 1320000,
        minimumPayment: 180000,
        paymentDue: today.add(const Duration(days: 3)),
        status: ConnectionStatus.connected,
        lastSync: now.subtract(const Duration(minutes: 5)),
      ),
      Account(
        id: 'nu',
        badge: 'NU',
        institution: 'Nu',
        nickname: 'Mastercard',
        kind: AccountKind.creditCard,
        last4: '8812',
        ownership: Ownership.personal,
        balance: 450000,
        creditLimit: 3000000,
        statementBalance: 450000,
        minimumPayment: 45000,
        paymentDue: today.add(const Duration(days: 27)),
        status: ConnectionStatus.connected,
        lastSync: now.subtract(const Duration(minutes: 30)),
      ),
    ];
  }
}
