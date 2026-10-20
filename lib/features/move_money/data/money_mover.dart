import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inti/core/api/api_client.dart';
import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/data/latency.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart';
import 'package:inti/features/accounts/domain/account.dart';
import 'package:inti/features/move_money/domain/move.dart';
import 'package:inti/features/transactions/data/ledger.dart';
import 'package:inti/features/transactions/data/transactions_repository.dart';
import 'package:inti/features/transactions/domain/transaction.dart';

/// Mueve plata entre cuentas propias. La versión real usará la iniciación
/// de pagos de Open Finance del banco de origen; la app solo depende de
/// esta interfaz.
abstract interface class MoneyMover {
  Future<MoveResult> move({
    required Account from,
    required Account to,
    required int amount,
  });
}

final moneyMoverProvider = Provider<MoneyMover>(
  (ref) => ref.watch(apiClientProvider) != null
      ? UnavailableMoneyMover(now: ref.watch(clockProvider))
      : MockMoneyMover(
          accounts: ref.watch(accountsRepositoryProvider),
          transactions: ref.watch(transactionsRepositoryProvider),
          ledger: ref.watch(ledgerProvider),
          now: ref.watch(clockProvider),
          latency: ref.watch(mockLatencyProvider),
        ),
);

/// Con el backend real, mover plata espera la iniciación de pagos del
/// banco: se rechaza con un motivo claro en lugar de simularlo.
class UnavailableMoneyMover implements MoneyMover {
  UnavailableMoneyMover({required this.now});

  final DateTime Function() now;

  @override
  Future<MoveResult> move({
    required Account from,
    required Account to,
    required int amount,
  }) async => MoveResult(
    status: MoveStatus.rejected,
    reference: '',
    when: now(),
    reason: 'Mover plata desde Inti llega con la conexión a tu banco.',
  );
}

/// Simulación con las reglas del producto:
/// - Nequi y Daviplata confirman al instante.
/// - Los bancos tradicionales quedan "en proceso" (llega hoy).
/// - Montos terminados en 13 se rechazan (para probar el estado de error).
class MockMoneyMover implements MoneyMover {
  MockMoneyMover({
    required this.accounts,
    required this.transactions,
    required this.ledger,
    required this.now,
    required this.latency,
  });

  final AccountsRepository accounts;
  final TransactionsRepository transactions;
  final Ledger ledger;
  final DateTime Function() now;
  final Duration latency;

  static const _instant = {'nequi', 'daviplata'};

  @override
  Future<MoveResult> move({
    required Account from,
    required Account to,
    required int amount,
  }) async {
    await Future<void>.delayed(latency * 2);
    final when = now();
    final reference = 'QL${when.millisecondsSinceEpoch % 100000000}';

    if (amount % 100 == 13) {
      return MoveResult(
        status: MoveStatus.rejected,
        reference: reference,
        when: when,
        reason: '${from.institution} no autorizó la operación.',
      );
    }

    // Se descuenta del origen y se suma al destino (o baja la deuda).
    await accounts.applyDelta(from.id, -amount);
    await accounts.applyDelta(to.id, amount);
    final title = to.isCard
        ? 'Pago ${to.shortName}'
        : 'De ${from.shortName} a ${to.shortName}';
    await transactions.add(
      Transaction(
        id: ledger.newId('mv'),
        title: title,
        amount: amount,
        kind: TransactionKind.transfer,
        accountId: from.id,
        categoryId: Categories.internal.id,
        ownership: from.ownership,
        date: when,
        note: 'Comprobante $reference',
      ),
    );

    return MoveResult(
      status: _instant.contains(from.id) ? MoveStatus.done : MoveStatus.pending,
      reference: reference,
      when: when,
    );
  }
}
