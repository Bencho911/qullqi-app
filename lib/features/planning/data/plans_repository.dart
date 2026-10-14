import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/data/latency.dart';
import 'package:inti/core/data/live_stream.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/planning/domain/plans.dart';

/// Presupuestos y metas de la persona.
abstract interface class PlansRepository {
  Stream<List<Budget>> watchBudgets();
  Stream<List<Goal>> watchGoals();

  Future<Budget> saveBudget({
    required String categoryId,
    required int limit,
    required Ownership ownership,
    String? id,
  });
  Future<void> deleteBudget(String id);

  Future<Goal> createGoal({
    required String name,
    required int target,
    required Ownership ownership,
    DateTime? deadline,
  });

  /// Separa plata para la meta. La plata sigue en tu cuenta: es un
  /// compromiso contigo, no un movimiento.
  Future<void> contribute(String goalId, int amount);
  Future<void> deleteGoal(String id);
}

final plansRepositoryProvider = Provider<PlansRepository>((ref) {
  final repo = MockPlansRepository(
    now: ref.watch(clockProvider),
    latency: ref.watch(mockLatencyProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final budgetsProvider = StreamProvider<List<Budget>>(
  (ref) => ref.watch(plansRepositoryProvider).watchBudgets(),
);

final goalsProvider = StreamProvider<List<Goal>>(
  (ref) => ref.watch(plansRepositoryProvider).watchGoals(),
);

class MockPlansRepository implements PlansRepository {
  MockPlansRepository({required this.now, required this.latency})
    : _goals = _seedGoals(now());

  final DateTime Function() now;
  final Duration latency;
  int _seq = 0;

  List<Budget> _budgets = const [
    Budget(
      id: 'b-mercado',
      categoryId: 'mercado',
      limit: 100000,
      ownership: Ownership.personal,
    ),
    Budget(
      id: 'b-transporte',
      categoryId: 'transporte',
      limit: 150000,
      ownership: Ownership.personal,
    ),
    Budget(
      id: 'b-salidas',
      categoryId: 'salidas',
      limit: 20000,
      ownership: Ownership.personal,
    ),
    Budget(
      id: 'b-suscripciones',
      categoryId: 'suscripciones',
      limit: 30000,
      ownership: Ownership.personal,
    ),
    Budget(
      id: 'b-software',
      categoryId: 'software',
      limit: 150000,
      ownership: Ownership.business,
    ),
  ];
  List<Goal> _goals;

  final _budgetChanges = StreamController<List<Budget>>.broadcast();
  final _goalChanges = StreamController<List<Goal>>.broadcast();

  @override
  Stream<List<Budget>> watchBudgets() => liveStream(
    changes: _budgetChanges.stream,
    current: () => _budgets,
    latency: latency,
  );

  @override
  Stream<List<Goal>> watchGoals() => liveStream(
    changes: _goalChanges.stream,
    current: () => _goals,
    latency: latency,
  );

  @override
  Future<Budget> saveBudget({
    required String categoryId,
    required int limit,
    required Ownership ownership,
    String? id,
  }) async {
    await Future<void>.delayed(latency ~/ 2);
    final budget = Budget(
      id: id ?? 'b-${_seq++}',
      categoryId: categoryId,
      limit: limit,
      ownership: ownership,
    );
    final exists = _budgets.any((b) => b.id == budget.id);
    _budgets = exists
        ? [
            for (final b in _budgets)
              if (b.id == budget.id) budget else b,
          ]
        : [..._budgets, budget];
    _budgetChanges.add(_budgets);
    return budget;
  }

  @override
  Future<void> deleteBudget(String id) async {
    await Future<void>.delayed(latency ~/ 2);
    _budgets = _budgets.where((b) => b.id != id).toList();
    _budgetChanges.add(_budgets);
  }

  @override
  Future<Goal> createGoal({
    required String name,
    required int target,
    required Ownership ownership,
    DateTime? deadline,
  }) async {
    await Future<void>.delayed(latency ~/ 2);
    final goal = Goal(
      id: 'g-${_seq++}',
      name: name.trim(),
      target: target,
      ownership: ownership,
      contributions: const [],
      deadline: deadline,
    );
    _goals = [..._goals, goal];
    _goalChanges.add(_goals);
    return goal;
  }

  @override
  Future<void> contribute(String goalId, int amount) async {
    await Future<void>.delayed(latency ~/ 2);
    _goals = [
      for (final g in _goals)
        if (g.id == goalId)
          g.withContribution(Contribution(amount: amount, date: now()))
        else
          g,
    ];
    _goalChanges.add(_goals);
  }

  @override
  Future<void> deleteGoal(String id) async {
    await Future<void>.delayed(latency ~/ 2);
    _goals = _goals.where((g) => g.id != id).toList();
    _goalChanges.add(_goals);
  }

  void dispose() {
    unawaited(_budgetChanges.close());
    unawaited(_goalChanges.close());
  }

  static List<Goal> _seedGoals(DateTime now) {
    DateTime monthsAgo(int m, int day) =>
        DateTime(now.year, now.month - m, day);
    return [
      Goal(
        id: 'g-emergencia',
        name: 'Fondo de emergencia',
        target: 6000000,
        ownership: Ownership.personal,
        deadline: DateTime(now.year, now.month + 6),
        contributions: [
          Contribution(amount: 400000, date: monthsAgo(0, 15)),
          Contribution(amount: 400000, date: monthsAgo(1, 15)),
          Contribution(amount: 400000, date: monthsAgo(2, 15)),
          Contribution(amount: 2520000, date: monthsAgo(6, 1)),
        ],
      ),
      Goal(
        id: 'g-cartagena',
        name: 'Viaje a Cartagena',
        target: 2500000,
        ownership: Ownership.personal,
        contributions: [
          Contribution(amount: 300000, date: monthsAgo(0, 2)),
          Contribution(amount: 300000, date: monthsAgo(1, 2)),
        ],
      ),
      Goal(
        id: 'g-computador',
        name: 'Computador nuevo',
        target: 5000000,
        ownership: Ownership.business,
        deadline: DateTime(now.year + 1, now.month),
        contributions: [Contribution(amount: 1200000, date: monthsAgo(1, 20))],
      ),
    ];
  }
}
