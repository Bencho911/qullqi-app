import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/home/domain/home_data.dart';
import 'package:inti/features/home/domain/money_summary.dart';

/// Un pago próximo tal como lo muestra un widget.
@immutable
class WidgetPayment {
  const WidgetPayment({
    required this.title,
    required this.daysLeft,
    this.amount,
  });

  final String title;

  /// `null` cuando la persona eligió ocultar los montos.
  final int? amount;

  /// Negativo: ya venció.
  final int daysLeft;

  Map<String, Object?> toJson() => {
    'title': title,
    'amount': amount,
    'daysLeft': daysLeft,
  };
}

/// Lo que ven los widgets, los atajos y Siri. Es una foto pequeña y
/// autosuficiente: el widget no entra a la app ni consulta nada más.
@immutable
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.updatedAt,
    required this.firstName,
    required this.scopeLabel,
    required this.amountsHidden,
    required this.runsShort,
    required this.unread,
    required this.payments,
    this.available,
    this.perDay,
    this.netWorth,
  });

  /// Versión del formato: el widget la revisa antes de leer.
  static const int version = 1;

  final DateTime updatedAt;
  final String firstName;

  /// "Todo", "Personal" o "Negocio".
  final String scopeLabel;

  /// Los montos van en `null`: se muestra "Abre Inti".
  final bool amountsHidden;
  final bool runsShort;
  final int unread;
  final List<WidgetPayment> payments;
  final int? available;
  final int? perDay;
  final int? netWorth;

  Map<String, Object?> toJson() => {
    'version': version,
    'updatedAt': updatedAt.toIso8601String(),
    'firstName': firstName,
    'scopeLabel': scopeLabel,
    'amountsHidden': amountsHidden,
    'runsShort': runsShort,
    'unread': unread,
    'available': available,
    'perDay': perDay,
    'netWorth': netWorth,
    'payments': [for (final p in payments) p.toJson()],
  };

  String encode() => jsonEncode(toJson());
}

/// Cuántos pagos caben en un widget.
const int widgetPaymentCount = 3;

/// Pagos que se muestran: los de los próximos 30 días, del más cercano.
WidgetSnapshot buildWidgetSnapshot({
  required HomeData data,
  required int unread,
  required String firstName,
  required bool showAmounts,
}) {
  final soon = data.summary.payments
      .where(
        (p) => daysBetween(data.now, p.due) <= MoneySummary.horizonDaysDefault,
      )
      .take(widgetPaymentCount);
  return WidgetSnapshot(
    updatedAt: data.now,
    firstName: firstName,
    scopeLabel: switch (data.scope) {
      Scope.all => 'Todo',
      Scope.personal => 'Personal',
      Scope.business => 'Negocio',
    },
    amountsHidden: !showAmounts,
    runsShort: data.forecast.runsShort,
    unread: unread,
    available: showAmounts ? data.summary.available : null,
    perDay: showAmounts ? data.forecast.perDay : null,
    netWorth: showAmounts ? data.summary.netWorth : null,
    payments: [
      for (final p in soon)
        WidgetPayment(
          title: p.title,
          amount: showAmounts ? p.amount : null,
          daysLeft: daysBetween(data.now, p.due),
        ),
    ],
  );
}
