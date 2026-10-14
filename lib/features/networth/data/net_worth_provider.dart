import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart';
import 'package:inti/features/investments/data/investments_repository.dart';
import 'package:inti/features/networth/domain/net_worth_history.dart';

/// Historial de patrimonio por ámbito.
final netWorthHistoryProvider = Provider<AsyncValue<NetWorthHistory>>((ref) {
  final accounts = ref.watch(accountsProvider);
  final now = ref.watch(clockProvider)();
  if (accounts.hasError) {
    return AsyncError(accounts.error!, accounts.stackTrace!);
  }
  if (!accounts.hasValue) return const AsyncLoading();
  // Las inversiones suman; si aún cargan, no frenan la gráfica.
  final investments = ref.watch(investmentsProvider).value ?? const [];
  int now0(Ownership o) =>
      accounts.requireValue
          .where((a) => a.ownership == o)
          .fold<int>(0, (s, a) => s + a.netValue) +
      investments
          .where((i) => i.ownership == o)
          .fold<int>(0, (s, i) => s + i.value);
  return AsyncData(
    buildDemoHistory(
      personalNow: now0(Ownership.personal),
      businessNow: now0(Ownership.business),
      now: now,
    ),
  );
});
