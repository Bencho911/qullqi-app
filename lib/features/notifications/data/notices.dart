import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/core/storage/prefs.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/business/data/invoices_repository.dart';
import 'package:qullqi/features/business/domain/business.dart';
import 'package:qullqi/features/commitments/data/commitments_repository.dart';
import 'package:qullqi/features/home/domain/home_data.dart';
import 'package:qullqi/features/investments/data/investments_repository.dart';
import 'package:qullqi/features/notifications/domain/notice.dart';
import 'package:qullqi/features/planning/data/plans_repository.dart';
import 'package:qullqi/features/profile/data/notification_prefs.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';

/// Fuentes de los avisos (para reintentar si alguna falla).
final List<ProviderBase<Object?>> noticeSources = [
  accountsProvider,
  commitmentsProvider,
  transactionsProvider,
  budgetsProvider,
  invoicesProvider,
  investmentsProvider,
];

/// Avisos vigentes, ya filtrados por lo que la persona eligió recibir.
final noticesProvider = Provider<AsyncValue<List<Notice>>>((ref) {
  final accounts = ref.watch(accountsProvider);
  final commitments = ref.watch(commitmentsProvider);
  final transactions = ref.watch(transactionsProvider);
  final budgets = ref.watch(budgetsProvider);
  final invoices = ref.watch(invoicesProvider);
  final investments = ref.watch(investmentsProvider);
  final now = ref.watch(clockProvider)();

  for (final v in [
    accounts,
    commitments,
    transactions,
    budgets,
    invoices,
    investments,
  ]) {
    if (v.hasError) return AsyncError(v.error!, v.stackTrace!);
    if (!v.hasValue) return const AsyncLoading();
  }
  final txs = transactions.requireValue;
  final business = BusinessMonth.of(invoices.requireValue, txs, now);
  return AsyncData(
    buildNotices(
      now: now,
      accounts: accounts.requireValue,
      commitments: withIvaCommitment(commitments.requireValue, business),
      transactions: txs,
      budgets: budgets.requireValue,
      invoices: invoices.requireValue,
      investments: investments.requireValue,
      hasBusiness: ref.watch(currentUserProvider).hasBusiness,
      enabled: ref.watch(noticePrefsProvider),
    ),
  );
});

/// Avisos que la persona ya vio (se recuerda en el teléfono).
final seenNoticesProvider = NotifierProvider<SeenNoticesNotifier, Set<String>>(
  SeenNoticesNotifier.new,
);

class SeenNoticesNotifier extends Notifier<Set<String>> {
  static const _key = 'notices_seen';

  @override
  Set<String> build() =>
      (ref.read(sharedPreferencesProvider).getStringList(_key) ?? const [])
          .toSet();

  /// Marca como vistos [ids]. Solo se guardan los vigentes, para que la
  /// lista no crezca sin fin.
  Future<void> markSeen(Iterable<String> ids) async {
    final next = ids.toSet();
    if (next.difference(state).isEmpty && state.length == next.length) return;
    state = next;
    await ref.read(sharedPreferencesProvider).setStringList(_key, [...next]);
  }
}

/// Avisos que aún no se han visto: el número de la campana.
final unreadNotificationsProvider = Provider<int>((ref) {
  final notices = ref.watch(noticesProvider).value ?? const <Notice>[];
  final seen = ref.watch(seenNoticesProvider);
  return notices.where((n) => !seen.contains(n.id)).length;
});
