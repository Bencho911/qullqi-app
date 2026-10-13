import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/storage/prefs.dart';
import 'package:qullqi/features/taxes/domain/tax_calendar.dart';

/// Documento con el que se arma el calendario. Se recuerda en el teléfono.
final taxDocumentProvider = NotifierProvider<TaxDocumentNotifier, TaxDocument?>(
  TaxDocumentNotifier.new,
);

class TaxDocumentNotifier extends Notifier<TaxDocument?> {
  static const _key = 'tax_document';

  @override
  TaxDocument? build() {
    final raw = ref.read(sharedPreferencesProvider).getString(_key);
    if (raw == null) return null;
    try {
      final doc = TaxDocument.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return doc.isValid ? doc : null;
    } on Object {
      return null;
    }
  }

  Future<void> save(TaxDocument doc) async {
    state = doc;
    await ref
        .read(sharedPreferencesProvider)
        .setString(_key, jsonEncode(doc.toJson()));
  }

  Future<void> clear() async {
    state = null;
    await ref.read(sharedPreferencesProvider).remove(_key);
  }
}
