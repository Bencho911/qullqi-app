import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/data/latency.dart';
import 'package:inti/core/data/live_stream.dart';
import 'package:inti/features/business/domain/business.dart';

/// Facturas de venta del negocio.
abstract interface class InvoicesRepository {
  Stream<List<Invoice>> watch();

  Future<Invoice> create({
    required String client,
    required int base,
    required bool chargesIva,
    required DateTime due,
  });

  Future<void> markPaid(String id);
  Future<void> delete(String id);
}

final invoicesRepositoryProvider = Provider<InvoicesRepository>((ref) {
  final repo = MockInvoicesRepository(
    now: ref.watch(clockProvider),
    latency: ref.watch(mockLatencyProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final invoicesProvider = StreamProvider<List<Invoice>>(
  (ref) => ref.watch(invoicesRepositoryProvider).watch(),
);

class MockInvoicesRepository implements InvoicesRepository {
  MockInvoicesRepository({required this.now, required this.latency})
    : _items = _seed(now());

  final DateTime Function() now;
  final Duration latency;
  List<Invoice> _items;
  final _changes = StreamController<List<Invoice>>.broadcast();

  @override
  Stream<List<Invoice>> watch() => liveStream(
    changes: _changes.stream,
    current: () => _items,
    latency: latency,
  );

  void _emit() => _changes.add(List.unmodifiable(_items));

  @override
  Future<Invoice> create({
    required String client,
    required int base,
    required bool chargesIva,
    required DateTime due,
  }) async {
    await Future<void>.delayed(latency ~/ 2);
    final next =
        _items
            .map((i) => int.tryParse(i.number.replaceAll(RegExp(r'\D'), '')))
            .whereType<int>()
            .fold(0, (m, n) => n > m ? n : m) +
        1;
    final invoice = Invoice(
      id: 'f-$next',
      client: client.trim(),
      number: 'F-${next.toString().padLeft(4, '0')}',
      base: base,
      chargesIva: chargesIva,
      issued: dateOnly(now()),
      due: due,
    );
    _items = [invoice, ..._items];
    _emit();
    return invoice;
  }

  @override
  Future<void> markPaid(String id) async {
    await Future<void>.delayed(latency ~/ 2);
    _items = [
      for (final i in _items)
        if (i.id == id) i.paid(now()) else i,
    ];
    _emit();
  }

  @override
  Future<void> delete(String id) async {
    await Future<void>.delayed(latency ~/ 2);
    _items = _items.where((i) => i.id != id).toList();
    _emit();
  }

  void dispose() => unawaited(_changes.close());

  static List<Invoice> _seed(DateTime now) {
    final today = dateOnly(now);
    DateTime d(int days) => today.add(Duration(days: days));
    return [
      Invoice(
        id: 'f-42',
        client: 'Estudio Alameda S.A.S.',
        number: 'F-0042',
        base: 1500000,
        chargesIva: true,
        issued: d(-6),
        due: d(4),
      ),
      Invoice(
        id: 'f-41',
        client: 'Café Origen S.A.S.',
        number: 'F-0041',
        base: 900000,
        chargesIva: true,
        issued: d(-21),
        due: d(-4),
      ),
      Invoice(
        id: 'f-40',
        client: 'Studio Norte',
        number: 'F-0040',
        base: 2000000,
        chargesIva: true,
        issued: d(-34),
        due: d(-19),
        paidOn: d(-20),
      ),
    ];
  }
}
