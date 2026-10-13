import 'package:flutter/foundation.dart' show immutable;

import 'package:qullqi/features/transactions/domain/transaction.dart';
import 'package:qullqi/features/transactions/domain/transaction_filter.dart'
    show normalizeForSearch;

/// "Cuando el comercio diga X, la categoría es Y".
@immutable
class CategoryRule {
  const CategoryRule({required this.keyword, required this.categoryId});

  factory CategoryRule.fromJson(Map<String, dynamic> json) => CategoryRule(
    keyword: json['keyword'] as String,
    categoryId: json['categoryId'] as String,
  );

  /// Lo que debe decir el comercio (sin importar mayúsculas ni tildes).
  final String keyword;
  final String categoryId;

  /// Estable y único por palabra: crear otra regla con la misma palabra la
  /// reemplaza.
  String get id => normalizeForSearch(keyword);

  Category get category => Categories.byId(categoryId);

  bool matches(String title) {
    final k = normalizeForSearch(keyword);
    return k.isNotEmpty && normalizeForSearch(title).contains(k);
  }

  Map<String, dynamic> toJson() => {
    'keyword': keyword,
    'categoryId': categoryId,
  };
}

/// La regla que aplica a [title]. Si varias coinciden, gana la palabra más
/// larga (la más específica).
CategoryRule? ruleFor(String title, List<CategoryRule> rules) {
  final hits = rules.where((r) => r.matches(title)).toList()
    ..sort((a, b) => b.keyword.length.compareTo(a.keyword.length));
  return hits.firstOrNull;
}

/// Movimientos que la regla cambiaría de categoría. Los traslados no se
/// tocan: no son gastos ni ingresos.
List<Transaction> affectedBy(CategoryRule rule, List<Transaction> all) => all
    .where(
      (t) =>
          t.kind != TransactionKind.transfer &&
          !t.needsReview &&
          rule.matches(t.title) &&
          t.categoryId != rule.categoryId,
    )
    .toList();
