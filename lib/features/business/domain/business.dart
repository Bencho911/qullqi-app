import 'package:flutter/foundation.dart' show immutable;

import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/transactions/domain/transaction.dart';

/// Tarifa general de IVA en Colombia.
const double ivaRate = 0.19;

/// Día del mes siguiente al bimestre en que vence la declaración de IVA
/// (estimado: el calendario real depende del último dígito del NIT).
const int ivaDueDay = 12;

enum InvoiceStatus { pending, overdue, paid }

/// Factura de venta (un cobro a un cliente).
@immutable
class Invoice {
  const Invoice({
    required this.id,
    required this.client,
    required this.number,
    required this.base,
    required this.chargesIva,
    required this.issued,
    required this.due,
    this.paidOn,
  });

  final String id;
  final String client;

  /// "F-0042".
  final String number;

  /// Valor antes de IVA.
  final int base;
  final bool chargesIva;
  final DateTime issued;
  final DateTime due;
  final DateTime? paidOn;

  int get iva => chargesIva ? (base * ivaRate).round() : 0;
  int get total => base + iva;

  InvoiceStatus statusAt(DateTime now) => paidOn != null
      ? InvoiceStatus.paid
      : daysBetween(now, due) < 0
      ? InvoiceStatus.overdue
      : InvoiceStatus.pending;

  Invoice paid(DateTime when) => Invoice(
    id: id,
    client: client,
    number: number,
    base: base,
    chargesIva: chargesIva,
    issued: issued,
    due: due,
    paidOn: when,
  );
}

/// Bimestre de IVA (enero-febrero, marzo-abril…) que contiene [now].
({DateTime start, DateTime end, DateTime due, String label}) ivaPeriod(
  DateTime now,
) {
  final firstMonth = now.month.isOdd ? now.month : now.month - 1;
  final start = DateTime(now.year, firstMonth);
  final end = DateTime(now.year, firstMonth + 2);
  const months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  return (
    start: start,
    end: end,
    due: DateTime(end.year, end.month, ivaDueDay),
    label: '${months[start.month - 1]} y ${months[start.month]}',
  );
}

/// IVA estimado del bimestre: lo que cobraste en tus facturas menos el IVA
/// que pagaste en gastos del negocio (descontable).
@immutable
class IvaEstimate {
  const IvaEstimate({
    required this.generated,
    required this.deductible,
    required this.due,
    required this.label,
    required this.invoices,
  });

  factory IvaEstimate.of(
    List<Invoice> invoices,
    List<Transaction> txs,
    DateTime now,
  ) {
    final p = ivaPeriod(now);
    bool inPeriod(DateTime d) => !d.isBefore(p.start) && d.isBefore(p.end);
    final billed = invoices.where((i) => inPeriod(i.issued)).toList();
    final generated = billed.fold<int>(0, (s, i) => s + i.iva);
    // El IVA incluido en un gasto con IVA es total × 19 / 119.
    final deductible = txs
        .where(
          (t) =>
              t.ownership == Ownership.business &&
              t.kind == TransactionKind.expense &&
              inPeriod(t.date),
        )
        .fold<int>(
          0,
          (s, t) => s + (t.amount * ivaRate / (1 + ivaRate)).round(),
        );
    return IvaEstimate(
      generated: generated,
      deductible: deductible,
      due: p.due,
      label: p.label,
      invoices: billed,
    );
  }

  final int generated;
  final int deductible;
  final DateTime due;

  /// "septiembre y octubre".
  final String label;
  final List<Invoice> invoices;

  /// A pagar (nunca negativo: un saldo a favor no se paga).
  int get toPay => (generated - deductible).clamp(0, generated);
}

/// Resumen del negocio en el mes.
@immutable
class BusinessMonth {
  const BusinessMonth({
    required this.income,
    required this.expense,
    required this.receivable,
    required this.overdueCount,
    required this.iva,
  });

  factory BusinessMonth.of(
    List<Invoice> invoices,
    List<Transaction> txs,
    DateTime now,
  ) {
    final month = txs.where(
      (t) =>
          t.ownership == Ownership.business &&
          t.date.year == now.year &&
          t.date.month == now.month,
    );
    int sum(TransactionKind k) =>
        month.where((t) => t.kind == k).fold(0, (s, t) => s + t.amount);
    final open = invoices.where((i) => i.paidOn == null);
    return BusinessMonth(
      income: sum(TransactionKind.income),
      expense: sum(TransactionKind.expense),
      receivable: open.fold(0, (s, i) => s + i.total),
      overdueCount: open
          .where((i) => i.statusAt(now) == InvoiceStatus.overdue)
          .length,
      iva: IvaEstimate.of(invoices, txs, now),
    );
  }

  final int income;
  final int expense;

  /// Lo que te deben (facturas sin pagar).
  final int receivable;
  final int overdueCount;
  final IvaEstimate iva;

  int get profit => income - expense;
}
