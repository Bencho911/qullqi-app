import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Demora simulada de los repositorios de prueba, para que los estados de
/// carga existan y se vean como con un backend real. Las pruebas la ponen
/// en cero.
final mockLatencyProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 700),
);
