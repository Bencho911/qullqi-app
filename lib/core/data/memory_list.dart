import 'dart:async';

import 'package:inti/core/data/live_stream.dart';

/// Lista en memoria que se puede observar: la base de los repositorios de
/// demostración. El backend real reemplaza cada repositorio entero; la app
/// solo conoce sus interfaces.
class MemoryList<T> {
  MemoryList({required List<T> initial, required this.latency})
    : _items = initial;

  /// Demora simulada de la red.
  final Duration latency;
  List<T> _items;
  final _changes = StreamController<List<T>>.broadcast();

  List<T> get items => List.unmodifiable(_items);

  /// Emite la lista actual (tras la demora) y cada cambio.
  Stream<List<T>> watch() => liveStream(
    changes: _changes.stream,
    current: () => List.unmodifiable(_items),
    latency: latency,
  );

  /// Pausa que imita la ida y vuelta al servidor.
  Future<void> roundTrip({int divisor = 2}) =>
      Future<void>.delayed(latency ~/ divisor);

  void _set(List<T> next) {
    _items = next;
    _changes.add(List.unmodifiable(next));
  }

  /// Agrega al principio.
  void prepend(T item) => _set([item, ..._items]);

  /// Reemplaza los elementos que cumplan [test] con [change].
  void update(bool Function(T) test, T Function(T) change) => _set([
    for (final i in _items)
      if (test(i)) change(i) else i,
  ]);

  void removeWhere(bool Function(T) test) =>
      _set(_items.where((i) => !test(i)).toList());

  void dispose() => unawaited(_changes.close());
}
