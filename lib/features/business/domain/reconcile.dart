import 'package:flutter/foundation.dart' show immutable;

import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/business/domain/business.dart';
import 'package:inti/features/transactions/domain/transaction.dart';
import 'package:inti/features/transactions/domain/transaction_filter.dart'
    show normalizeForSearch;

/// Qué tan segura es la coincidencia.
enum MatchConfidence {
  /// El depósito es justo el valor de la factura.
  exact('Mismo valor'),

  /// Se parece: el cliente aparece en el depósito y el valor casi coincide.
  likely('Parecido');

  MatchConfidence(this.label);

  final String label;
}

/// Un depósito que parece pagar una factura abierta.
@immutable
class ReconcileSuggestion {
  const ReconcileSuggestion({
    required this.invoice,
    required this.deposit,
    required this.confidence,
  });

  final Invoice invoice;
  final Transaction deposit;
  final MatchConfidence confidence;

  String get id => '${invoice.id}:${deposit.id}';
}

/// Diferencia máxima, como fracción del valor, para llamar "parecido".
const double _likelyTolerance = 0.05;

/// Palabras que no sirven para reconocer a un cliente.
const _noise = {'s.a.s.', 'sas', 'ltda', 'sa', 'de', 'la', 'el', 'los'};

/// Primera palabra con la que se reconoce a un cliente ("Café Origen S.A.S."
/// → "cafe").
String _clientKey(String client) {
  for (final w in normalizeForSearch(client).split(RegExp(r'\s+'))) {
    if (w.length >= 4 && !_noise.contains(w)) return w;
  }
  return '';
}

/// Cruza facturas sin pagar con depósitos del negocio que llegaron después de
/// emitirlas. Un depósito se usa una sola vez y gana el de mismo valor.
List<ReconcileSuggestion> suggestMatches({
  required List<Invoice> invoices,
  required List<Transaction> transactions,
  required DateTime now,
  Set<String> dismissed = const {},
}) {
  final deposits = transactions
      .where(
        (t) =>
            t.kind == TransactionKind.income &&
            t.ownership == Ownership.business &&
            !t.needsReview,
      )
      .toList();
  final open = invoices.where((i) => i.paidOn == null).toList()
    ..sort((a, b) => a.issued.compareTo(b.issued));
  final used = <String>{};
  final out = <ReconcileSuggestion>[];
  for (final i in open) {
    final key = _clientKey(i.client);
    Transaction? exact;
    Transaction? likely;
    for (final d in deposits) {
      if (used.contains(d.id)) continue;
      if (dismissed.contains('${i.id}:${d.id}')) continue;
      if (dateOnly(d.date).isBefore(dateOnly(i.issued))) continue;
      if (daysBetween(d.date, now) < 0) continue;
      if (d.amount == i.total) {
        exact ??= d;
      } else if (key.isNotEmpty &&
          normalizeForSearch(d.title).contains(key) &&
          (d.amount - i.total).abs() <= i.total * _likelyTolerance) {
        likely ??= d;
      }
    }
    final pick = exact ?? likely;
    if (pick == null) continue;
    used.add(pick.id);
    out.add(
      ReconcileSuggestion(
        invoice: i,
        deposit: pick,
        confidence: exact != null
            ? MatchConfidence.exact
            : MatchConfidence.likely,
      ),
    );
  }
  return out;
}
