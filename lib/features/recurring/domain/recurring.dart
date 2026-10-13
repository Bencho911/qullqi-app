import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';
import 'package:qullqi/features/transactions/domain/transaction_filter.dart'
    show normalizeForSearch;

/// Días mínimos y máximos entre dos cobros para llamarlo "cada mes".
const int _minGapDays = 25;
const int _maxGapDays = 36;

/// Si el último cobro fue hace más de esto, dejó de cobrarse.
const int _activeWithinDays = 45;

final _monthWord = RegExp(
  r'\b(enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|'
  r'octubre|noviembre|diciembre)\b',
);

/// Nombre sin meses, números ni tildes: "Arriendo septiembre" y "Arriendo
/// agosto" son el mismo cobro.
String recurringKey(String title) =>
    normalizeForSearch(title)
        .replaceAll(_monthWord, ' ')
        .replaceAll(RegExp('[^a-z ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

/// Un cobro que se repite cada mes (suscripción, plan, cuota).
@immutable
class RecurringCharge {
  const RecurringCharge({
    required this.key,
    required this.title,
    required this.categoryId,
    required this.ownership,
    required this.accountId,
    required this.amount,
    required this.lastDate,
    required this.nextDate,
    required this.history,
    this.previousAmount,
  });

  final String key;
  final String title;
  final String categoryId;
  final Ownership ownership;
  final String accountId;

  /// Lo del último cobro.
  final int amount;

  /// Lo del cobro anterior (para ver si subió).
  final int? previousAmount;
  final DateTime lastDate;

  /// Cuándo debería llegar el próximo.
  final DateTime nextDate;

  /// Todos los cobros, del más reciente al más antiguo.
  final List<Transaction> history;

  Category get category => Categories.byId(categoryId);

  /// Cuánto subió (o bajó, si es negativo) frente al cobro anterior.
  int? get change => previousAmount == null ? null : amount - previousAmount!;

  bool get priceUp => (change ?? 0) > 0;
}

/// Busca gastos que se repiten cada mes con el mismo nombre. Los traslados y
/// los movimientos por revisar no cuentan.
List<RecurringCharge> detectRecurring(List<Transaction> all, DateTime now) {
  final groups = <String, List<Transaction>>{};
  for (final t in all) {
    if (t.kind != TransactionKind.expense || t.needsReview) continue;
    final key = recurringKey(t.title);
    if (key.isEmpty) continue;
    groups.putIfAbsent('$key|${t.ownership.name}', () => []).add(t);
  }
  final found = <RecurringCharge>[];
  for (final group in groups.values) {
    if (group.length < 2) continue;
    final list = [...group]..sort((a, b) => a.date.compareTo(b.date));
    var monthly = true;
    for (var i = 1; i < list.length; i++) {
      final gap = daysBetween(list[i - 1].date, list[i].date);
      if (gap < _minGapDays || gap > _maxGapDays) {
        monthly = false;
        break;
      }
    }
    if (!monthly) continue;
    final last = list.last;
    if (daysBetween(last.date, now) > _activeWithinDays) continue;
    final d = last.date;
    final day = math.min(d.day, DateTime(d.year, d.month + 2, 0).day);
    found.add(
      RecurringCharge(
        key: recurringKey(last.title),
        title: last.title,
        categoryId: last.categoryId,
        ownership: last.ownership,
        accountId: last.accountId,
        amount: last.amount,
        previousAmount: list[list.length - 2].amount,
        lastDate: dateOnly(d),
        nextDate: DateTime(d.year, d.month + 1, day),
        history: list.reversed.toList(),
      ),
    );
  }
  return found..sort((a, b) => a.nextDate.compareTo(b.nextDate));
}

/// Lo que suman al mes.
int monthlyTotal(Iterable<RecurringCharge> list) =>
    list.fold(0, (s, c) => s + c.amount);
