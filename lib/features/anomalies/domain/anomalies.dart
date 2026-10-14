import 'package:flutter/foundation.dart' show immutable;

import 'package:inti/core/clock/clock.dart';
import 'package:inti/features/recurring/domain/recurring.dart';
import 'package:inti/features/transactions/domain/transaction.dart';
import 'package:inti/features/transactions/domain/transaction_filter.dart'
    show normalizeForSearch;

enum AnomalyKind { duplicate, unusual, bankFee }

/// Días hacia atrás en que un cobro raro todavía vale la pena revisar.
const int anomalyRecentDays = 7;

/// Una comisión del banco se muestra por más tiempo (es informativa).
const int bankFeeRecentDays = 30;

/// Horas entre dos cobros iguales para sospechar un duplicado.
const int duplicateWindowHours = 48;

/// Cobros previos del mismo comercio que hacen falta para saber qué es
/// "lo normal".
const int unusualMinHistory = 3;

/// Cuántas veces lo normal, y cuánto de diferencia mínima, hacen "raro" un
/// cobro.
const double unusualFactor = 2;
const int unusualMinDifference = 50000;

const _feeWords = [
  'cuota de manejo',
  'cuota manejo',
  'comision',
  'gmf',
  '4x1000',
  'cobro bancario',
  'cargo por servicio',
];

/// Un cobro que conviene mirar dos veces.
@immutable
class Anomaly {
  const Anomaly({
    required this.kind,
    required this.transaction,
    this.reference,
  });

  final AnomalyKind kind;
  final Transaction transaction;

  /// Lo normal en ese comercio (solo [AnomalyKind.unusual]).
  final int? reference;

  String get id => '${kind.name}:${transaction.id}';
}

int _median(List<int> values) {
  final s = [...values]..sort();
  final mid = s.length ~/ 2;
  return s.length.isOdd ? s[mid] : (s[mid - 1] + s[mid]) ~/ 2;
}

/// Revisa los gastos recientes en busca de duplicados, montos fuera de lo
/// normal y comisiones del banco. Del más reciente al más antiguo.
List<Anomaly> detectAnomalies(List<Transaction> all, DateTime now) {
  final expenses = all
      .where((t) => t.kind == TransactionKind.expense && !t.needsReview)
      .toList();
  final found = <Anomaly>[];
  for (final t in expenses) {
    final age = daysBetween(t.date, now);
    if (age < 0) continue;
    final key = recurringKey(t.title);

    final isFee = _feeWords.any(normalizeForSearch(t.title).contains);
    if (isFee && age <= bankFeeRecentDays) {
      found.add(Anomaly(kind: AnomalyKind.bankFee, transaction: t));
      continue;
    }
    if (age > anomalyRecentDays || key.isEmpty) continue;

    final others = expenses.where(
      (u) => u.id != t.id && recurringKey(u.title) == key,
    );
    final isDuplicate = others.any(
      (u) =>
          u.accountId == t.accountId &&
          u.amount == t.amount &&
          u.date.isBefore(t.date) &&
          t.date.difference(u.date).inHours <= duplicateWindowHours,
    );
    if (isDuplicate) {
      found.add(Anomaly(kind: AnomalyKind.duplicate, transaction: t));
      continue;
    }

    final before = others
        .where((u) => u.date.isBefore(t.date))
        .map((u) => u.amount)
        .toList();
    if (before.length >= unusualMinHistory) {
      final usual = _median(before);
      if (t.amount >= usual * unusualFactor &&
          t.amount - usual >= unusualMinDifference) {
        found.add(
          Anomaly(kind: AnomalyKind.unusual, transaction: t, reference: usual),
        );
      }
    }
  }
  return found
    ..sort((a, b) => b.transaction.date.compareTo(a.transaction.date));
}
