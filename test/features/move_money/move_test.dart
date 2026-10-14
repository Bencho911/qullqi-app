import 'package:flutter_test/flutter_test.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart';
import 'package:inti/features/accounts/domain/account.dart';
import 'package:inti/features/move_money/data/money_mover.dart';
import 'package:inti/features/move_money/domain/move.dart';
import 'package:inti/features/transactions/data/ledger.dart';
import 'package:inti/features/transactions/data/transactions_repository.dart';
import 'package:inti/features/transactions/domain/transaction.dart';

void main() {
  final now = DateTime(2026, 10, 24, 14, 45);
  late MockAccountsRepository accounts;
  late MockTransactionsRepository transactions;
  late Ledger ledger;

  setUp(() {
    accounts = MockAccountsRepository(now: () => now, latency: Duration.zero);
    transactions = MockTransactionsRepository(
      now: () => now,
      latency: Duration.zero,
    );
    ledger = Ledger(
      transactions: transactions,
      accounts: accounts,
      now: () => now,
    );
  });

  Future<Map<String, Account>> snapshot() async => {
    for (final a in await accounts.watch().first) a.id: a,
  };

  group('Validación', () {
    test('cada problema se detecta antes de intentar', () async {
      final a = await snapshot();
      MoveProblem? v(String f, String t, int n) =>
          validateMove(from: a[f], to: a[t], amount: n);
      expect(v('nequi', 'bancolombia', 0), MoveProblem.noAmount);
      expect(v('nequi', 'nequi', 1000), MoveProblem.sameAccount);
      expect(v('visa', 'nequi', 1000), MoveProblem.sourceIsCard);
      expect(v('davivienda', 'nequi', 1000), MoveProblem.sourceDisconnected);
      expect(v('nequi', 'bancolombia', 900000), MoveProblem.insufficientFunds);
      expect(v('nu', 'visa', 1), MoveProblem.sourceIsCard);
      expect(v('bancolombia', 'nu', 500000), MoveProblem.overCardDebt);
      expect(v('nequi', 'bancolombia', 300000), isNull);
      // Daviplata (negocio) también tiene autorizado mover plata.
      expect(v('daviplata', 'nequi', 1000), isNull);
    });

    test('el tope diario se respeta', () {
      final rich = Account(
        id: 'x',
        institution: 'Banco',
        kind: AccountKind.savings,
        last4: '0000',
        ownership: Ownership.personal,
        balance: 9000000,
        status: ConnectionStatus.connected,
        lastSync: now,
        paymentsEnabled: true,
      );
      final other = Account(
        id: 'y',
        institution: 'Otro',
        kind: AccountKind.savings,
        last4: '1111',
        ownership: Ownership.personal,
        balance: 0,
        status: ConnectionStatus.connected,
        lastSync: now,
      );
      expect(
        validateMove(from: rich, to: other, amount: dailyMoveLimit + 1),
        MoveProblem.overDailyLimit,
      );
    });
  });

  group('Mover plata', () {
    MockMoneyMover mover() => MockMoneyMover(
      accounts: accounts,
      transactions: transactions,
      ledger: ledger,
      now: () => now,
      latency: Duration.zero,
    );

    test('entre cuentas: sale de una y llega a la otra', () async {
      final a = await snapshot();
      final r = await mover().move(
        from: a['nequi']!,
        to: a['bancolombia']!,
        amount: 300000,
      );
      expect(r.status, MoveStatus.done); // Nequi confirma al instante
      final b = await snapshot();
      expect(b['nequi']!.balance, 850000 - 300000);
      expect(b['bancolombia']!.balance, 3200000 + 300000);
      final txs = await transactions.watch().first;
      expect(txs.first.kind, TransactionKind.transfer);
      expect(txs.first.title, 'De Nequi a Bancolombia');
    });

    test('pagar una tarjeta baja la deuda y el corte', () async {
      final a = await snapshot();
      final r = await mover().move(
        from: a['bancolombia']!,
        to: a['visa']!,
        amount: 320000,
      );
      expect(r.status, MoveStatus.pending); // banco tradicional
      final b = await snapshot();
      expect(b['visa']!.debt, 1320000 - 320000);
      expect(b['visa']!.statementBalance, 1000000);
      expect(b['bancolombia']!.balance, 3200000 - 320000);
    });

    test('si el banco rechaza no se mueve nada', () async {
      final a = await snapshot();
      final r = await mover().move(
        from: a['nequi']!,
        to: a['bancolombia']!,
        amount: 100013,
      );
      expect(r.status, MoveStatus.rejected);
      expect(r.reason, isNotEmpty);
      final b = await snapshot();
      expect(b['nequi']!.balance, 850000);
    });
  });

  group('Libro de movimientos manuales', () {
    test('un gasto baja el saldo y borrarlo lo devuelve', () async {
      final tx = await ledger.record(
        kind: TransactionKind.expense,
        amount: 50000,
        accountId: 'nequi',
        categoryId: 'mercado',
        ownership: Ownership.personal,
      );
      expect(tx.title, 'Mercado'); // sin comercio, usa la categoría
      expect(tx.canDelete, isTrue);
      expect((await snapshot())['nequi']!.balance, 800000);
      await ledger.remove(tx);
      expect((await snapshot())['nequi']!.balance, 850000);
    });

    test('un gasto con tarjeta sube la deuda', () async {
      await ledger.record(
        kind: TransactionKind.expense,
        amount: 80000,
        accountId: 'nu',
        categoryId: 'salidas',
        ownership: Ownership.personal,
        title: '  Crepes & Waffles ',
      );
      expect((await snapshot())['nu']!.debt, 530000);
      final txs = await transactions.watch().first;
      expect(txs.first.title, 'Crepes & Waffles');
    });

    test('un ingreso sube el saldo', () async {
      await ledger.record(
        kind: TransactionKind.income,
        amount: 200000,
        accountId: 'bancolombia',
        categoryId: 'honorarios',
        ownership: Ownership.personal,
      );
      expect((await snapshot())['bancolombia']!.balance, 3400000);
    });
  });
}
