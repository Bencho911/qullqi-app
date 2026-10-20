import 'dart:async';

import 'package:inti/core/api/api_client.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/transactions/data/transactions_repository.dart';
import 'package:inti/features/transactions/domain/transaction.dart';

/// Movimientos guardados en el backend.
///
/// La app crea los movimientos con un id local; el backend asigna otro. Se
/// recuerda la equivalencia para que "Deshacer" con el id local funcione.
class ApiTransactionsRepository implements TransactionsRepository {
  ApiTransactionsRepository(this.api, {this.onBalancesChanged});

  final ApiClient api;

  /// Reclasificar un gasto manual como ingreso cambia el saldo en el
  /// servidor; esto avisa para volver a leer las cuentas.
  final Future<void> Function()? onBalancesChanged;
  final _changes = StreamController<List<Transaction>>.broadcast();
  final _serverIds = <String, String>{};
  List<Transaction>? _last;

  @override
  Stream<List<Transaction>> watch() {
    unawaited(_reload().catchError(_changes.addError));
    return _last == null ? _changes.stream : _startWith(_last!);
  }

  Stream<List<Transaction>> _startWith(List<Transaction> first) async* {
    yield first;
    yield* _changes.stream;
  }

  Future<void> _reload() async {
    final json = await api.get('/v1/transactions', query: {'limit': '500'});
    _last = [
      for (final t in (json! as List).cast<Map<String, Object?>>())
        transactionFromJson(t),
    ];
    _changes.add(List.unmodifiable(_last!));
  }

  String _id(String id) => _serverIds[id] ?? id;

  @override
  Future<void> add(Transaction t) async {
    if (t.kind == TransactionKind.transfer) {
      throw UnsupportedError('Los traslados se registran con el backend.');
    }
    final json = await api.post('/v1/transactions', {
      'accountId': t.accountId,
      'title': t.title,
      'amount': t.amount,
      'kind': t.kind.name,
      'categoryId': t.categoryId,
      'ownership': t.ownership.name,
      'date': t.date.toUtc().toIso8601String(),
      if (t.note != null) 'note': t.note,
      'source': t.source == TransactionSource.imported ? 'imported' : 'manual',
      'needsReview': t.needsReview,
    });
    _serverIds[t.id] = (json! as Map)['id']! as String;
    await _reload();
  }

  @override
  Future<void> update(Transaction t) async {
    await api.patch('/v1/transactions/${_id(t.id)}', {
      'categoryId': t.categoryId,
      'ownership': t.ownership.name,
      'kind': t.kind.name,
      'needsReview': t.needsReview,
      'note': t.note ?? '',
    });
    await _reload();
    await onBalancesChanged?.call();
  }

  @override
  Future<void> delete(String id) async {
    await api.delete('/v1/transactions/${_id(id)}');
    _serverIds.remove(id);
    await _reload();
  }

  void dispose() => unawaited(_changes.close());
}

Transaction transactionFromJson(Map<String, Object?> j) => Transaction(
  id: j['id']! as String,
  title: j['title']! as String,
  amount: (j['amount']! as num).toInt(),
  kind: TransactionKind.values.byName(j['kind']! as String),
  accountId: j['accountId']! as String,
  categoryId: j['categoryId']! as String,
  ownership: Ownership.values.byName(j['ownership']! as String),
  date: DateTime.parse(j['date']! as String).toLocal(),
  needsReview: j['needsReview']! as bool,
  note: j['note'] as String?,
  source: TransactionSource.values.byName(j['source']! as String),
);
