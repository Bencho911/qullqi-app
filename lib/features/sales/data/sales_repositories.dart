import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/data/latency.dart';
import 'package:inti/core/data/memory_list.dart';
import 'package:inti/features/sales/domain/sales.dart';

/// Siguiente número consecutivo con prefijo: "C-0004".
String _nextNumber(String prefix, Iterable<String> existing) {
  final last = existing
      .map((n) => int.tryParse(n.replaceAll(RegExp(r'\D'), '')))
      .whereType<int>()
      .fold(0, (m, n) => n > m ? n : m);
  return '$prefix-${(last + 1).toString().padLeft(4, '0')}';
}

// ---------------------------------------------------------------------------
// Cotizaciones
// ---------------------------------------------------------------------------

abstract interface class QuotesRepository {
  Stream<List<Quote>> watch();

  Future<Quote> create({
    required String client,
    required List<QuoteLine> lines,
    required bool chargesIva,
    required int validDays,
    required bool send,
  });

  Future<void> setStatus(String id, QuoteStatus status);

  /// La cotización se aceptó y se convirtió en la factura [invoiceId].
  Future<void> linkInvoice(String id, String invoiceId);

  Future<void> delete(String id);
}

final quotesRepositoryProvider = Provider<QuotesRepository>((ref) {
  final repo = MockQuotesRepository(
    now: ref.watch(clockProvider),
    latency: ref.watch(mockLatencyProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final quotesProvider = StreamProvider<List<Quote>>(
  (ref) => ref.watch(quotesRepositoryProvider).watch(),
);

class MockQuotesRepository implements QuotesRepository {
  MockQuotesRepository({required this.now, required this.latency})
    : _store = MemoryList(initial: _seed(now()), latency: latency);

  final DateTime Function() now;
  final Duration latency;
  final MemoryList<Quote> _store;
  int _seq = 0;

  @override
  Stream<List<Quote>> watch() => _store.watch();

  @override
  Future<Quote> create({
    required String client,
    required List<QuoteLine> lines,
    required bool chargesIva,
    required int validDays,
    required bool send,
  }) async {
    await _store.roundTrip();
    final today = dateOnly(now());
    final quote = Quote(
      id: 'q-${_seq++}',
      client: client.trim(),
      number: _nextNumber('C', _store.items.map((q) => q.number)),
      lines: lines,
      chargesIva: chargesIva,
      issued: today,
      validUntil: today.add(Duration(days: validDays)),
      status: send ? QuoteStatus.sent : QuoteStatus.draft,
    );
    _store.prepend(quote);
    return quote;
  }

  @override
  Future<void> setStatus(String id, QuoteStatus status) async {
    await _store.roundTrip();
    _store.update((q) => q.id == id, (q) => q.copyWith(status: status));
  }

  @override
  Future<void> linkInvoice(String id, String invoiceId) async {
    await _store.roundTrip();
    _store.update(
      (q) => q.id == id,
      (q) => q.copyWith(status: QuoteStatus.accepted, invoiceId: invoiceId),
    );
  }

  @override
  Future<void> delete(String id) async {
    await _store.roundTrip();
    _store.removeWhere((q) => q.id == id);
  }

  void dispose() => _store.dispose();

  static List<Quote> _seed(DateTime now) {
    final today = dateOnly(now);
    DateTime d(int days) => today.add(Duration(days: days));
    return [
      Quote(
        id: 'q-3',
        client: 'Estudio Alameda S.A.S.',
        number: 'C-0003',
        lines: const [
          QuoteLine(description: 'Diseño de marca', amount: 1800000),
          QuoteLine(description: 'Manual de uso', amount: 600000),
        ],
        chargesIva: true,
        issued: d(-5),
        validUntil: d(10),
        status: QuoteStatus.sent,
      ),
      Quote(
        id: 'q-2',
        client: 'Boutique Chapinero',
        number: 'C-0002',
        lines: const [
          QuoteLine(description: 'Sitio web de 5 secciones', amount: 3200000),
        ],
        chargesIva: true,
        issued: d(-2),
        validUntil: d(28),
        status: QuoteStatus.draft,
      ),
      Quote(
        id: 'q-1',
        client: 'Café Origen S.A.S.',
        number: 'C-0001',
        lines: const [
          QuoteLine(description: 'Fotografía de producto', amount: 750000),
        ],
        chargesIva: true,
        issued: d(-40),
        validUntil: d(-25),
        status: QuoteStatus.rejected,
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Facturas recurrentes
// ---------------------------------------------------------------------------

abstract interface class InvoiceTemplatesRepository {
  Stream<List<InvoiceTemplate>> watch();

  Future<InvoiceTemplate> create({
    required String client,
    required String concept,
    required int base,
    required bool chargesIva,
    required int dayOfMonth,
    required int termDays,
  });

  Future<void> setActive(String id, {required bool active});

  /// Registra que ya se emitió la factura de este mes.
  Future<void> markIssued(String id);

  Future<void> delete(String id);
}

final invoiceTemplatesRepositoryProvider = Provider<InvoiceTemplatesRepository>(
  (ref) {
    final repo = MockInvoiceTemplatesRepository(
      now: ref.watch(clockProvider),
      latency: ref.watch(mockLatencyProvider),
    );
    ref.onDispose(repo.dispose);
    return repo;
  },
);

final invoiceTemplatesProvider = StreamProvider<List<InvoiceTemplate>>(
  (ref) => ref.watch(invoiceTemplatesRepositoryProvider).watch(),
);

class MockInvoiceTemplatesRepository implements InvoiceTemplatesRepository {
  MockInvoiceTemplatesRepository({required this.now, required this.latency})
    : _store = MemoryList(initial: _seed(now()), latency: latency);

  final DateTime Function() now;
  final Duration latency;
  final MemoryList<InvoiceTemplate> _store;
  int _seq = 0;

  @override
  Stream<List<InvoiceTemplate>> watch() => _store.watch();

  @override
  Future<InvoiceTemplate> create({
    required String client,
    required String concept,
    required int base,
    required bool chargesIva,
    required int dayOfMonth,
    required int termDays,
  }) async {
    await _store.roundTrip();
    final t = InvoiceTemplate(
      id: 'tpl-${_seq++}',
      client: client.trim(),
      concept: concept.trim(),
      base: base,
      chargesIva: chargesIva,
      dayOfMonth: dayOfMonth,
      termDays: termDays,
    );
    _store.prepend(t);
    return t;
  }

  @override
  Future<void> setActive(String id, {required bool active}) async {
    await _store.roundTrip();
    _store.update((t) => t.id == id, (t) => t.copyWith(active: active));
  }

  @override
  Future<void> markIssued(String id) async {
    await _store.roundTrip();
    final t = dateOnly(now());
    _store.update((x) => x.id == id, (x) => x.copyWith(lastIssued: t));
  }

  @override
  Future<void> delete(String id) async {
    await _store.roundTrip();
    _store.removeWhere((t) => t.id == id);
  }

  void dispose() => _store.dispose();

  static List<InvoiceTemplate> _seed(DateTime now) {
    final today = dateOnly(now);
    return [
      InvoiceTemplate(
        id: 'tpl-studio',
        client: 'Studio Norte',
        concept: 'Mantenimiento web mensual',
        base: 800000,
        chargesIva: true,
        dayOfMonth: 5,
        termDays: 15,
        // Ya salió la de este mes: la próxima es en noviembre.
        lastIssued: DateTime(today.year, today.month, 5),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Enlaces de pago
// ---------------------------------------------------------------------------

abstract interface class PaymentLinksRepository {
  Stream<List<PaymentLink>> watch();

  Future<PaymentLink> create({
    required String concept,
    required int amount,
    required int validDays,
    String? client,
    String? invoiceId,
  });

  Future<void> cancel(String id);
}

final paymentLinksRepositoryProvider = Provider<PaymentLinksRepository>((ref) {
  final repo = MockPaymentLinksRepository(
    now: ref.watch(clockProvider),
    latency: ref.watch(mockLatencyProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

final paymentLinksProvider = StreamProvider<List<PaymentLink>>(
  (ref) => ref.watch(paymentLinksRepositoryProvider).watch(),
);

class MockPaymentLinksRepository implements PaymentLinksRepository {
  MockPaymentLinksRepository({required this.now, required this.latency})
    : _store = MemoryList(initial: _seed(now()), latency: latency);

  final DateTime Function() now;
  final Duration latency;
  final MemoryList<PaymentLink> _store;
  int _seq = 0;

  static String _url(String code) => 'https://pago.inti.app/l/$code';

  @override
  Stream<List<PaymentLink>> watch() => _store.watch();

  @override
  Future<PaymentLink> create({
    required String concept,
    required int amount,
    required int validDays,
    String? client,
    String? invoiceId,
  }) async {
    await _store.roundTrip();
    final today = dateOnly(now());
    final n = _seq++;
    final link = PaymentLink(
      id: 'pl-new-$n',
      concept: concept.trim(),
      amount: amount,
      createdAt: today,
      expiresAt: today.add(Duration(days: validDays)),
      status: PaymentLinkStatus.active,
      url: _url('q${(4096 + n * 37).toRadixString(36)}'),
      client: client,
      invoiceId: invoiceId,
    );
    _store.prepend(link);
    return link;
  }

  @override
  Future<void> cancel(String id) async {
    await _store.roundTrip();
    _store.update(
      (l) => l.id == id,
      (l) => l.copyWith(status: PaymentLinkStatus.cancelled),
    );
  }

  void dispose() => _store.dispose();

  static List<PaymentLink> _seed(DateTime now) {
    final today = dateOnly(now);
    DateTime d(int days) => today.add(Duration(days: days));
    return [
      PaymentLink(
        id: 'pl-3',
        concept: 'Anticipo del sitio web',
        client: 'Boutique Chapinero',
        amount: 1000000,
        createdAt: d(-2),
        expiresAt: d(12),
        status: PaymentLinkStatus.active,
        url: _url('qa7k2'),
      ),
      PaymentLink(
        id: 'pl-2',
        concept: 'Factura F-0040',
        client: 'Studio Norte',
        amount: 2380000,
        createdAt: d(-30),
        expiresAt: d(-15),
        status: PaymentLinkStatus.paid,
        url: _url('qb91x'),
        invoiceId: 'f-40',
      ),
      PaymentLink(
        id: 'pl-1',
        concept: 'Sesión de fotos',
        amount: 350000,
        createdAt: d(-45),
        expiresAt: d(-30),
        status: PaymentLinkStatus.active,
        url: _url('qc3m8'),
      ),
    ];
  }
}
