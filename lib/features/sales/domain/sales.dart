import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/features/business/domain/business.dart' show ivaRate;

// ---------------------------------------------------------------------------
// Cotizaciones
// ---------------------------------------------------------------------------

enum QuoteStatus {
  draft('Borrador'),
  sent('Enviada'),
  accepted('Aceptada'),
  rejected('Rechazada'),
  expired('Vencida');

  QuoteStatus(this.label);

  final String label;
}

/// Un renglón de una cotización.
@immutable
class QuoteLine {
  const QuoteLine({required this.description, required this.amount});

  final String description;

  /// Valor del renglón antes de IVA.
  final int amount;
}

/// Propuesta de precio a un cliente.
@immutable
class Quote {
  const Quote({
    required this.id,
    required this.client,
    required this.number,
    required this.lines,
    required this.chargesIva,
    required this.issued,
    required this.validUntil,
    required this.status,
    this.invoiceId,
  });

  final String id;
  final String client;

  /// "C-0003".
  final String number;
  final List<QuoteLine> lines;
  final bool chargesIva;
  final DateTime issued;
  final DateTime validUntil;
  final QuoteStatus status;

  /// Factura en que se convirtió, si la aceptó.
  final String? invoiceId;

  int get base => lines.fold(0, (s, l) => s + l.amount);
  int get iva => chargesIva ? (base * ivaRate).round() : 0;
  int get total => base + iva;

  /// Una cotización enviada que pasó su fecha queda vencida.
  QuoteStatus statusAt(DateTime now) =>
      status == QuoteStatus.sent && daysBetween(now, validUntil) < 0
      ? QuoteStatus.expired
      : status;

  Quote copyWith({QuoteStatus? status, String? invoiceId}) => Quote(
    id: id,
    client: client,
    number: number,
    lines: lines,
    chargesIva: chargesIva,
    issued: issued,
    validUntil: validUntil,
    status: status ?? this.status,
    invoiceId: invoiceId ?? this.invoiceId,
  );
}

// ---------------------------------------------------------------------------
// Facturas recurrentes
// ---------------------------------------------------------------------------

/// Plantilla de una factura que se emite todos los meses.
@immutable
class InvoiceTemplate {
  const InvoiceTemplate({
    required this.id,
    required this.client,
    required this.concept,
    required this.base,
    required this.chargesIva,
    required this.dayOfMonth,
    required this.termDays,
    this.active = true,
    this.lastIssued,
  });

  final String id;
  final String client;
  final String concept;
  final int base;
  final bool chargesIva;

  /// Día del mes en que se emite (1 a 28).
  final int dayOfMonth;

  /// Días que tiene el cliente para pagar.
  final int termDays;
  final bool active;
  final DateTime? lastIssued;

  int get iva => chargesIva ? (base * ivaRate).round() : 0;
  int get total => base + iva;

  bool issuedThisMonth(DateTime now) =>
      lastIssued != null &&
      lastIssued!.year == now.year &&
      lastIssued!.month == now.month;

  /// La próxima fecha de emisión: este mes si aún no pasa y no se emitió, y
  /// si no, el mes siguiente.
  DateTime nextIssue(DateTime now) {
    final today = dateOnly(now);
    DateTime inMonth(int offset) {
      final first = DateTime(now.year, now.month + offset);
      final last = DateTime(first.year, first.month + 1, 0).day;
      return DateTime(first.year, first.month, math.min(dayOfMonth, last));
    }

    final thisMonth = inMonth(0);
    return !issuedThisMonth(now) && !thisMonth.isBefore(today)
        ? thisMonth
        : inMonth(1);
  }

  InvoiceTemplate copyWith({bool? active, DateTime? lastIssued}) =>
      InvoiceTemplate(
        id: id,
        client: client,
        concept: concept,
        base: base,
        chargesIva: chargesIva,
        dayOfMonth: dayOfMonth,
        termDays: termDays,
        active: active ?? this.active,
        lastIssued: lastIssued ?? this.lastIssued,
      );
}

// ---------------------------------------------------------------------------
// Enlaces de pago
// ---------------------------------------------------------------------------

enum PaymentLinkStatus {
  active('Activo'),
  paid('Pagado'),
  expired('Vencido'),
  cancelled('Cancelado');

  PaymentLinkStatus(this.label);

  final String label;
}

/// Enlace con el que un cliente te paga. El cobro lo procesa un aliado de
/// pagos; Qullqi no guarda datos de tarjetas.
@immutable
class PaymentLink {
  const PaymentLink({
    required this.id,
    required this.concept,
    required this.amount,
    required this.createdAt,
    required this.expiresAt,
    required this.status,
    required this.url,
    this.client,
    this.invoiceId,
  });

  final String id;
  final String concept;
  final int amount;
  final DateTime createdAt;
  final DateTime expiresAt;
  final PaymentLinkStatus status;
  final String url;
  final String? client;

  /// Factura que cobra, si es de una.
  final String? invoiceId;

  /// Un enlace activo que pasó su fecha queda vencido.
  PaymentLinkStatus statusAt(DateTime now) =>
      status == PaymentLinkStatus.active && daysBetween(now, expiresAt) < 0
      ? PaymentLinkStatus.expired
      : status;

  PaymentLink copyWith({PaymentLinkStatus? status}) => PaymentLink(
    id: id,
    concept: concept,
    amount: amount,
    createdAt: createdAt,
    expiresAt: expiresAt,
    status: status ?? this.status,
    url: url,
    client: client,
    invoiceId: invoiceId,
  );
}
