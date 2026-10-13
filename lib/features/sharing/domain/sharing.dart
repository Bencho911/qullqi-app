import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show IconData, Icons;

/// Identificador de quien usa la app dentro de un grupo.
const String meId = 'me';

/// Una persona de un grupo o de una meta compartida.
@immutable
class Person {
  const Person({required this.id, required this.name});

  final String id;
  final String name;

  bool get isMe => id == meId;

  /// "Tú" o el nombre.
  String get label => isMe ? 'Tú' : name;
}

// ---------------------------------------------------------------------------
// Grupos y gastos compartidos
// ---------------------------------------------------------------------------

enum GroupKind {
  home('Hogar', Icons.home_rounded),
  trip('Viaje', Icons.flight_takeoff_rounded),
  event('Plan', Icons.celebration_rounded);

  GroupKind(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Personas con las que compartes gastos: la casa, un viaje, una salida.
@immutable
class SharedGroup {
  const SharedGroup({
    required this.id,
    required this.name,
    required this.kind,
    required this.members,
    required this.createdAt,
  });

  final String id;
  final String name;
  final GroupKind kind;
  final List<Person> members;
  final DateTime createdAt;

  Person? member(String id) => members.where((m) => m.id == id).firstOrNull;
}

/// Un gasto que pagó una persona y se reparte entre varias.
@immutable
class SharedExpense {
  const SharedExpense({
    required this.id,
    required this.groupId,
    required this.title,
    required this.amount,
    required this.paidBy,
    required this.shares,
    required this.date,
  });

  /// Reparte [amount] en partes iguales entre [participants]; si no cuadra
  /// exacto, los pesos que sobran van de a uno a las primeras personas.
  factory SharedExpense.equal({
    required String id,
    required String groupId,
    required String title,
    required int amount,
    required String paidBy,
    required List<String> participants,
    required DateTime date,
  }) {
    final n = participants.length;
    final base = amount ~/ n;
    final extra = amount - base * n;
    return SharedExpense(
      id: id,
      groupId: groupId,
      title: title,
      amount: amount,
      paidBy: paidBy,
      shares: {
        for (final (i, p) in participants.indexed)
          p: base + (i < extra ? 1 : 0),
      },
      date: date,
    );
  }

  final String id;
  final String groupId;
  final String title;
  final int amount;
  final String paidBy;

  /// Cuánto le toca a cada persona; suma [amount].
  final Map<String, int> shares;
  final DateTime date;
}

/// Un pago entre dos personas del grupo para quedar a mano.
@immutable
class Settlement {
  const Settlement({
    required this.id,
    required this.groupId,
    required this.from,
    required this.to,
    required this.amount,
    required this.date,
  });

  final String id;
  final String groupId;

  /// Quien paga.
  final String from;

  /// Quien recibe.
  final String to;
  final int amount;
  final DateTime date;
}

/// Quién le paga a quién, y cuánto.
@immutable
class Transfer {
  const Transfer({required this.from, required this.to, required this.amount});

  final String from;
  final String to;
  final int amount;
}

/// Saldo de cada persona: positivo, le deben; negativo, debe.
Map<String, int> balancesOf(
  SharedGroup group,
  List<SharedExpense> expenses,
  List<Settlement> settlements,
) {
  final b = {for (final m in group.members) m.id: 0};
  for (final e in expenses.where((e) => e.groupId == group.id)) {
    b[e.paidBy] = (b[e.paidBy] ?? 0) + e.amount;
    for (final s in e.shares.entries) {
      b[s.key] = (b[s.key] ?? 0) - s.value;
    }
  }
  for (final s in settlements.where((s) => s.groupId == group.id)) {
    // Quien paga un saldo sube; quien lo recibe baja.
    b[s.from] = (b[s.from] ?? 0) + s.amount;
    b[s.to] = (b[s.to] ?? 0) - s.amount;
  }
  return b;
}

class _Pending {
  _Pending(this.id, this.left);

  final String id;
  int left;
}

/// Los pagos mínimos que dejan a todos a mano: quien más debe le paga a quien
/// más le deben, y así hasta cuadrar.
List<Transfer> simplifyDebts(Map<String, int> balances) {
  final debtors = [
    for (final e in balances.entries)
      if (e.value < 0) _Pending(e.key, -e.value),
  ]..sort((a, b) => b.left.compareTo(a.left));
  final creditors = [
    for (final e in balances.entries)
      if (e.value > 0) _Pending(e.key, e.value),
  ]..sort((a, b) => b.left.compareTo(a.left));
  final out = <Transfer>[];
  var i = 0;
  var j = 0;
  while (i < debtors.length && j < creditors.length) {
    final d = debtors[i];
    final c = creditors[j];
    final pay = d.left < c.left ? d.left : c.left;
    out.add(Transfer(from: d.id, to: c.id, amount: pay));
    d.left -= pay;
    c.left -= pay;
    if (d.left == 0) i++;
    if (c.left == 0) j++;
  }
  return out;
}

// ---------------------------------------------------------------------------
// Deudas entre personas
// ---------------------------------------------------------------------------

enum DebtDirection {
  theyOweMe('Te deben'),
  iOwe('Debes');

  DebtDirection(this.label);

  final String label;
}

/// Plata que te deben o que debes a una persona, fuera de un grupo.
@immutable
class PersonDebt {
  const PersonDebt({
    required this.id,
    required this.person,
    required this.amount,
    required this.direction,
    required this.concept,
    required this.date,
    this.settledOn,
  });

  final String id;
  final String person;
  final int amount;
  final DebtDirection direction;
  final String concept;
  final DateTime date;
  final DateTime? settledOn;

  bool get settled => settledOn != null;

  PersonDebt settle(DateTime when) => PersonDebt(
    id: id,
    person: person,
    amount: amount,
    direction: direction,
    concept: concept,
    date: date,
    settledOn: when,
  );
}

/// Resumen de las deudas abiertas.
@immutable
class DebtTotals {
  const DebtTotals({required this.owedToMe, required this.iOwe});

  factory DebtTotals.of(Iterable<PersonDebt> debts) {
    var owedToMe = 0;
    var iOwe = 0;
    for (final d in debts.where((d) => !d.settled)) {
      if (d.direction == DebtDirection.theyOweMe) {
        owedToMe += d.amount;
      } else {
        iOwe += d.amount;
      }
    }
    return DebtTotals(owedToMe: owedToMe, iOwe: iOwe);
  }

  final int owedToMe;
  final int iOwe;

  /// Positivo: en total te deben a ti.
  int get net => owedToMe - iOwe;
}

// ---------------------------------------------------------------------------
// Dividir una cuenta
// ---------------------------------------------------------------------------

/// Resultado de dividir una cuenta entre varias personas.
@immutable
class BillSplit {
  const BillSplit({
    required this.bill,
    required this.tip,
    required this.total,
    required this.perPerson,
    required this.people,
  });

  /// [tipPercent] va de 0 a 100. Cada persona paga igual; si no cuadra
  /// exacto, se sube al peso siguiente para que nunca falte plata.
  factory BillSplit.of({
    required int bill,
    required int people,
    int tipPercent = 0,
  }) {
    final n = people < 1 ? 1 : people;
    final tip = (bill * tipPercent / 100).round();
    final total = bill + tip;
    return BillSplit(
      bill: bill,
      tip: tip,
      total: total,
      perPerson: (total / n).ceil(),
      people: n,
    );
  }

  final int bill;
  final int tip;
  final int total;
  final int perPerson;
  final int people;
}

// ---------------------------------------------------------------------------
// Metas compartidas
// ---------------------------------------------------------------------------

@immutable
class SharedContribution {
  const SharedContribution({
    required this.personId,
    required this.amount,
    required this.date,
  });

  final String personId;
  final int amount;
  final DateTime date;
}

/// Meta de ahorro entre varias personas.
@immutable
class SharedGoal {
  const SharedGoal({
    required this.id,
    required this.name,
    required this.target,
    required this.members,
    required this.contributions,
    this.deadline,
  });

  final String id;
  final String name;
  final int target;
  final List<Person> members;
  final List<SharedContribution> contributions;
  final DateTime? deadline;

  int get saved => contributions.fold(0, (s, c) => s + c.amount);
  int get missing => (target - saved).clamp(0, target);
  double get ratio => target == 0 ? 0 : (saved / target).clamp(0, 1);
  bool get done => saved >= target;

  /// Cuánto ha puesto cada persona.
  Map<String, int> get byMember => {
    for (final m in members)
      m.id: contributions
          .where((c) => c.personId == m.id)
          .fold(0, (s, c) => s + c.amount),
  };

  /// Cuánto le tocaría a cada una para llegar, en partes iguales.
  int get fairShare => members.isEmpty ? 0 : (target / members.length).ceil();

  SharedGoal withContribution(SharedContribution c) => SharedGoal(
    id: id,
    name: name,
    target: target,
    members: members,
    contributions: [c, ...contributions],
    deadline: deadline,
  );
}
