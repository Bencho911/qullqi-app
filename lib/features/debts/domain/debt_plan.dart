import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

/// En qué orden se paga el dinero extra.
enum DebtStrategy {
  avalanche(
    'Avalancha',
    'Pagas primero la que más interés cobra. Es la que menos te cuesta en '
        'total.',
  ),
  snowball(
    'Bola de nieve',
    'Pagas primero la más pequeña. Cierras deudas rápido y ganas impulso.',
  );

  DebtStrategy(this.label, this.description);

  final String label;
  final String description;
}

/// Una deuda con lo necesario para planear su pago.
@immutable
class DebtInput {
  const DebtInput({
    required this.id,
    required this.name,
    required this.balance,
    required this.annualRate,
    required this.minimum,
  });

  final String id;
  final String name;

  /// Lo que debes hoy.
  final int balance;

  /// Tasa efectiva anual como fracción (0.27 = 27 % e. a.).
  final double annualRate;

  /// Pago mínimo mensual.
  final int minimum;
}

/// En qué mes queda en cero cada deuda.
@immutable
class DebtPayoff {
  const DebtPayoff({required this.id, required this.name, required this.month});

  final String id;
  final String name;

  /// Mes 1 es el primero desde hoy.
  final int month;
}

/// Resultado de simular el pago de las deudas.
@immutable
class DebtResult {
  const DebtResult({
    required this.months,
    required this.totalInterest,
    required this.totalPaid,
    required this.payoffs,
    required this.completed,
  });

  /// Meses hasta quedar sin deudas (o hasta el tope si [completed] es false).
  final int months;
  final int totalInterest;
  final int totalPaid;
  final List<DebtPayoff> payoffs;

  /// `false`: con ese pago las deudas no se terminan de pagar.
  final bool completed;
}

/// Tope de la simulación: 50 años.
const int debtMaxMonths = 600;

double _monthlyRate(double annual) =>
    math.pow(1 + annual, 1 / 12).toDouble() - 1;

/// Suma de los pagos mínimos.
int totalMinimums(List<DebtInput> debts) =>
    debts.fold(0, (s, d) => s + d.minimum);

/// Simula mes a mes cuánto tardas y cuánto pagas en intereses.
///
/// Con [redirectFreed] el dinero que deja libre una deuda ya pagada pasa a la
/// siguiente (el plan). Sin él, cada deuda recibe solo su mínimo (lo que pasa
/// si no haces nada más).
DebtResult simulateDebtPlan({
  required List<DebtInput> debts,
  required int monthlyPayment,
  required DebtStrategy strategy,
  bool redirectFreed = true,
}) {
  final active = [...debts.where((d) => d.balance > 0)];
  if (active.isEmpty) {
    return const DebtResult(
      months: 0,
      totalInterest: 0,
      totalPaid: 0,
      payoffs: [],
      completed: true,
    );
  }
  final balance = {for (final d in active) d.id: d.balance.toDouble()};
  final rate = {for (final d in active) d.id: _monthlyRate(d.annualRate)};
  final budget = math.max(monthlyPayment, totalMinimums(active)).toDouble();
  final payoffs = <DebtPayoff>[];
  var interest = 0.0;
  var paid = 0.0;

  bool open(DebtInput d) => balance[d.id]! > 0.5;

  for (var month = 1; month <= debtMaxMonths; month++) {
    // 1. Los intereses del mes.
    for (final d in active.where(open)) {
      final i = balance[d.id]! * rate[d.id]!;
      balance[d.id] = balance[d.id]! + i;
      interest += i;
    }
    // 2. Los mínimos.
    var available = redirectFreed
        ? budget
        : active.where(open).fold<double>(0, (s, d) => s + d.minimum);
    for (final d in active.where(open)) {
      final pay = math.min(balance[d.id]!, d.minimum.toDouble());
      balance[d.id] = balance[d.id]! - pay;
      available -= pay;
      paid += pay;
    }
    // 3. Lo que sobra, a la deuda que toca primero.
    if (redirectFreed) {
      final order = active.where(open).toList()
        ..sort(
          (a, b) => switch (strategy) {
            DebtStrategy.avalanche => b.annualRate.compareTo(a.annualRate),
            DebtStrategy.snowball => balance[a.id]!.compareTo(balance[b.id]!),
          },
        );
      for (final d in order) {
        if (available <= 0) break;
        final pay = math.min(balance[d.id]!, available);
        balance[d.id] = balance[d.id]! - pay;
        available -= pay;
        paid += pay;
      }
    }
    // 4. Las que quedaron en cero.
    for (final d in active) {
      if (!open(d) && payoffs.every((p) => p.id != d.id)) {
        payoffs.add(DebtPayoff(id: d.id, name: d.name, month: month));
      }
    }
    if (active.every((d) => !open(d))) {
      return DebtResult(
        months: month,
        totalInterest: interest.round(),
        totalPaid: paid.round(),
        payoffs: payoffs,
        completed: true,
      );
    }
  }
  return DebtResult(
    months: debtMaxMonths,
    totalInterest: interest.round(),
    totalPaid: paid.round(),
    payoffs: payoffs,
    completed: false,
  );
}
