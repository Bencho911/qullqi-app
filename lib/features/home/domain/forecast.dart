import 'package:flutter/foundation.dart' show immutable;

import 'package:inti/core/clock/clock.dart';
import 'package:inti/features/home/domain/money_summary.dart';
import 'package:inti/features/planning/domain/plans.dart'
    show daysLeftInMonth;
import 'package:inti/features/recurring/domain/recurring.dart';
import 'package:inti/features/transactions/domain/transaction.dart';

/// Días hacia atrás con que se calcula el gasto típico.
const int forecastWindowDays = 30;

/// Cómo va el mes: cuánto puedes gastar por día y cuánto tendrías al final.
///
/// Es una estimación con tus últimos 30 días; los pagos fijos y los cobros
/// recurrentes ya van aparte, para no contarlos dos veces.
@immutable
class MonthForecast {
  const MonthForecast({
    required this.daysLeft,
    required this.dueThisMonth,
    required this.free,
    required this.perDay,
    required this.typicalDaily,
    required this.projectedEnd,
  });

  factory MonthForecast.compute({
    required MoneySummary summary,
    required List<Transaction> transactions,
    required Set<String> fixedKeys,
    required DateTime now,
  }) {
    final daysLeft = daysLeftInMonth(now);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);
    final due = summary.payments
        .where((p) => !dateOnly(p.due).isAfter(endOfMonth))
        .fold<int>(0, (s, p) => s + p.amount);
    final free = summary.liquid - due;

    bool isFixed(String title) {
      final k = recurringKey(title);
      if (k.isEmpty) return false;
      return fixedKeys.any(
        (f) => f.isNotEmpty && (k.contains(f) || f.contains(k)),
      );
    }

    final spent = transactions
        .where(
          (t) =>
              t.kind == TransactionKind.expense &&
              !t.needsReview &&
              daysBetween(t.date, now) >= 0 &&
              daysBetween(t.date, now) < forecastWindowDays &&
              !isFixed(t.title),
        )
        .fold<int>(0, (s, t) => s + t.amount);
    final typical = spent ~/ forecastWindowDays;
    return MonthForecast(
      daysLeft: daysLeft,
      dueThisMonth: due,
      free: free,
      perDay: free > 0 ? free ~/ daysLeft : 0,
      typicalDaily: typical,
      projectedEnd: free - typical * (daysLeft - 1),
    );
  }

  /// Días que quedan del mes, contando hoy.
  final int daysLeft;

  /// Pagos que vencen antes de fin de mes.
  final int dueThisMonth;

  /// Lo que tienes menos esos pagos.
  final int free;

  /// Lo que puedes gastar por día sin quedarte corto.
  final int perDay;

  /// Lo que sueles gastar por día (sin pagos fijos ni recurrentes).
  final int typicalDaily;

  /// Lo que tendrías al terminar el mes si sigues así.
  final int projectedEnd;

  bool get runsShort => projectedEnd < 0;
}
