import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/scope/scope.dart';

/// Lo que valía tu patrimonio un día.
@immutable
class NetWorthPoint {
  const NetWorthPoint(this.date, this.value);

  final DateTime date;
  final int value;
}

/// Rangos de la gráfica.
enum HistoryRange {
  month('1 mes', 30),
  quarter('3 meses', 90),
  year('1 año', 365);

  HistoryRange(this.label, this.days);

  final String label;
  final int days;
}

/// Una foto por día del patrimonio de cada ámbito. El backend las guardará;
/// hasta entonces se arman con los saldos de hoy.
@immutable
class NetWorthHistory {
  const NetWorthHistory({required this.personal, required this.business});

  final List<NetWorthPoint> personal;
  final List<NetWorthPoint> business;

  /// La serie de la vista activa (en Todo, la suma día a día).
  List<NetWorthPoint> forScope(Scope scope) => switch (scope) {
    Scope.personal => personal,
    Scope.business => business,
    Scope.all => [
      for (var i = 0; i < personal.length; i++)
        NetWorthPoint(
          personal[i].date,
          personal[i].value + (i < business.length ? business[i].value : 0),
        ),
    ],
  };
}

/// Los últimos [days] días de una serie (más el día de partida).
List<NetWorthPoint> lastDays(List<NetWorthPoint> points, int days) =>
    points.length <= days + 1
    ? points
    : points.sublist(points.length - days - 1);

/// Cuánto cambió entre el primer y el último punto.
int changeOf(List<NetWorthPoint> points) =>
    points.length < 2 ? 0 : points.last.value - points.first.value;

/// Cambio como fracción del valor de partida (0.058 = +5,8 %).
double changeRatio(List<NetWorthPoint> points) {
  if (points.length < 2 || points.first.value == 0) return 0;
  return changeOf(points) / points.first.value.abs();
}

/// Historia de demostración: crece de forma pareja hacia el valor de hoy,
/// con altibajos pequeños y deterministas. El último día es exactamente el
/// valor actual.
NetWorthHistory buildDemoHistory({
  required int personalNow,
  required int businessNow,
  required DateTime now,
  int days = 365,
}) {
  final today = dateOnly(now);
  List<NetWorthPoint> series(int current, double startFactor, double phase) => [
    for (var i = 0; i <= days; i++)
      NetWorthPoint(today.subtract(Duration(days: days - i)), () {
        final p = i / days;
        final trend = startFactor + (1 - startFactor) * p;
        final wobble =
            (0.012 * math.sin(i / 6 + phase) +
                0.006 * math.sin(i / 2.3 + phase)) *
            (1 - p * p);
        return (current * (trend + wobble)).round();
      }()),
  ];
  return NetWorthHistory(
    personal: series(personalNow, 0.74, 0),
    business: series(businessNow, 0.86, 1.7),
  );
}
