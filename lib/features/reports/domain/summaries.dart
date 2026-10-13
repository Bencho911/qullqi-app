import 'package:flutter/foundation.dart' show immutable;

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';

/// Resumen de un periodo: qué entró, qué salió y en qué se fue.
@immutable
class PeriodSummary {
  const PeriodSummary({
    required this.title,
    required this.start,
    required this.end,
    required this.income,
    required this.expense,
    required this.previousExpense,
    required this.byCategory,
    required this.biggest,
    required this.count,
  });

  /// Del [start] al [end], ambos incluidos, contra el periodo anterior
  /// ([prevStart] a [prevEnd]). Los traslados y los movimientos por revisar
  /// no cuentan: no son gastos ni ingresos.
  factory PeriodSummary.of(
    List<Transaction> all, {
    required String title,
    required DateTime start,
    required DateTime end,
    required DateTime prevStart,
    required DateTime prevEnd,
    required Scope scope,
  }) {
    bool within(Transaction t, DateTime a, DateTime b) {
      final d = dateOnly(t.date);
      return !d.isBefore(a) && !d.isAfter(b);
    }

    final counted = all.where(
      (t) =>
          t.kind != TransactionKind.transfer &&
          !t.needsReview &&
          t.ownership.visibleIn(scope),
    );
    final mine = counted.where((t) => within(t, start, end)).toList();
    final expenses = mine
        .where((t) => t.kind == TransactionKind.expense)
        .toList();
    final byCat = <String, int>{};
    for (final t in expenses) {
      byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amount;
    }
    final ranked = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return PeriodSummary(
      title: title,
      start: start,
      end: end,
      income: mine
          .where((t) => t.kind == TransactionKind.income)
          .fold(0, (s, t) => s + t.amount),
      expense: expenses.fold(0, (s, t) => s + t.amount),
      previousExpense: counted
          .where(
            (t) =>
                t.kind == TransactionKind.expense &&
                within(t, prevStart, prevEnd),
          )
          .fold(0, (s, t) => s + t.amount),
      byCategory: [for (final e in ranked) (Categories.byId(e.key), e.value)],
      biggest: ([
        ...expenses,
      ]..sort((a, b) => b.amount.compareTo(a.amount))).take(3).toList(),
      count: mine.length,
    );
  }

  final String title;
  final DateTime start;
  final DateTime end;
  final int income;
  final int expense;
  final int previousExpense;

  /// Gasto por categoría, de mayor a menor.
  final List<(Category, int)> byCategory;

  /// Los tres gastos más grandes.
  final List<Transaction> biggest;

  /// Movimientos que cuentan en el periodo.
  final int count;

  int get saved => income - expense;

  /// Positivo: gastaste más que en el periodo anterior.
  int get expenseChange => expense - previousExpense;

  /// "18 al 24 de octubre" o "1 de octubre al 3 de noviembre".
  String get range {
    if (start.month == end.month && start.year == end.year) {
      return '${start.day} al ${Dates.dayMonth(end)}';
    }
    return '${Dates.dayMonth(start)} al ${Dates.dayMonth(end)}';
  }
}

/// Los últimos 7 días (hoy incluido) contra los 7 anteriores.
PeriodSummary lastSevenDays(List<Transaction> all, DateTime now, Scope scope) {
  final today = dateOnly(now);
  return PeriodSummary.of(
    all,
    title: 'Últimos 7 días',
    start: today.subtract(const Duration(days: 6)),
    end: today,
    prevStart: today.subtract(const Duration(days: 13)),
    prevEnd: today.subtract(const Duration(days: 7)),
    scope: scope,
  );
}

/// El mes de [month] (hasta hoy si es el actual) contra el mes anterior.
PeriodSummary monthSummary(
  List<Transaction> all,
  DateTime month,
  DateTime now,
  Scope scope,
) {
  final today = dateOnly(now);
  final first = DateTime(month.year, month.month);
  final last = DateTime(month.year, month.month + 1, 0);
  final isCurrent = month.year == now.year && month.month == now.month;
  final prevFirst = DateTime(month.year, month.month - 1);
  return PeriodSummary.of(
    all,
    title: isCurrent ? 'Este mes' : 'Cierre de ${Dates.month(month)}',
    start: first,
    end: isCurrent ? today : last,
    prevStart: prevFirst,
    prevEnd: DateTime(month.year, month.month, 0),
    scope: scope,
  );
}

/// Texto para mandar por WhatsApp o por correo.
String summaryText(PeriodSummary s) {
  final b = StringBuffer()
    ..writeln('${s.title} (${s.range})')
    ..writeln('Ingresos: ${Cop.format(s.income)}')
    ..writeln('Gastos: ${Cop.format(s.expense)}')
    ..writeln(
      s.saved >= 0
          ? 'Te sobró: ${Cop.format(s.saved)}'
          : 'Gastaste de más: ${Cop.format(-s.saved)}',
    );
  final change = s.expenseChange;
  if (s.previousExpense > 0 && change != 0) {
    b.writeln(
      change > 0
          ? 'Gastaste ${Cop.format(change)} más que el periodo anterior.'
          : 'Gastaste ${Cop.format(-change)} menos que el periodo anterior.',
    );
  }
  if (s.byCategory.isNotEmpty) {
    b
      ..writeln()
      ..writeln('En qué se fue:');
    for (final (cat, amount) in s.byCategory.take(5)) {
      b.writeln('- ${cat.name}: ${Cop.format(amount)}');
    }
  }
  if (s.biggest.isNotEmpty) {
    b
      ..writeln()
      ..writeln('Gastos más grandes:');
    for (final t in s.biggest) {
      b.writeln('- ${t.title}: ${Cop.format(t.amount)}');
    }
  }
  return b.toString().trimRight();
}
