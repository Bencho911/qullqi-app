import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/data/latency.dart';
import 'package:qullqi/core/data/memory_list.dart';
import 'package:qullqi/features/sharing/domain/sharing.dart';

/// "Tú" siempre va de primero en un grupo.
const Person _me = Person(id: meId, name: 'Tú');

List<Person> _people(List<String> names, String prefix) => [
  _me,
  for (final (i, n) in names.indexed) Person(id: '$prefix-$i', name: n.trim()),
];

// ---------------------------------------------------------------------------
// Grupos
// ---------------------------------------------------------------------------

abstract interface class GroupsRepository {
  Stream<List<SharedGroup>> watchGroups();
  Stream<List<SharedExpense>> watchExpenses();
  Stream<List<Settlement>> watchSettlements();

  Future<SharedGroup> createGroup({
    required String name,
    required GroupKind kind,
    required List<String> otherMembers,
  });

  /// Reparte en partes iguales entre [participants].
  Future<SharedExpense> addExpense({
    required String groupId,
    required String title,
    required int amount,
    required String paidBy,
    required List<String> participants,
  });

  Future<void> deleteExpense(String id);

  /// [from] le pagó [amount] a [to].
  Future<void> settle({
    required String groupId,
    required String from,
    required String to,
    required int amount,
  });

  Future<void> deleteGroup(String id);
}

final groupsRepositoryProvider = Provider<GroupsRepository>((ref) {
  final repo = MockGroupsRepository(
    now: ref.watch(clockProvider),
    latency: ref.watch(mockLatencyProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final groupsProvider = StreamProvider<List<SharedGroup>>(
  (ref) => ref.watch(groupsRepositoryProvider).watchGroups(),
);

final sharedExpensesProvider = StreamProvider<List<SharedExpense>>(
  (ref) => ref.watch(groupsRepositoryProvider).watchExpenses(),
);

final settlementsProvider = StreamProvider<List<Settlement>>(
  (ref) => ref.watch(groupsRepositoryProvider).watchSettlements(),
);

class MockGroupsRepository implements GroupsRepository {
  MockGroupsRepository({required this.now, required this.latency})
    : _groups = MemoryList(initial: _seedGroups(now()), latency: latency),
      _expenses = MemoryList(initial: _seedExpenses(now()), latency: latency),
      _settlements = MemoryList<Settlement>(initial: [], latency: latency);

  final DateTime Function() now;
  final Duration latency;
  final MemoryList<SharedGroup> _groups;
  final MemoryList<SharedExpense> _expenses;
  final MemoryList<Settlement> _settlements;
  int _seq = 0;

  @override
  Stream<List<SharedGroup>> watchGroups() => _groups.watch();

  @override
  Stream<List<SharedExpense>> watchExpenses() => _expenses.watch();

  @override
  Stream<List<Settlement>> watchSettlements() => _settlements.watch();

  @override
  Future<SharedGroup> createGroup({
    required String name,
    required GroupKind kind,
    required List<String> otherMembers,
  }) async {
    await _groups.roundTrip();
    final id = 'g-new-${_seq++}';
    final group = SharedGroup(
      id: id,
      name: name.trim(),
      kind: kind,
      members: _people(otherMembers, id),
      createdAt: dateOnly(now()),
    );
    _groups.prepend(group);
    return group;
  }

  @override
  Future<SharedExpense> addExpense({
    required String groupId,
    required String title,
    required int amount,
    required String paidBy,
    required List<String> participants,
  }) async {
    await _expenses.roundTrip();
    final e = SharedExpense.equal(
      id: 'e-new-${_seq++}',
      groupId: groupId,
      title: title.trim(),
      amount: amount,
      paidBy: paidBy,
      participants: participants,
      date: dateOnly(now()),
    );
    _expenses.prepend(e);
    return e;
  }

  @override
  Future<void> deleteExpense(String id) async {
    await _expenses.roundTrip();
    _expenses.removeWhere((e) => e.id == id);
  }

  @override
  Future<void> settle({
    required String groupId,
    required String from,
    required String to,
    required int amount,
  }) async {
    await _settlements.roundTrip();
    _settlements.prepend(
      Settlement(
        id: 's-new-${_seq++}',
        groupId: groupId,
        from: from,
        to: to,
        amount: amount,
        date: dateOnly(now()),
      ),
    );
  }

  @override
  Future<void> deleteGroup(String id) async {
    await _groups.roundTrip();
    _groups.removeWhere((g) => g.id == id);
    _expenses.removeWhere((e) => e.groupId == id);
    _settlements.removeWhere((s) => s.groupId == id);
  }

  void dispose() {
    _groups.dispose();
    _expenses.dispose();
    _settlements.dispose();
  }

  static List<SharedGroup> _seedGroups(DateTime now) {
    final today = dateOnly(now);
    return [
      SharedGroup(
        id: 'g-casa',
        name: 'Casa',
        kind: GroupKind.home,
        members: const [
          _me,
          Person(id: 'casa-laura', name: 'Laura'),
        ],
        createdAt: today.subtract(const Duration(days: 120)),
      ),
      SharedGroup(
        id: 'g-viaje',
        name: 'Viaje a Cartagena',
        kind: GroupKind.trip,
        members: const [
          _me,
          Person(id: 'viaje-laura', name: 'Laura'),
          Person(id: 'viaje-andres', name: 'Andrés'),
        ],
        createdAt: today.subtract(const Duration(days: 20)),
      ),
    ];
  }

  static List<SharedExpense> _seedExpenses(DateTime now) {
    final today = dateOnly(now);
    DateTime d(int ago) => today.subtract(Duration(days: ago));
    return [
      SharedExpense.equal(
        id: 'e-3',
        groupId: 'g-viaje',
        title: 'Cena de despedida',
        amount: 210000,
        paidBy: meId,
        participants: const [meId, 'viaje-laura', 'viaje-andres'],
        date: d(2),
      ),
      SharedExpense.equal(
        id: 'e-2',
        groupId: 'g-viaje',
        title: 'Hotel',
        amount: 900000,
        paidBy: 'viaje-laura',
        participants: const [meId, 'viaje-laura', 'viaje-andres'],
        date: d(6),
      ),
      SharedExpense.equal(
        id: 'e-1',
        groupId: 'g-casa',
        title: 'Mercado de la semana',
        amount: 240000,
        paidBy: meId,
        participants: const [meId, 'casa-laura'],
        date: d(3),
      ),
      SharedExpense.equal(
        id: 'e-0',
        groupId: 'g-casa',
        title: 'Servicios (agua y luz)',
        amount: 180000,
        paidBy: 'casa-laura',
        participants: const [meId, 'casa-laura'],
        date: d(8),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Deudas entre personas
// ---------------------------------------------------------------------------

abstract interface class DebtsRepository {
  Stream<List<PersonDebt>> watch();

  Future<PersonDebt> add({
    required String person,
    required int amount,
    required DebtDirection direction,
    required String concept,
  });

  Future<void> markSettled(String id);
  Future<void> delete(String id);
}

final debtsRepositoryProvider = Provider<DebtsRepository>((ref) {
  final repo = MockDebtsRepository(
    now: ref.watch(clockProvider),
    latency: ref.watch(mockLatencyProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final personDebtsProvider = StreamProvider<List<PersonDebt>>(
  (ref) => ref.watch(debtsRepositoryProvider).watch(),
);

class MockDebtsRepository implements DebtsRepository {
  MockDebtsRepository({required this.now, required this.latency})
    : _store = MemoryList(initial: _seed(now()), latency: latency);

  final DateTime Function() now;
  final Duration latency;
  final MemoryList<PersonDebt> _store;
  int _seq = 0;

  @override
  Stream<List<PersonDebt>> watch() => _store.watch();

  @override
  Future<PersonDebt> add({
    required String person,
    required int amount,
    required DebtDirection direction,
    required String concept,
  }) async {
    await _store.roundTrip();
    final d = PersonDebt(
      id: 'd-new-${_seq++}',
      person: person.trim(),
      amount: amount,
      direction: direction,
      concept: concept.trim(),
      date: dateOnly(now()),
    );
    _store.prepend(d);
    return d;
  }

  @override
  Future<void> markSettled(String id) async {
    await _store.roundTrip();
    final t = dateOnly(now());
    _store.update((d) => d.id == id, (d) => d.settle(t));
  }

  @override
  Future<void> delete(String id) async {
    await _store.roundTrip();
    _store.removeWhere((d) => d.id == id);
  }

  void dispose() => _store.dispose();

  static List<PersonDebt> _seed(DateTime now) {
    final today = dateOnly(now);
    DateTime d(int ago) => today.subtract(Duration(days: ago));
    return [
      PersonDebt(
        id: 'd-2',
        person: 'Andrés',
        amount: 45000,
        direction: DebtDirection.theyOweMe,
        concept: 'Almuerzo del viernes',
        date: d(4),
      ),
      PersonDebt(
        id: 'd-1',
        person: 'Laura',
        amount: 30000,
        direction: DebtDirection.iOwe,
        concept: 'Entradas al cine',
        date: d(9),
      ),
      PersonDebt(
        id: 'd-0',
        person: 'Juan Pérez',
        amount: 150000,
        direction: DebtDirection.theyOweMe,
        concept: 'Préstamo',
        date: d(40),
        settledOn: d(12),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Metas compartidas
// ---------------------------------------------------------------------------

abstract interface class SharedGoalsRepository {
  Stream<List<SharedGoal>> watch();

  Future<SharedGoal> create({
    required String name,
    required int target,
    required List<String> otherMembers,
  });

  Future<void> contribute(String goalId, String personId, int amount);
  Future<void> delete(String id);
}

final sharedGoalsRepositoryProvider = Provider<SharedGoalsRepository>((ref) {
  final repo = MockSharedGoalsRepository(
    now: ref.watch(clockProvider),
    latency: ref.watch(mockLatencyProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final sharedGoalsProvider = StreamProvider<List<SharedGoal>>(
  (ref) => ref.watch(sharedGoalsRepositoryProvider).watch(),
);

class MockSharedGoalsRepository implements SharedGoalsRepository {
  MockSharedGoalsRepository({required this.now, required this.latency})
    : _store = MemoryList(initial: _seed(now()), latency: latency);

  final DateTime Function() now;
  final Duration latency;
  final MemoryList<SharedGoal> _store;
  int _seq = 0;

  @override
  Stream<List<SharedGoal>> watch() => _store.watch();

  @override
  Future<SharedGoal> create({
    required String name,
    required int target,
    required List<String> otherMembers,
  }) async {
    await _store.roundTrip();
    final id = 'sg-new-${_seq++}';
    final goal = SharedGoal(
      id: id,
      name: name.trim(),
      target: target,
      members: _people(otherMembers, id),
      contributions: const [],
    );
    _store.prepend(goal);
    return goal;
  }

  @override
  Future<void> contribute(String goalId, String personId, int amount) async {
    await _store.roundTrip();
    final c = SharedContribution(
      personId: personId,
      amount: amount,
      date: dateOnly(now()),
    );
    _store.update((g) => g.id == goalId, (g) => g.withContribution(c));
  }

  @override
  Future<void> delete(String id) async {
    await _store.roundTrip();
    _store.removeWhere((g) => g.id == id);
  }

  void dispose() => _store.dispose();

  static List<SharedGoal> _seed(DateTime now) {
    final today = dateOnly(now);
    return [
      SharedGoal(
        id: 'sg-sai',
        name: 'Viaje a San Andrés',
        target: 6000000,
        members: const [
          _me,
          Person(id: 'sg-sai-laura', name: 'Laura'),
        ],
        deadline: DateTime(today.year + 1, 3),
        contributions: [
          SharedContribution(
            personId: meId,
            amount: 1200000,
            date: today.subtract(const Duration(days: 10)),
          ),
          SharedContribution(
            personId: 'sg-sai-laura',
            amount: 900000,
            date: today.subtract(const Duration(days: 6)),
          ),
        ],
      ),
    ];
  }
}
