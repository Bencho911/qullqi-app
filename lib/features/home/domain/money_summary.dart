import 'package:flutter/foundation.dart';

import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/accounts/domain/account.dart';
import 'package:inti/features/commitments/domain/commitment.dart';
import 'package:inti/features/investments/domain/investment.dart';

enum PaymentKind { card, bill, tax }

/// Un pago que viene: el pago de una tarjeta o un compromiso.
@immutable
class UpcomingPayment {
  const UpcomingPayment({
    required this.id,
    required this.title,
    required this.amount,
    required this.due,
    required this.ownership,
    required this.kind,
    this.accountId,
    this.minimum,
  });

  final String id;
  final String title;
  final int amount;
  final DateTime due;
  final Ownership ownership;
  final PaymentKind kind;

  /// Tarjeta a la que corresponde (solo pagos de tarjeta).
  final String? accountId;

  /// Pago mínimo de la tarjeta, si aplica.
  final int? minimum;
}

/// Lo que hay que pagar pronto, en orden de vencimiento.
List<UpcomingPayment> upcomingPayments({
  required List<Account> accounts,
  required List<Commitment> commitments,
  required Scope scope,
}) {
  final list = <UpcomingPayment>[
    for (final a in accounts)
      if (a.isCard &&
          a.ownership.visibleIn(scope) &&
          a.paymentDue != null &&
          (a.statementBalance ?? 0) > 0)
        UpcomingPayment(
          id: 'card-${a.id}',
          title: a.shortName,
          amount: a.statementBalance!,
          due: a.paymentDue!,
          ownership: a.ownership,
          kind: PaymentKind.card,
          accountId: a.id,
          minimum: a.minimumPayment,
        ),
    for (final c in commitments)
      if (c.ownership.visibleIn(scope) && c.amount > 0)
        UpcomingPayment(
          id: c.id,
          title: c.title,
          amount: c.amount,
          due: c.due,
          ownership: c.ownership,
          kind: c.kind == CommitmentKind.tax
              ? PaymentKind.tax
              : PaymentKind.bill,
        ),
  ]..sort((a, b) => a.due.compareTo(b.due));
  return list;
}

/// Resumen del dinero para una vista.
///
/// Regla central de Inti: **disponible para gastar** = dinero en cuentas
/// líquidas − pagos que vencen en los próximos `horizonDays` días (tarjetas
/// por el valor del corte, pagos fijos e impuestos estimados).
@immutable
class MoneySummary {
  const MoneySummary({
    required this.liquid,
    required this.committed,
    required this.netWorth,
    required this.payments,
    this.invested = 0,
  });

  factory MoneySummary.compute({
    required List<Account> accounts,
    required List<Commitment> commitments,
    required Scope scope,
    required DateTime now,
    List<Investment> investments = const [],
    int horizonDays = horizonDaysDefault,
  }) {
    final visible = accounts.where((a) => a.ownership.visibleIn(scope));
    final liquid = visible
        .where((a) => a.kind.isLiquid)
        .fold<int>(0, (s, a) => s + a.balance);
    // Lo invertido suma al patrimonio, pero no es plata para gastar hoy.
    final invested = investments
        .where((i) => i.ownership.visibleIn(scope))
        .fold<int>(0, (s, i) => s + i.value);
    final netWorth = visible.fold<int>(0, (s, a) => s + a.netValue) + invested;
    final payments = upcomingPayments(
      accounts: accounts,
      commitments: commitments,
      scope: scope,
    );
    final committed = payments
        .where((p) => daysBetween(now, p.due) <= horizonDays)
        .fold<int>(0, (s, p) => s + p.amount);
    return MoneySummary(
      liquid: liquid,
      committed: committed,
      netWorth: netWorth,
      payments: payments,
      invested: invested,
    );
  }

  static const int horizonDaysDefault = 30;

  final int liquid;
  final int committed;

  /// Cuentas + inversiones − deudas de tarjetas.
  final int netWorth;

  /// Lo que valen las inversiones de la vista.
  final int invested;
  final List<UpcomingPayment> payments;

  int get available => liquid - committed;
}
