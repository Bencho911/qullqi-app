import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/data/latency.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/features/commitments/domain/commitment.dart';

/// Pagos fijos e impuestos estimados de la persona.
abstract interface class CommitmentsRepository {
  Stream<List<Commitment>> watch();
}

final commitmentsRepositoryProvider = Provider<CommitmentsRepository>(
  (ref) => MockCommitmentsRepository(
    now: ref.watch(clockProvider),
    latency: ref.watch(mockLatencyProvider),
  ),
);

final commitmentsProvider = StreamProvider<List<Commitment>>(
  (ref) => ref.watch(commitmentsRepositoryProvider).watch(),
);

class MockCommitmentsRepository implements CommitmentsRepository {
  MockCommitmentsRepository({required this.now, required this.latency});

  final DateTime Function() now;
  final Duration latency;

  @override
  Stream<List<Commitment>> watch() async* {
    await Future<void>.delayed(latency);
    final today = dateOnly(now());
    DateTime inDays(int d) => today.add(Duration(days: d));
    yield [
      Commitment(
        id: 'internet',
        title: 'Internet y TV del hogar',
        amount: 89000,
        due: inDays(5),
        ownership: Ownership.personal,
        kind: CommitmentKind.bill,
      ),
      Commitment(
        id: 'arriendo',
        title: 'Arriendo',
        amount: 1200000,
        due: inDays(8),
        ownership: Ownership.personal,
        kind: CommitmentKind.bill,
      ),
      Commitment(
        id: 'claro',
        title: 'Plan Claro del negocio',
        amount: 89000,
        due: inDays(5),
        ownership: Ownership.business,
        kind: CommitmentKind.bill,
      ),
    ];
  }
}
