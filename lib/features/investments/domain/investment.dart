import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show IconData, Icons;

import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/money/money.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/accounts/domain/account.dart';

/// Tipos de inversión que la persona puede registrar o conectar.
enum InvestmentKind {
  cdt('CDT', 'Certificado de depósito a término', Icons.savings_outlined),
  fund(
    'Fondo de inversión',
    'Fondos de inversión colectiva y fiducias',
    Icons.pie_chart_outline_rounded,
  ),
  stock(
    'Acciones y ETF',
    'Acciones, ETF y otros valores en bolsa',
    Icons.show_chart_rounded,
  ),
  crypto('Cripto', 'Bitcoin y otras criptomonedas', Icons.currency_bitcoin),
  pension(
    'Pensión voluntaria',
    'Aportes voluntarios a pensión o cesantías',
    Icons.beach_access_outlined,
  ),
  other('Otra', 'Cualquier otra inversión', Icons.account_balance_outlined);

  InvestmentKind(this.label, this.description, this.icon);

  final String label;
  final String description;
  final IconData icon;
}

/// Una inversión: lo que pusiste, lo que vale hoy y de dónde sale el dato.
@immutable
class Investment {
  const Investment({
    required this.id,
    required this.name,
    required this.kind,
    required this.ownership,
    required this.invested,
    required this.value,
    required this.openedOn,
    required this.status,
    required this.lastSync,
    this.institution,
    this.badge,
    this.maturity,
    this.annualRate,
  });

  final String id;
  final String name;
  final InvestmentKind kind;
  final Ownership ownership;

  /// Lo que pusiste en pesos (el capital).
  final int invested;

  /// Lo que vale hoy en pesos.
  final int value;
  final DateTime openedOn;

  /// `connected` (viene de la entidad), `needsReconnect` o `manual`.
  final ConnectionStatus status;

  /// Última vez que se actualizó el valor.
  final DateTime lastSync;

  /// Entidad donde está ("Bancolombia"); `null` si la registraste a mano.
  final String? institution;
  final String? badge;

  /// Vencimiento (CDT).
  final DateTime? maturity;

  /// Tasa efectiva anual como fracción (0.098 = 9,8 % e. a.).
  final double? annualRate;

  bool get isManual => status == ConnectionStatus.manual;
  bool get needsReconnect => status == ConnectionStatus.needsReconnect;

  /// Ganancia (o pérdida, si es negativa) en pesos.
  int get gain => value - invested;

  /// Rentabilidad sobre lo puesto: 0.063 = 6,3 %.
  double get returnRatio => invested <= 0 ? 0 : gain / invested;

  /// Días que faltan para el vencimiento; negativo si ya pasó.
  int? daysToMaturity(DateTime now) =>
      maturity == null ? null : daysBetween(now, maturity!);

  /// "Bancolombia" o el nombre si no hay entidad.
  String get place => institution ?? name;

  String get initials {
    if (badge != null) return badge!;
    final words = place.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length == 1) {
      final w = words.first;
      return (w.length < 2 ? w : w.substring(0, 2)).toUpperCase();
    }
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }

  Investment copyWith({
    int? value,
    ConnectionStatus? status,
    DateTime? lastSync,
  }) => Investment(
    id: id,
    name: name,
    kind: kind,
    ownership: ownership,
    invested: invested,
    value: value ?? this.value,
    openedOn: openedOn,
    status: status ?? this.status,
    lastSync: lastSync ?? this.lastSync,
    institution: institution,
    badge: badge,
    maturity: maturity,
    annualRate: annualRate,
  );
}

/// Qué parte del portafolio es de un tipo.
@immutable
class KindShare {
  const KindShare({
    required this.kind,
    required this.value,
    required this.ratio,
  });

  final InvestmentKind kind;
  final int value;

  /// 0 a 1 sobre el total.
  final double ratio;
}

/// Resumen de un conjunto de inversiones.
@immutable
class Portfolio {
  const Portfolio({
    required this.items,
    required this.value,
    required this.invested,
    required this.byKind,
  });

  factory Portfolio.of(Iterable<Investment> items) {
    final list = items.toList();
    final value = list.fold<int>(0, (s, i) => s + i.value);
    final invested = list.fold<int>(0, (s, i) => s + i.invested);
    final totals = <InvestmentKind, int>{};
    for (final i in list) {
      totals[i.kind] = (totals[i.kind] ?? 0) + i.value;
    }
    final shares = [
      for (final e in totals.entries)
        KindShare(
          kind: e.key,
          value: e.value,
          ratio: value <= 0 ? 0 : e.value / value,
        ),
    ]..sort((a, b) => b.value.compareTo(a.value));
    return Portfolio(
      items: list,
      value: value,
      invested: invested,
      byKind: shares,
    );
  }

  final List<Investment> items;
  final int value;
  final int invested;

  /// De mayor a menor.
  final List<KindShare> byKind;

  bool get isEmpty => items.isEmpty;
  int get gain => value - invested;
  double get returnRatio => invested <= 0 ? 0 : gain / invested;
}

/// "+4,3 %" o "-6,3 %": la rentabilidad con signo y una cifra decimal.
String signedPercent(double ratio) {
  final pct = ratio * 100;
  final text = Cop.percent(pct.abs(), decimals: 1);
  if (text.startsWith('0,0')) return text;
  return pct < 0 ? '-$text' : '+$text';
}

// ---------------------------------------------------------------------------
// Simulador: cuánto podría crecer lo que aportas. Es una estimación con una
// tasa que elige la persona; nunca una promesa de rentabilidad.
// ---------------------------------------------------------------------------

/// Tasa mensual equivalente a una tasa efectiva anual (0.08 → ~0.0064).
double monthlyRate(double annualRate) =>
    math.pow(1 + annualRate, 1 / 12).toDouble() - 1;

/// Resultado de una proyección.
@immutable
class Projection {
  const Projection({
    required this.initial,
    required this.monthly,
    required this.months,
    required this.finalValue,
  });

  final int initial;
  final int monthly;
  final int months;

  /// Lo que tendrías al final del plazo.
  final int finalValue;

  /// Lo que habrías puesto de tu bolsillo.
  int get contributed => initial + monthly * months;

  /// Lo que rendiría.
  int get earned => finalValue - contributed;
}

/// Valor al cabo de [months] meses, con aporte al final de cada mes.
double _grow({
  required int initial,
  required int monthly,
  required int months,
  required double annualRate,
}) {
  final r = monthlyRate(annualRate);
  var v = initial.toDouble();
  for (var m = 0; m < months; m++) {
    v = v * (1 + r) + monthly;
  }
  return v;
}

/// Proyecta cuánto tendrías.
Projection projectGrowth({
  required int initial,
  required int monthly,
  required int months,
  required double annualRate,
}) {
  final v = _grow(
    initial: initial,
    monthly: monthly,
    months: months,
    annualRate: annualRate,
  );
  return Projection(
    initial: initial,
    monthly: monthly,
    months: months,
    finalValue: v.round(),
  );
}

/// Valor al final de cada año del plazo (para ver cómo crece).
List<int> yearlyValues({
  required int initial,
  required int monthly,
  required int years,
  required double annualRate,
}) => [
  for (var y = 1; y <= years; y++)
    _grow(
      initial: initial,
      monthly: monthly,
      months: y * 12,
      annualRate: annualRate,
    ).round(),
];

/// Meses que tardas en llegar a [target]. `null` si no llegas en 50 años
/// (por ejemplo, sin aportes ni rendimiento).
int? monthsToReach({
  required int target,
  required int initial,
  required int monthly,
  required double annualRate,
  int maxMonths = 600,
}) {
  if (initial >= target) return 0;
  final r = monthlyRate(annualRate);
  var v = initial.toDouble();
  for (var m = 1; m <= maxMonths; m++) {
    v = v * (1 + r) + monthly;
    if (v >= target) return m;
  }
  return null;
}

/// Cuánto aportar al mes para llegar a [target] en [months] meses.
int monthlyForTarget({
  required int target,
  required int initial,
  required int months,
  required double annualRate,
}) {
  if (months <= 0) return math.max(0, target - initial);
  final r = monthlyRate(annualRate);
  final g = math.pow(1 + r, months).toDouble();
  final needed = target - initial * g;
  if (needed <= 0) return 0;
  final perMonth = r == 0 ? needed / months : needed * r / (g - 1);
  return perMonth.ceil();
}
