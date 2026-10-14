import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inti/core/clock/clock.dart';
import 'package:inti/features/recurring/domain/recurring.dart';
import 'package:inti/features/transactions/data/transactions_repository.dart';

/// Cobros que se repiten cada mes, detectados en tus movimientos.
final recurringProvider = Provider<AsyncValue<List<RecurringCharge>>>((ref) {
  final txs = ref.watch(transactionsProvider);
  final now = ref.watch(clockProvider)();
  return txs.whenData((list) => detectRecurring(list, now));
});
