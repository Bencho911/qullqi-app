import 'package:flutter/foundation.dart' show immutable;

import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';

/// Porcentaje desde el que un presupuesto avisa ("vas cerca del límite").
const double budgetWarnAt = 0.8;

/// Presupuesto mensual de una categoría.
@immutable
class Budget {
  const Budget({
    required this.id,
    required this.categoryId,
    required this.limit,
    required this.ownership,
  });

  final String id;
  final String categoryId;

  /// Tope del mes en pesos.
  final int limit;
  final Ownership ownership;

  Category get category => Categories.byId(categoryId);

  Budget copyWith({int? limit}) => Budget(
    id: id,
    categoryId: categoryId,
    limit: limit ?? this.limit,
    ownership: ownership,
  );
}

enum BudgetStatus { ok, warning, over }

/// Cómo va un presupuesto en el mes.
@immutable
class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.spent,
    required this.daysLeft,
  });

  final Budget budget;
  final int spent;

  /// Días que quedan del mes, contando hoy.
  final int daysLeft;

  double get ratio => budget.limit == 0 ? 0 : spent / budget.limit;
  int get left => budget.limit - spent;

  BudgetStatus get status => ratio > 1
      ? BudgetStatus.over
      : ratio >= budgetWarnAt
      ? BudgetStatus.warning
      : BudgetStatus.ok;

  /// Lo que puedes gastar por día para no pasarte.
  int get perDay => left <= 0 || daysLeft <= 0 ? 0 : left ~/ daysLeft;
}

/// Días que quedan del mes de [now], contando hoy.
int daysLeftInMonth(DateTime now) {
  final last = DateTime(now.year, now.month + 1, 0).day;
  return last - now.day + 1;
}

/// Gasto del mes en la categoría del presupuesto (solo gastos, en su ámbito).
int spentThisMonth(Budget b, List<Transaction> txs, DateTime now) => txs
    .where(
      (t) =>
          t.kind == TransactionKind.expense &&
          t.categoryId == b.categoryId &&
          t.ownership == b.ownership &&
          t.date.year == now.year &&
          t.date.month == now.month,
    )
    .fold(0, (s, t) => s + t.amount);

BudgetProgress progressOf(Budget b, List<Transaction> txs, DateTime now) =>
    BudgetProgress(
      budget: b,
      spent: spentThisMonth(b, txs, now),
      daysLeft: daysLeftInMonth(now),
    );

/// Un aporte a una meta.
@immutable
class Contribution {
  const Contribution({required this.amount, required this.date});

  final int amount;
  final DateTime date;
}

/// Meta de ahorro.
@immutable
class Goal {
  const Goal({
    required this.id,
    required this.name,
    required this.target,
    required this.ownership,
    required this.contributions,
    this.deadline,
  });

  final String id;
  final String name;
  final int target;
  final Ownership ownership;
  final List<Contribution> contributions;

  /// Fecha para la que se quiere lograr (opcional).
  final DateTime? deadline;

  int get saved => contributions.fold(0, (s, c) => s + c.amount);
  int get missing => (target - saved).clamp(0, target);
  double get ratio => target == 0 ? 0 : (saved / target).clamp(0, 1);
  bool get done => saved >= target;

  Goal withContribution(Contribution c) => Goal(
    id: id,
    name: name,
    target: target,
    ownership: ownership,
    contributions: [c, ...contributions],
    deadline: deadline,
  );
}

/// Promedio mensual de aportes de los últimos 3 meses (el "ritmo").
int monthlyPace(Goal g, DateTime now) {
  final from = DateTime(now.year, now.month - 2);
  final recent = g.contributions
      .where((c) => !c.date.isBefore(from))
      .fold<int>(0, (s, c) => s + c.amount);
  return recent ~/ 3;
}

/// Meses que faltan al ritmo actual. `null` si no hay ritmo (sin aportes).
int? monthsToGoal(Goal g, DateTime now) {
  if (g.done) return 0;
  final pace = monthlyPace(g, now);
  if (pace <= 0) return null;
  return (g.missing / pace).ceil();
}

/// Lo que hay que aportar cada mes para llegar a la fecha. `null` sin fecha.
int? monthlyNeeded(Goal g, DateTime now) {
  final d = g.deadline;
  if (d == null || g.done) return null;
  final months = (d.year - now.year) * 12 + d.month - now.month;
  if (months <= 0) return g.missing;
  return (g.missing / months).ceil();
}

/// Resumen del mes para Reportes.
@immutable
class MonthReport {
  const MonthReport({
    required this.income,
    required this.expense,
    required this.prevIncome,
    required this.prevExpense,
    required this.byCategory,
    required this.topExpenses,
  });

  factory MonthReport.of(
    List<Transaction> txs, {
    required Scope scope,
    required DateTime now,
  }) {
    final prev = DateTime(now.year, now.month - 1);
    bool inMonth(Transaction t, DateTime m) =>
        t.date.year == m.year && t.date.month == m.month;
    final visible = txs.where((t) => t.ownership.visibleIn(scope)).toList();
    int sum(Iterable<Transaction> l, TransactionKind k) =>
        l.where((t) => t.kind == k).fold(0, (s, t) => s + t.amount);
    final thisMonth = visible.where((t) => inMonth(t, now)).toList();
    final lastMonth = visible.where((t) => inMonth(t, prev)).toList();
    final expenses = thisMonth
        .where((t) => t.kind == TransactionKind.expense)
        .toList();
    final byCat = <String, int>{};
    for (final t in expenses) {
      byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amount;
    }
    final ranked = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return MonthReport(
      income: sum(thisMonth, TransactionKind.income),
      expense: sum(thisMonth, TransactionKind.expense),
      prevIncome: sum(lastMonth, TransactionKind.income),
      prevExpense: sum(lastMonth, TransactionKind.expense),
      byCategory: [for (final e in ranked) (Categories.byId(e.key), e.value)],
      topExpenses: ([
        ...expenses,
      ]..sort((a, b) => b.amount.compareTo(a.amount))).take(3).toList(),
    );
  }

  final int income;
  final int expense;
  final int prevIncome;
  final int prevExpense;

  /// Gasto por categoría, de mayor a menor.
  final List<(Category, int)> byCategory;
  final List<Transaction> topExpenses;

  int get saved => income - expense;

  /// Cambio del gasto frente al mes pasado (positivo = gastaste más).
  int get expenseChange => expense - prevExpense;
}
