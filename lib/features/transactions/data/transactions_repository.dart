import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inti/core/api/api_client.dart';
import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/data/latency.dart';
import 'package:inti/core/data/live_stream.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart';
import 'package:inti/features/transactions/data/api_transactions_repository.dart';
import 'package:inti/features/transactions/domain/transaction.dart';

/// Movimientos de todas las cuentas, del más reciente al más antiguo.
abstract interface class TransactionsRepository {
  Stream<List<Transaction>> watch();

  /// Guarda cambios de clasificación (categoría, ámbito, nota, tipo).
  Future<void> update(Transaction transaction);

  /// Borra un movimiento registrado a mano.
  Future<void> delete(String id);

  /// Agrega un movimiento nuevo (manual o de un traslado).
  Future<void> add(Transaction transaction);
}

final transactionsRepositoryProvider = Provider<TransactionsRepository>((ref) {
  final api = ref.watch(apiClientProvider);
  if (api != null) {
    final repo = ApiTransactionsRepository(
      api,
      onBalancesChanged: () => ref.read(accountsRepositoryProvider).sync(),
    );
    ref.onDispose(repo.dispose);
    return repo;
  }
  final repo = MockTransactionsRepository(
    now: ref.watch(clockProvider),
    latency: ref.watch(mockLatencyProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final transactionsProvider = StreamProvider<List<Transaction>>(
  (ref) => ref.watch(transactionsRepositoryProvider).watch(),
);

class MockTransactionsRepository implements TransactionsRepository {
  MockTransactionsRepository({required this.now, required this.latency})
    : _items = _seed(now());

  final DateTime Function() now;
  final Duration latency;
  List<Transaction> _items;
  final _changes = StreamController<List<Transaction>>.broadcast();

  @override
  Stream<List<Transaction>> watch() => liveStream(
    changes: _changes.stream,
    current: () => List.unmodifiable(_items),
    latency: latency,
  );

  @override
  Future<void> update(Transaction transaction) async {
    await Future<void>.delayed(latency ~/ 2);
    _items = [
      for (final t in _items)
        if (t.id == transaction.id) transaction else t,
    ];
    _changes.add(List.unmodifiable(_items));
  }

  @override
  Future<void> delete(String id) async {
    final target = _items.where((t) => t.id == id).firstOrNull;
    if (target == null) return;
    if (!target.canDelete) {
      throw StateError('Los movimientos del banco no se pueden borrar.');
    }
    await Future<void>.delayed(latency ~/ 2);
    _items = _items.where((t) => t.id != id).toList();
    _changes.add(List.unmodifiable(_items));
  }

  @override
  Future<void> add(Transaction transaction) async {
    await Future<void>.delayed(latency ~/ 2);
    _items = [transaction, ..._items]..sort((a, b) => b.date.compareTo(a.date));
    _changes.add(List.unmodifiable(_items));
  }

  void dispose() => unawaited(_changes.close());

  static List<Transaction> _seed(DateTime now) {
    final today = dateOnly(now);
    DateTime at(int daysAgo, int h, int m) => today
        .subtract(Duration(days: daysAgo))
        .add(Duration(hours: h, minutes: m));
    Transaction t(
      String id,
      String title,
      int amount,
      TransactionKind kind,
      String account,
      Category cat,
      Ownership own,
      DateTime date, {
      bool review = false,
    }) => Transaction(
      id: id,
      title: title,
      amount: amount,
      kind: kind,
      accountId: account,
      categoryId: cat.id,
      ownership: own,
      date: date,
      needsReview: review,
    );
    const e = TransactionKind.expense;
    const i = TransactionKind.income;
    const x = TransactionKind.transfer;
    const p = Ownership.personal;
    const b = Ownership.business;
    final list = [
      t(
        't1',
        'Éxito Chapinero',
        85400,
        e,
        'nequi',
        Categories.groceries,
        p,
        at(0, 14, 32),
      ),
      t(
        't2',
        'Anticipo proyecto UX',
        2500000,
        i,
        'davivienda',
        Categories.fees,
        b,
        at(0, 11, 15),
      ),
      t(
        't3',
        'Pago de Juan Pérez',
        150000,
        i,
        'nequi',
        Categories.transferIn,
        p,
        at(0, 9, 15),
      ),
      t(
        't4',
        'Starbucks Torre 72',
        18500,
        e,
        'bancolombia',
        Categories.coffee,
        p,
        at(1, 16, 40),
      ),
      t(
        't5',
        'Figma y Notion',
        142000,
        e,
        'daviplata',
        Categories.software,
        b,
        at(1, 12, 20),
      ),
      t(
        't6',
        'Terpel Calle 100',
        75000,
        e,
        'visa',
        Categories.transport,
        p,
        at(1, 8, 12),
      ),
      t(
        't7',
        'De Bancolombia a Nequi',
        300000,
        x,
        'bancolombia',
        Categories.internal,
        p,
        at(2, 9, 14),
        review: true,
      ),
      t(
        't8',
        'Farmatodo Nogal',
        63200,
        e,
        'bancolombia',
        Categories.health,
        p,
        at(3, 19, 45),
      ),
      t(
        't9',
        'Asesoría digital',
        1850000,
        i,
        'davivienda',
        Categories.fees,
        b,
        at(3, 10, 5),
      ),
      t(
        't11',
        'De Nequi a Daviplata',
        120000,
        x,
        'nequi',
        Categories.internal,
        p,
        at(3, 18, 42),
        review: true,
      ),
      t(
        't12',
        'Arriendo septiembre',
        1200000,
        e,
        'bancolombia',
        Categories.home,
        p,
        DateTime(now.year, now.month - 1, 28, 8, 30),
      ),
      t(
        't13',
        'Pago nómina freelance',
        2500000,
        i,
        'bancolombia',
        Categories.fees,
        p,
        DateTime(now.year, now.month - 1, 30, 11),
      ),
      t(
        't10',
        'Netflix',
        38900,
        e,
        'visa',
        Categories.subscriptions,
        p,
        at(4, 6, 0),
      ),
      // Meses anteriores: lo que permite ver qué se repite y qué subió.
      t(
        't14',
        'Netflix',
        34900,
        e,
        'visa',
        Categories.subscriptions,
        p,
        DateTime(now.year, now.month - 1, 20, 6),
      ),
      t(
        't15',
        'Netflix',
        34900,
        e,
        'visa',
        Categories.subscriptions,
        p,
        DateTime(now.year, now.month - 2, 20, 6),
      ),
      t(
        't16',
        'Spotify',
        16900,
        e,
        'nequi',
        Categories.subscriptions,
        p,
        DateTime(now.year, now.month - 1, 28, 7),
      ),
      t(
        't17',
        'Spotify',
        16900,
        e,
        'nequi',
        Categories.subscriptions,
        p,
        DateTime(now.year, now.month - 2, 28, 7),
      ),
      t(
        't18',
        'Spotify',
        16900,
        e,
        'nequi',
        Categories.subscriptions,
        p,
        DateTime(now.year, now.month - 3, 28, 7),
      ),
      t(
        't25',
        'Transferencia Café Origen',
        1071000,
        i,
        'davivienda',
        Categories.fees,
        b,
        at(2, 10, 5),
      ),
      // Cobros que conviene mirar dos veces: un duplicado, una comisión y un
      // Éxito muy por encima de lo habitual (sus compras previas eran de
      // $35.000).
      t(
        't19',
        'Rappi pedido',
        32000,
        e,
        'nequi',
        Categories.other,
        p,
        at(1, 20, 10),
      ),
      t(
        't20',
        'Rappi pedido',
        32000,
        e,
        'nequi',
        Categories.other,
        p,
        at(1, 20, 12),
      ),
      t(
        't21',
        'Cuota de manejo tarjeta',
        24900,
        e,
        'visa',
        Categories.other,
        p,
        at(2, 4, 0),
      ),
      t(
        't22',
        'Éxito Chapinero',
        35000,
        e,
        'nequi',
        Categories.groceries,
        p,
        DateTime(now.year, now.month - 1, 10, 18),
      ),
      t(
        't23',
        'Éxito Chapinero',
        35000,
        e,
        'nequi',
        Categories.groceries,
        p,
        DateTime(now.year, now.month - 2, 10, 18),
      ),
      t(
        't24',
        'Éxito Chapinero',
        35000,
        e,
        'nequi',
        Categories.groceries,
        p,
        DateTime(now.year, now.month - 3, 10, 18),
      ),
    ]..sort((a, c) => c.date.compareTo(a.date));
    return list;
  }
}
