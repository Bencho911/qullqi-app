import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/data/latency.dart';
import 'package:inti/core/data/memory_list.dart';
import 'package:inti/core/storage/prefs.dart';
import 'package:inti/features/business/data/invoices_repository.dart';
import 'package:inti/features/business/domain/accountant.dart';
import 'package:inti/features/business/domain/bill.dart';
import 'package:inti/features/business/domain/reconcile.dart';
import 'package:inti/features/transactions/data/transactions_repository.dart';
import 'package:inti/features/transactions/domain/transaction.dart';

// ---------------------------------------------------------------------------
// Cuentas por pagar
// ---------------------------------------------------------------------------

abstract interface class BillsRepository {
  Stream<List<Bill>> watch();

  Future<Bill> create({
    required String supplier,
    required String concept,
    required int amount,
    required DateTime due,
    required String categoryId,
  });

  Future<void> markPaid(String id);
  Future<void> delete(String id);
}

final billsRepositoryProvider = Provider<BillsRepository>((ref) {
  final repo = MockBillsRepository(
    now: ref.watch(clockProvider),
    latency: ref.watch(mockLatencyProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final billsProvider = StreamProvider<List<Bill>>(
  (ref) => ref.watch(billsRepositoryProvider).watch(),
);

class MockBillsRepository implements BillsRepository {
  MockBillsRepository({required this.now, required this.latency})
    : _store = MemoryList(initial: _seed(now()), latency: latency);

  final DateTime Function() now;
  final Duration latency;
  final MemoryList<Bill> _store;
  int _seq = 0;

  @override
  Stream<List<Bill>> watch() => _store.watch();

  @override
  Future<Bill> create({
    required String supplier,
    required String concept,
    required int amount,
    required DateTime due,
    required String categoryId,
  }) async {
    await _store.roundTrip();
    final bill = Bill(
      id: 'b-new-${_seq++}',
      supplier: supplier.trim(),
      concept: concept.trim(),
      amount: amount,
      due: dateOnly(due),
      categoryId: categoryId,
    );
    _store.prepend(bill);
    return bill;
  }

  @override
  Future<void> markPaid(String id) async {
    await _store.roundTrip();
    final t = now();
    _store.update((b) => b.id == id, (b) => b.paid(t));
  }

  @override
  Future<void> delete(String id) async {
    await _store.roundTrip();
    _store.removeWhere((b) => b.id == id);
  }

  void dispose() => _store.dispose();

  static List<Bill> _seed(DateTime now) {
    final today = dateOnly(now);
    DateTime d(int days) => today.add(Duration(days: days));
    return [
      Bill(
        id: 'b-2',
        supplier: 'Papelería El Norte',
        concept: 'Insumos de oficina',
        amount: 180000,
        due: d(-3),
        categoryId: Categories.other.id,
      ),
      Bill(
        id: 'b-1',
        supplier: 'Diseño Gráfico Andino',
        concept: 'Diseño de empaques',
        amount: 450000,
        due: d(12),
        categoryId: Categories.other.id,
      ),
      Bill(
        id: 'b-0',
        supplier: 'Hosting Colombia',
        concept: 'Plan anual',
        amount: 320000,
        due: d(-40),
        categoryId: Categories.software.id,
        paidOn: d(-41),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Acceso del contador
// ---------------------------------------------------------------------------

abstract interface class AccountantRepository {
  Stream<List<AccountantInvite>> watch();
  Future<AccountantInvite> invite(String email);
  Future<void> revoke(String id);
}

final accountantRepositoryProvider = Provider<AccountantRepository>((ref) {
  final repo = MockAccountantRepository(
    now: ref.watch(clockProvider),
    latency: ref.watch(mockLatencyProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final accountantInvitesProvider = StreamProvider<List<AccountantInvite>>(
  (ref) => ref.watch(accountantRepositoryProvider).watch(),
);

class MockAccountantRepository implements AccountantRepository {
  MockAccountantRepository({required this.now, required this.latency})
    : _store = MemoryList(initial: _seed(now()), latency: latency);

  final DateTime Function() now;
  final Duration latency;
  final MemoryList<AccountantInvite> _store;
  int _seq = 0;

  @override
  Stream<List<AccountantInvite>> watch() => _store.watch();

  @override
  Future<AccountantInvite> invite(String email) async {
    await _store.roundTrip();
    final invite = AccountantInvite(
      id: 'inv-${_seq++}',
      email: email.trim().toLowerCase(),
      createdAt: dateOnly(now()),
      status: InviteStatus.pending,
    );
    _store.prepend(invite);
    return invite;
  }

  @override
  Future<void> revoke(String id) async {
    await _store.roundTrip();
    _store.update(
      (i) => i.id == id,
      (i) => i.copyWith(status: InviteStatus.revoked),
    );
  }

  void dispose() => _store.dispose();

  static List<AccountantInvite> _seed(DateTime now) => [
    AccountantInvite(
      id: 'inv-seed',
      email: 'contadora@estudiocontable.co',
      createdAt: dateOnly(now).subtract(const Duration(days: 60)),
      status: InviteStatus.active,
    ),
  ];
}

// ---------------------------------------------------------------------------
// Conciliación
// ---------------------------------------------------------------------------

/// Sugerencias que la persona descartó ("No es este pago").
final dismissedReconcileProvider =
    NotifierProvider<DismissedReconcileNotifier, Set<String>>(
      DismissedReconcileNotifier.new,
    );

class DismissedReconcileNotifier extends Notifier<Set<String>> {
  static const _key = 'reconcile_dismissed';

  @override
  Set<String> build() =>
      (ref.read(sharedPreferencesProvider).getStringList(_key) ?? const [])
          .toSet();

  Future<void> dismiss(String id) async {
    state = {...state, id};
    await ref.read(sharedPreferencesProvider).setStringList(_key, [...state]);
  }
}

/// Depósitos que parecen pagar una factura abierta.
final reconcileSuggestionsProvider =
    Provider<AsyncValue<List<ReconcileSuggestion>>>((ref) {
      final invoices = ref.watch(invoicesProvider);
      final txs = ref.watch(transactionsProvider);
      final dismissed = ref.watch(dismissedReconcileProvider);
      final now = ref.watch(clockProvider)();
      if (invoices.hasError) {
        return AsyncError(invoices.error!, invoices.stackTrace!);
      }
      if (txs.hasError) return AsyncError(txs.error!, txs.stackTrace!);
      if (!invoices.hasValue || !txs.hasValue) return const AsyncLoading();
      return AsyncData(
        suggestMatches(
          invoices: invoices.requireValue,
          transactions: txs.requireValue,
          now: now,
          dismissed: dismissed,
        ),
      );
    });
