import 'package:flutter_test/flutter_test.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/transactions/data/transactions_repository.dart';
import 'package:inti/features/transactions/domain/transaction.dart';
import 'package:inti/features/transactions/domain/transaction_filter.dart';

void main() {
  final now = DateTime(2026, 10, 24, 14, 45);
  late MockTransactionsRepository repo;
  late List<Transaction> all;

  setUp(() async {
    repo = MockTransactionsRepository(now: () => now, latency: Duration.zero);
    all = await repo.watch().first;
  });

  String name(String id) => switch (id) {
    'nequi' => 'Nequi',
    'bancolombia' => 'Bancolombia',
    _ => id,
  };

  List<Transaction> run(TransactionFilter f, {Scope scope = Scope.all}) =>
      applyFilter(all, f, scope: scope, now: now, accountName: name);

  group('Búsqueda', () {
    test('ignora tildes y mayúsculas', () {
      expect(normalizeForSearch('  ÉXITO Chapinero '), 'exito chapinero');
      final r = run(const TransactionFilter(query: 'exito'));
      expect(r.map((t) => t.title), ['Éxito Chapinero']);
    });

    test('encuentra por categoría y por cuenta', () {
      expect(run(const TransactionFilter(query: 'salud')).map((t) => t.title), [
        'Farmatodo Nogal',
      ]);
      expect(
        run(const TransactionFilter(query: 'nequi')).length,
        greaterThanOrEqualTo(3),
      );
    });
  });

  group('Filtros', () {
    test('por tipo', () {
      final r = run(const TransactionFilter(kind: TransactionKind.income));
      expect(r.every((t) => t.kind == TransactionKind.income), isTrue);
      expect(r, isNotEmpty);
    });

    test('este mes no incluye septiembre; mes pasado sí', () {
      final thisMonth = run(const TransactionFilter());
      expect(thisMonth.any((t) => t.title == 'Arriendo septiembre'), isFalse);
      final last = run(const TransactionFilter(range: DateRange.lastMonth));
      expect(
        last.map((t) => t.title),
        unorderedEquals([
          'Arriendo septiembre',
          'Pago nómina freelance',
          'Netflix',
          'Spotify',
          'Éxito Chapinero',
        ]),
      );
    });

    test('mes pasado funciona en enero (diciembre del año anterior)', () {
      final jan = DateTime(2027, 1, 10);
      expect(DateRange.lastMonth.contains(DateTime(2026, 12, 5), jan), isTrue);
      expect(DateRange.lastMonth.contains(DateTime(2027, 1, 5), jan), isFalse);
    });

    test('por cuenta y categoría a la vez', () {
      final r = run(
        const TransactionFilter(
          range: DateRange.all,
          accountIds: {'bancolombia'},
          categoryIds: {'salud'},
        ),
      );
      expect(r.map((t) => t.title), ['Farmatodo Nogal']);
    });

    test('respeta la vista', () {
      final r = run(const TransactionFilter(), scope: Scope.business);
      expect(r.every((t) => t.ownership == Ownership.business), isTrue);
    });

    test('cuenta los filtros de la hoja', () {
      expect(const TransactionFilter().sheetCount, 0);
      expect(
        const TransactionFilter(
          range: DateRange.all,
          accountIds: {'nequi'},
        ).sheetCount,
        2,
      );
      expect(const TransactionFilter(query: 'x').isDefault, isFalse);
    });
  });

  test('los totales no cuentan traslados', () {
    final t = FlowTotals.of(run(const TransactionFilter()));
    final transfers = run(
      const TransactionFilter(kind: TransactionKind.transfer),
    );
    expect(transfers, isNotEmpty);
    // Ingresos de octubre: 2.500.000 + 150.000 + 1.850.000 + 1.071.000.
    expect(t.income, 5571000);
    expect(
      t.expense,
      // Los de siempre + dos Rappi + la cuota de manejo.
      85400 + 18500 + 142000 + 75000 + 63200 + 38900 + 32000 + 32000 + 24900,
    );
  });

  test('agrupa por día del más reciente al más antiguo', () {
    final groups = groupByDay(run(const TransactionFilter()), now);
    expect(groups.first.label, 'Hoy');
    expect(groups[1].label, 'Ayer');
    expect(groups.first.items.length, 3);
    for (final g in groups) {
      for (var i = 1; i < g.items.length; i++) {
        expect(g.items[i - 1].date.isAfter(g.items[i].date), isTrue);
      }
    }
  });

  group('Repositorio', () {
    test('actualiza y emite el cambio', () async {
      final next = repo.watch().skip(1).first;
      final t1 = all.firstWhere((t) => t.id == 't1');
      await repo.update(t1.copyWith(categoryId: 'salud', note: 'Mercado mes'));
      final updated = (await next).firstWhere((t) => t.id == 't1');
      expect(updated.categoryId, 'salud');
      expect(updated.note, 'Mercado mes');
    });

    test('una nota vacía se borra', () {
      final t = all.first.copyWith(note: 'algo').copyWith(note: '   ');
      expect(t.note, isNull);
    });

    test('no deja borrar movimientos del banco', () async {
      expect(() => repo.delete('t1'), throwsStateError);
    });
  });
}
