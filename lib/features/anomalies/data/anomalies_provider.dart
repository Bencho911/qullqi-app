import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/features/anomalies/domain/anomalies.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';

/// Cobros que conviene mirar dos veces, detectados en tus movimientos.
final anomaliesProvider = Provider<AsyncValue<List<Anomaly>>>((ref) {
  final txs = ref.watch(transactionsProvider);
  final now = ref.watch(clockProvider)();
  return txs.whenData((list) => detectAnomalies(list, now));
});
