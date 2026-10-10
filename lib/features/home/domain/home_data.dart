import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/scope/scope_provider.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/accounts/domain/account.dart';
import 'package:qullqi/features/business/data/invoices_repository.dart';
import 'package:qullqi/features/business/domain/business.dart';
import 'package:qullqi/features/commitments/data/commitments_repository.dart';
import 'package:qullqi/features/commitments/domain/commitment.dart';
import 'package:qullqi/features/home/domain/money_summary.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';

/// Lo que muestra el Inicio para la vista activa.
@immutable
class HomeData {
  const HomeData({
    required this.scope,
    required this.now,
    required this.summary,
    required this.byOwnership,
    required this.accounts,
    required this.recent,
    required this.needsReconnect,
    required this.hasAnyAccount,
    required this.business,
  });

  final Scope scope;
  final DateTime now;
  final MoneySummary summary;

  /// Disponible de cada ámbito (para el reparto en la vista Todo).
  final Map<Ownership, int> byOwnership;

  /// Cuentas de la vista: primero las líquidas, luego las tarjetas.
  final List<Account> accounts;
  final List<Transaction> recent;

  /// Cuentas de la vista con el permiso vencido.
  final List<Account> needsReconnect;

  /// Si la persona tiene al menos una cuenta (en cualquier vista).
  final bool hasAnyAccount;

  /// Utilidad, cobros e IVA del negocio en el mes.
  final BusinessMonth business;

  static const recentCount = 4;
}

/// Los pagos fijos más el IVA estimado del bimestre, que es un pago próximo
/// del negocio.
List<Commitment> withIvaCommitment(
  List<Commitment> commitments,
  BusinessMonth business,
) {
  final iva = business.iva;
  return [
    ...commitments,
    if (iva.toPay > 0)
      Commitment(
        id: 'iva',
        title: 'IVA de ${iva.label}',
        amount: iva.toPay,
        due: iva.due,
        ownership: Ownership.business,
        kind: CommitmentKind.tax,
      ),
  ];
}

/// Combina las tres fuentes. Carga mientras falte alguna; si una falla, el
/// Inicio muestra el error con opción de reintentar.
final homeDataProvider = Provider<AsyncValue<HomeData>>((ref) {
  final accounts = ref.watch(accountsProvider);
  final commitments = ref.watch(commitmentsProvider);
  final transactions = ref.watch(transactionsProvider);
  final invoices = ref.watch(invoicesProvider);
  final scope = ref.watch(scopeProvider);
  final now = ref.watch(clockProvider)();

  for (final v in [accounts, commitments, transactions, invoices]) {
    if (v.hasError) return AsyncError<HomeData>(v.error!, v.stackTrace!);
  }
  if (!accounts.hasValue ||
      !commitments.hasValue ||
      !transactions.hasValue ||
      !invoices.hasValue) {
    return const AsyncLoading<HomeData>();
  }

  final allAccounts = accounts.requireValue;
  final business = BusinessMonth.of(
    invoices.requireValue,
    transactions.requireValue,
    now,
  );
  final allCommitments = withIvaCommitment(commitments.requireValue, business);
  MoneySummary summaryFor(Scope s) => MoneySummary.compute(
    accounts: allAccounts,
    commitments: allCommitments,
    scope: s,
    now: now,
  );

  final visible =
      allAccounts.where((a) => a.ownership.visibleIn(scope)).toList()
        ..sort((a, b) {
          if (a.isCard != b.isCard) return a.isCard ? 1 : -1;
          return b.balance.compareTo(a.balance);
        });

  return AsyncData(
    HomeData(
      scope: scope,
      now: now,
      summary: summaryFor(scope),
      byOwnership: {
        for (final o in Ownership.values)
          o: summaryFor(
            o == Ownership.personal ? Scope.personal : Scope.business,
          ).available,
      },
      accounts: visible,
      recent: transactions.requireValue
          .where((t) => t.ownership.visibleIn(scope))
          .take(HomeData.recentCount)
          .toList(),
      needsReconnect: visible
          .where((a) => a.status == ConnectionStatus.needsReconnect)
          .toList(),
      hasAnyAccount: allAccounts.isNotEmpty,
      business: business,
    ),
  );
});
