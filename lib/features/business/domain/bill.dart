import 'package:flutter/foundation.dart' show immutable;

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/features/commitments/domain/commitment.dart';

enum BillStatus { pending, overdue, paid }

/// Una cuenta por pagar a un proveedor del negocio.
@immutable
class Bill {
  const Bill({
    required this.id,
    required this.supplier,
    required this.concept,
    required this.amount,
    required this.due,
    required this.categoryId,
    this.paidOn,
  });

  final String id;
  final String supplier;

  /// Qué se compró o se debe ("Diseño de empaques").
  final String concept;
  final int amount;
  final DateTime due;
  final String categoryId;
  final DateTime? paidOn;

  BillStatus statusAt(DateTime now) => paidOn != null
      ? BillStatus.paid
      : daysBetween(now, due) < 0
      ? BillStatus.overdue
      : BillStatus.pending;

  Bill paid(DateTime when) => Bill(
    id: id,
    supplier: supplier,
    concept: concept,
    amount: amount,
    due: due,
    categoryId: categoryId,
    paidOn: when,
  );
}

/// Las cuentas por pagar abiertas cuentan como pagos próximos del negocio, y
/// por eso bajan lo que puedes gastar y llegan a los avisos.
List<Commitment> withBillCommitments(
  List<Commitment> commitments,
  List<Bill> bills,
) => [
  ...commitments,
  for (final b in bills)
    if (b.paidOn == null)
      Commitment(
        id: 'bill:${b.id}',
        title: '${b.supplier}: ${b.concept}',
        amount: b.amount,
        due: b.due,
        ownership: Ownership.business,
        kind: CommitmentKind.bill,
      ),
];
