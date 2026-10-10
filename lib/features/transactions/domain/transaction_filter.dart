import 'package:flutter/foundation.dart';

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';

/// Rango de fechas de la lista.
enum DateRange {
  thisMonth('Este mes'),
  lastMonth('Mes pasado'),
  last30('Últimos 30 días'),
  all('Todo el historial');

  DateRange(this.label);

  final String label;

  /// `true` si [d] cae en el rango, contando desde [now].
  bool contains(DateTime d, DateTime now) => switch (this) {
    DateRange.thisMonth => d.year == now.year && d.month == now.month,
    DateRange.lastMonth => () {
      final prev = DateTime(now.year, now.month - 1);
      return d.year == prev.year && d.month == prev.month;
    }(),
    DateRange.last30 => daysBetween(d, now) <= 30 && !d.isAfter(now),
    DateRange.all => true,
  };
}

/// Filtros de la lista de movimientos.
@immutable
class TransactionFilter {
  const TransactionFilter({
    this.query = '',
    this.kind,
    this.range = DateRange.thisMonth,
    this.accountIds = const {},
    this.categoryIds = const {},
  });

  final String query;

  /// `null` = todos los tipos.
  final TransactionKind? kind;
  final DateRange range;
  final Set<String> accountIds;
  final Set<String> categoryIds;

  /// Filtros de la hoja (no cuenta búsqueda ni tipo, que están a la vista).
  int get sheetCount =>
      (range == DateRange.thisMonth ? 0 : 1) +
      (accountIds.isEmpty ? 0 : 1) +
      (categoryIds.isEmpty ? 0 : 1);

  bool get isDefault => query.isEmpty && kind == null && sheetCount == 0;

  TransactionFilter copyWith({
    String? query,
    TransactionKind? Function()? kind,
    DateRange? range,
    Set<String>? accountIds,
    Set<String>? categoryIds,
  }) => TransactionFilter(
    query: query ?? this.query,
    kind: kind == null ? this.kind : kind(),
    range: range ?? this.range,
    accountIds: accountIds ?? this.accountIds,
    categoryIds: categoryIds ?? this.categoryIds,
  );
}

/// Quita tildes y mayúsculas para buscar "exito" y encontrar "Éxito".
String normalizeForSearch(String s) {
  const from = 'áéíóúüñÁÉÍÓÚÜÑ';
  const to = 'aeiouunaeiouun';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().toLowerCase().trim();
}

/// Aplica la vista y los filtros. [accountName] da el nombre de la cuenta
/// para que la búsqueda también la encuentre ("nequi").
List<Transaction> applyFilter(
  List<Transaction> all,
  TransactionFilter f, {
  required Scope scope,
  required DateTime now,
  required String Function(String accountId) accountName,
}) {
  final q = normalizeForSearch(f.query);
  return all.where((t) {
    if (!t.ownership.visibleIn(scope)) return false;
    if (f.kind != null && t.kind != f.kind) return false;
    if (!f.range.contains(t.date, now)) return false;
    if (f.accountIds.isNotEmpty && !f.accountIds.contains(t.accountId)) {
      return false;
    }
    if (f.categoryIds.isNotEmpty && !f.categoryIds.contains(t.categoryId)) {
      return false;
    }
    if (q.isEmpty) return true;
    final haystack = normalizeForSearch(
      '${t.title} ${t.category.name} ${accountName(t.accountId)} '
      '${t.note ?? ''}',
    );
    return haystack.contains(q);
  }).toList();
}

/// Ingresos y gastos de una lista (los traslados no cuentan: son tu plata
/// moviéndose entre tus cuentas).
@immutable
class FlowTotals {
  const FlowTotals({required this.income, required this.expense});

  factory FlowTotals.of(Iterable<Transaction> list) {
    var income = 0;
    var expense = 0;
    for (final t in list) {
      if (t.kind == TransactionKind.income) income += t.amount;
      if (t.kind == TransactionKind.expense) expense += t.amount;
    }
    return FlowTotals(income: income, expense: expense);
  }

  final int income;
  final int expense;

  int get net => income - expense;
}

/// Grupo de movimientos de un mismo día.
@immutable
class DayGroup {
  const DayGroup(this.label, this.items);

  /// "Hoy", "Ayer" o "21 de octubre".
  final String label;
  final List<Transaction> items;
}

/// Agrupa por día, del más reciente al más antiguo.
List<DayGroup> groupByDay(List<Transaction> list, DateTime now) {
  final sorted = [...list]..sort((a, b) => b.date.compareTo(a.date));
  final groups = <DayGroup>[];
  for (final t in sorted) {
    final label = Dates.relativeDay(t.date, now);
    if (groups.isNotEmpty && groups.last.label == label) {
      groups.last.items.add(t);
    } else {
      groups.add(DayGroup(label, [t]));
    }
  }
  return groups;
}
