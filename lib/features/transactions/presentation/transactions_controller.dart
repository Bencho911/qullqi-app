import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderFamily;

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/scope/scope_provider.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/accounts/domain/account.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';
import 'package:qullqi/features/transactions/domain/transaction_filter.dart';

/// Filtros activos de la lista de movimientos (se conservan al cambiar de
/// pestaña y volver).
final transactionFilterProvider =
    NotifierProvider<TransactionFilterNotifier, TransactionFilter>(
      TransactionFilterNotifier.new,
    );

class TransactionFilterNotifier extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() {
    // Al cambiar de vista, los filtros de cuenta dejan de tener sentido.
    ref.watch(scopeProvider);
    return const TransactionFilter();
  }

  // Los notifiers de Riverpod exponen el cambio como método, no como setter.
  // ignore: use_setters_to_change_properties
  void set(TransactionFilter f) => state = f;

  void reset() => state = const TransactionFilter();
}

/// Lo que muestra la lista de movimientos.
@immutable
class TransactionsView {
  const TransactionsView({
    required this.scope,
    required this.now,
    required this.filter,
    required this.groups,
    required this.totals,
    required this.toReview,
    required this.accounts,
    required this.isEmpty,
  });

  final Scope scope;
  final DateTime now;
  final TransactionFilter filter;
  final List<DayGroup> groups;
  final FlowTotals totals;

  /// Traslados detectados que esperan confirmación (en la vista).
  final List<Transaction> toReview;
  final List<Account> accounts;

  /// La persona no tiene ningún movimiento en esta vista (sin filtros).
  final bool isEmpty;

  int get shown => groups.fold(0, (s, g) => s + g.items.length);
}

final transactionsViewProvider = Provider<AsyncValue<TransactionsView>>((ref) {
  final txs = ref.watch(transactionsProvider);
  final accounts = ref.watch(accountsProvider);
  final scope = ref.watch(scopeProvider);
  final filter = ref.watch(transactionFilterProvider);
  final now = ref.watch(clockProvider)();

  for (final v in [txs, accounts]) {
    if (v.hasError) return AsyncError(v.error!, v.stackTrace!);
  }
  if (!txs.hasValue || !accounts.hasValue) return const AsyncLoading();

  final accs = accounts.requireValue;
  String name(String id) =>
      accs.where((a) => a.id == id).firstOrNull?.shortName ?? '';
  final inScope = txs.requireValue
      .where((t) => t.ownership.visibleIn(scope))
      .toList();
  final shown = applyFilter(
    inScope,
    filter,
    scope: scope,
    now: now,
    accountName: name,
  );
  return AsyncData(
    TransactionsView(
      scope: scope,
      now: now,
      filter: filter,
      groups: groupByDay(shown, now),
      totals: FlowTotals.of(shown),
      toReview: inScope.where((t) => t.needsReview).toList(),
      accounts: accs,
      isEmpty: inScope.isEmpty,
    ),
  );
});

/// Un movimiento por id (para el detalle). `null` si ya no existe.
final ProviderFamily<AsyncValue<Transaction?>, String> transactionByIdProvider =
    Provider.family<AsyncValue<Transaction?>, String>((ref, id) {
      return ref
          .watch(transactionsProvider)
          .whenData((list) => list.where((t) => t.id == id).firstOrNull);
    });

/// Guarda un cambio y avisa. Si falla, lo dice y no pierde nada.
Future<bool> saveTransaction(
  BuildContext context,
  WidgetRef ref,
  Transaction updated, {
  required String done,
  Transaction? undo,
}) async {
  final repo = ref.read(transactionsRepositoryProvider);
  try {
    await repo.update(updated);
    if (context.mounted) {
      showQToast(
        context,
        done,
        actionLabel: undo == null ? null : 'Deshacer',
        onAction: undo == null ? null : () => repo.update(undo),
      );
    }
    return true;
  } on Object {
    if (context.mounted) {
      showQToast(context, 'No pudimos guardar el cambio. Inténtalo de nuevo.');
    }
    return false;
  }
}
