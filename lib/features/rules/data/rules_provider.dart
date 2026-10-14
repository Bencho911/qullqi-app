import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inti/core/storage/prefs.dart';
import 'package:inti/features/rules/domain/category_rule.dart';

/// Reglas de categoría de la persona. Se recuerdan en el teléfono.
final categoryRulesProvider =
    NotifierProvider<CategoryRulesNotifier, List<CategoryRule>>(
      CategoryRulesNotifier.new,
    );

class CategoryRulesNotifier extends Notifier<List<CategoryRule>> {
  static const _key = 'category_rules';

  @override
  List<CategoryRule> build() {
    final raw =
        ref.read(sharedPreferencesProvider).getStringList(_key) ?? const [];
    final rules = <CategoryRule>[];
    for (final s in raw) {
      try {
        rules.add(CategoryRule.fromJson(jsonDecode(s) as Map<String, dynamic>));
      } on Object {
        // Una regla dañada se descarta; las demás siguen.
      }
    }
    return rules;
  }

  Future<void> _save() => ref.read(sharedPreferencesProvider).setStringList(
    _key,
    [for (final r in state) jsonEncode(r.toJson())],
  );

  /// Crea la regla; si ya había una con la misma palabra, la reemplaza.
  Future<CategoryRule> add({
    required String keyword,
    required String categoryId,
  }) async {
    final rule = CategoryRule(keyword: keyword.trim(), categoryId: categoryId);
    state = [
      for (final r in state)
        if (r.id != rule.id) r,
      rule,
    ];
    await _save();
    return rule;
  }

  Future<void> remove(String id) async {
    state = state.where((r) => r.id != id).toList();
    await _save();
  }
}
