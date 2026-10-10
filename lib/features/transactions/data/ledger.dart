import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';

/// Registra movimientos manuales y mantiene los saldos coherentes: cada
/// gasto, ingreso o borrado se refleja en la cuenta que corresponde.
class Ledger {
  Ledger({
    required this.transactions,
    required this.accounts,
    required this.now,
  });

  final TransactionsRepository transactions;
  final AccountsRepository accounts;
  final DateTime Function() now;

  static int _seq = 0;

  /// Id único local (el backend asignará el definitivo).
  String newId(String prefix) =>
      '$prefix-${now().microsecondsSinceEpoch}-${_seq++}';

  /// Guarda un gasto o ingreso registrado a mano y ajusta el saldo.
  Future<Transaction> record({
    required TransactionKind kind,
    required int amount,
    required String accountId,
    required String categoryId,
    required Ownership ownership,
    String? title,
    String? note,
  }) async {
    assert(kind != TransactionKind.transfer, 'Los traslados usan move()');
    assert(amount > 0, 'El monto debe ser positivo');
    final tx = Transaction(
      id: newId('m'),
      title: (title?.trim().isNotEmpty ?? false)
          ? title!.trim()
          : Categories.byId(categoryId).name,
      amount: amount,
      kind: kind,
      accountId: accountId,
      categoryId: categoryId,
      ownership: ownership,
      date: now(),
      note: (note?.trim().isEmpty ?? true) ? null : note!.trim(),
      source: TransactionSource.manual,
    );
    await transactions.add(tx);
    await accounts.applyDelta(accountId, tx.signedAmount);
    return tx;
  }

  /// Borra un movimiento manual y devuelve el saldo a como estaba. Uno
  /// importado de un extracto nunca movió el saldo: solo se borra.
  Future<void> remove(Transaction tx) async {
    await transactions.delete(tx.id);
    if (tx.source == TransactionSource.manual) {
      await accounts.applyDelta(tx.accountId, -tx.signedAmount);
    }
  }
}

final ledgerProvider = Provider<Ledger>(
  (ref) => Ledger(
    transactions: ref.watch(transactionsRepositoryProvider),
    accounts: ref.watch(accountsRepositoryProvider),
    now: ref.watch(clockProvider),
  ),
);
