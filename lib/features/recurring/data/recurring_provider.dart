import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/features/recurring/domain/recurring.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';

/// Cobros que se repiten cada mes, detectados en tus movimientos.
final recurringProvider = Provider<AsyncValue<List<RecurringCharge>>>((ref) {
  final txs = ref.watch(transactionsProvider);
  final now = ref.watch(clockProvider)();
  return txs.whenData((list) => detectRecurring(list, now));
});
