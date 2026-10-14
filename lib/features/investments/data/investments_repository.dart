import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/data/latency.dart';
import 'package:inti/core/data/live_stream.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart'
    show ConnectionFailure;
import 'package:inti/features/accounts/domain/account.dart';
import 'package:inti/features/investments/domain/investment.dart';
import 'package:inti/features/investments/domain/investment_source.dart';

/// Fuente de las inversiones de la persona. La implementación real hablará
/// con el agregador; la app solo depende de esta interfaz.
///
/// Inti solo **muestra** lo invertido: no compra ni vende.
abstract interface class InvestmentsRepository {
  /// Emite la lista actual y cada cambio.
  Stream<List<Investment>> watch();

  /// Pide a las entidades el valor de hoy.
  Future<void> sync();

  /// Conecta una entidad (solo lectura). Devuelve lo que trajo.
  /// Lanza [ConnectionFailure] si la entidad no responde o la rechaza.
  Future<List<Investment>> connect(InvestmentSource source);

  /// Renueva el permiso de una inversión cuyo acceso venció.
  Future<void> reconnect(String id);

  /// Agrega una inversión registrada a mano.
  Future<Investment> addManual({
    required String name,
    required InvestmentKind kind,
    required int invested,
    required int value,
    required Ownership ownership,
    String? institution,
    DateTime? maturity,
    double? annualRate,
  });

  /// Cambia lo que vale hoy una inversión registrada a mano.
  Future<void> updateValue(String id, int value);

  /// La quita de Inti (y revoca el permiso si venía de una entidad).
  Future<void> remove(String id);
}

final investmentsRepositoryProvider = Provider<InvestmentsRepository>((ref) {
  final repo = MockInvestmentsRepository(
    now: ref.watch(clockProvider),
    latency: ref.watch(mockLatencyProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

/// Inversiones de la persona, en vivo.
final investmentsProvider = StreamProvider<List<Investment>>(
  (ref) => ref.watch(investmentsRepositoryProvider).watch(),
);

/// Datos de prueba en memoria.
class MockInvestmentsRepository implements InvestmentsRepository {
  MockInvestmentsRepository({required this.now, required this.latency})
    : _items = _seed(now());

  final DateTime Function() now;
  final Duration latency;
  List<Investment> _items;
  final _changes = StreamController<List<Investment>>.broadcast();
  int _seq = 0;

  void _emit() => _changes.add(List.unmodifiable(_items));

  @override
  Stream<List<Investment>> watch() => liveStream(
    changes: _changes.stream,
    current: () => _items,
    latency: latency,
  );

  @override
  Future<void> sync() async {
    await Future<void>.delayed(latency * 2);
    final t = now();
    _items = [
      for (final i in _items)
        if (i.status == ConnectionStatus.connected)
          i.copyWith(lastSync: t)
        else
          i,
    ];
    _emit();
  }

  @override
  Future<List<Investment>> connect(InvestmentSource source) async {
    await Future<void>.delayed(latency * 3);
    if (!source.available) {
      throw ConnectionFailure(
        '${source.name} aún no tiene conexión automática.',
      );
    }
    // Simulación: Porvenir no responde (para ver el estado de error).
    if (source.id == 'porvenir') {
      throw const ConnectionFailure(
        'Porvenir no respondió. Puede ser algo temporal de su lado.',
      );
    }
    final t = now();
    final created = [
      for (final (i, kind) in source.kinds.indexed)
        Investment(
          id: '${source.id}-${_seq++}',
          name: switch (kind) {
            InvestmentKind.cdt => 'CDT en ${source.name}',
            InvestmentKind.fund => 'Fondo en ${source.name}',
            _ => '${kind.label} en ${source.name}',
          },
          kind: kind,
          ownership: Ownership.personal,
          institution: source.name,
          badge: source.badge,
          invested: 1000000 + source.name.length * 100000 + i * 250000,
          value:
              (1000000 + source.name.length * 100000 + i * 250000) * 104 ~/ 100,
          openedOn: DateTime(t.year, t.month - 3, t.day),
          maturity: kind == InvestmentKind.cdt
              ? DateTime(t.year, t.month + 3, t.day)
              : null,
          annualRate: kind == InvestmentKind.cdt ? 0.095 : null,
          status: ConnectionStatus.connected,
          lastSync: t,
        ),
    ];
    _items = [..._items, ...created];
    _emit();
    return created;
  }

  @override
  Future<void> reconnect(String id) async {
    await Future<void>.delayed(latency * 3);
    final t = now();
    _items = [
      for (final i in _items)
        if (i.id == id)
          i.copyWith(
            status: ConnectionStatus.connected,
            lastSync: t,
            // Al renovar el permiso llega el valor de hoy.
            value: i.value * 101 ~/ 100,
          )
        else
          i,
    ];
    _emit();
  }

  @override
  Future<Investment> addManual({
    required String name,
    required InvestmentKind kind,
    required int invested,
    required int value,
    required Ownership ownership,
    String? institution,
    DateTime? maturity,
    double? annualRate,
  }) async {
    await Future<void>.delayed(latency);
    final t = now();
    final place = institution?.trim() ?? '';
    final item = Investment(
      id: 'manual-${_seq++}',
      name: name.trim(),
      kind: kind,
      ownership: ownership,
      institution: place.isEmpty ? null : place,
      invested: invested,
      value: value,
      openedOn: dateOnly(t),
      maturity: maturity,
      annualRate: annualRate,
      status: ConnectionStatus.manual,
      lastSync: t,
    );
    _items = [..._items, item];
    _emit();
    return item;
  }

  @override
  Future<void> updateValue(String id, int value) async {
    await Future<void>.delayed(latency);
    final t = now();
    _items = [
      for (final i in _items)
        if (i.id == id) i.copyWith(value: value, lastSync: t) else i,
    ];
    _emit();
  }

  @override
  Future<void> remove(String id) async {
    await Future<void>.delayed(latency);
    _items = _items.where((i) => i.id != id).toList();
    _emit();
  }

  void dispose() => unawaited(_changes.close());

  static List<Investment> _seed(DateTime now) {
    DateTime inDays(int d) => dateOnly(now).add(Duration(days: d));
    return [
      Investment(
        id: 'cdt-bancolombia',
        name: 'CDT a 180 días',
        kind: InvestmentKind.cdt,
        ownership: Ownership.personal,
        institution: 'Bancolombia',
        badge: 'BC',
        invested: 3000000,
        value: 3087500,
        openedOn: inDays(-120),
        maturity: inDays(60),
        annualRate: 0.098,
        status: ConnectionStatus.connected,
        lastSync: now.subtract(const Duration(minutes: 5)),
      ),
      Investment(
        id: 'fondo-tyba',
        name: 'Fondo de inversión colectiva',
        kind: InvestmentKind.fund,
        ownership: Ownership.personal,
        institution: 'Tyba',
        badge: 'TY',
        invested: 1500000,
        value: 1562300,
        openedOn: inDays(-200),
        status: ConnectionStatus.connected,
        lastSync: now.subtract(const Duration(minutes: 30)),
      ),
      Investment(
        id: 'acciones-trii',
        name: 'Acciones y ETF',
        kind: InvestmentKind.stock,
        ownership: Ownership.personal,
        institution: 'Trii',
        badge: 'TR',
        invested: 2000000,
        value: 1874000,
        openedOn: inDays(-90),
        status: ConnectionStatus.connected,
        lastSync: now.subtract(const Duration(hours: 1)),
      ),
      Investment(
        id: 'cripto-bitcoin',
        name: 'Bitcoin',
        kind: InvestmentKind.crypto,
        ownership: Ownership.personal,
        invested: 500000,
        value: 640000,
        openedOn: inDays(-150),
        status: ConnectionStatus.manual,
        lastSync: now.subtract(const Duration(days: 3)),
      ),
      Investment(
        id: 'pension-proteccion',
        name: 'Pensión voluntaria',
        kind: InvestmentKind.pension,
        ownership: Ownership.personal,
        institution: 'Protección',
        badge: 'PR',
        invested: 4000000,
        value: 4310000,
        openedOn: inDays(-400),
        status: ConnectionStatus.needsReconnect,
        lastSync: now.subtract(const Duration(days: 2)),
      ),
      Investment(
        id: 'cdt-confiar',
        name: 'CDT Confiar',
        kind: InvestmentKind.cdt,
        ownership: Ownership.business,
        institution: 'Confiar',
        invested: 5000000,
        value: 5120000,
        openedOn: inDays(-170),
        maturity: inDays(6),
        annualRate: 0.105,
        status: ConnectionStatus.manual,
        lastSync: now.subtract(const Duration(days: 10)),
      ),
    ];
  }
}
