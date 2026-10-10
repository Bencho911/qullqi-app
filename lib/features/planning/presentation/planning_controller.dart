import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/scope/scope_provider.dart';
import 'package:qullqi/features/planning/data/plans_repository.dart';
import 'package:qullqi/features/planning/domain/plans.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';

enum PlanningSection {
  budgets('Presupuestos'),
  goals('Metas'),
  reports('Reportes');

  PlanningSection(this.label);

  final String label;
}

/// Sección abierta de Planes (se recuerda al cambiar de pestaña).
final planningSectionProvider =
    NotifierProvider<PlanningSectionNotifier, PlanningSection>(
      PlanningSectionNotifier.new,
    );

class PlanningSectionNotifier extends Notifier<PlanningSection> {
  @override
  PlanningSection build() => PlanningSection.budgets;

  // Los notifiers de Riverpod exponen el cambio como método, no como setter.
  // ignore: use_setters_to_change_properties
  void set(PlanningSection s) => state = s;
}

/// Lo que muestra Planes para la vista activa.
@immutable
class PlanningView {
  const PlanningView({
    required this.now,
    required this.scope,
    required this.budgets,
    required this.goals,
    required this.report,
    required this.transactions,
  });

  final DateTime now;
  final Scope scope;
  final List<BudgetProgress> budgets;
  final List<Goal> goals;
  final MonthReport report;
  final List<Transaction> transactions;

  int get budgeted => budgets.fold(0, (s, b) => s + b.budget.limit);
  int get spent => budgets.fold(0, (s, b) => s + b.spent);
}

final planningViewProvider = Provider<AsyncValue<PlanningView>>((ref) {
  final budgets = ref.watch(budgetsProvider);
  final goals = ref.watch(goalsProvider);
  final txs = ref.watch(transactionsProvider);
  final scope = ref.watch(scopeProvider);
  final now = ref.watch(clockProvider)();
  for (final v in [budgets, goals, txs]) {
    if (v.hasError) return AsyncError(v.error!, v.stackTrace!);
  }
  if (!budgets.hasValue || !goals.hasValue || !txs.hasValue) {
    return const AsyncLoading();
  }
  final list = txs.requireValue;
  return AsyncData(
    PlanningView(
      now: now,
      scope: scope,
      budgets:
          budgets.requireValue
              .where((b) => b.ownership.visibleIn(scope))
              .map((b) => progressOf(b, list, now))
              .toList()
            // Primero lo que necesita atención.
            ..sort((a, b) => b.ratio.compareTo(a.ratio)),
      goals: goals.requireValue
          .where((g) => g.ownership.visibleIn(scope))
          .toList(),
      report: MonthReport.of(list, scope: scope, now: now),
      transactions: list,
    ),
  );
});
