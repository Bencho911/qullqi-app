import 'dart:async';

/// Flujo "en vivo" para repositorios en memoria: escucha los cambios desde el
/// primer instante y, tras la demora simulada, entrega el estado actual. Así
/// ningún cambio se pierde entre la carga inicial y la suscripción.
Stream<T> liveStream<T>({
  required Stream<T> changes,
  required T Function() current,
  required Duration latency,
}) {
  late final StreamController<T> out;
  StreamSubscription<T>? sub;
  out = StreamController<T>(
    onListen: () {
      sub = changes.listen(out.add, onError: out.addError);
      unawaited(
        Future<void>.delayed(latency).then((_) {
          if (!out.isClosed) out.add(current());
        }),
      );
    },
    onCancel: () async {
      await sub?.cancel();
      await out.close();
    },
  );
  return out.stream;
}
