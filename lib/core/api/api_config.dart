import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dirección del backend, por ejemplo
/// `flutter run --dart-define=INTI_API_URL=http://10.0.2.2:3000`.
///
/// Sin ella la app usa los repositorios de demostración en memoria.
const String _apiUrl = String.fromEnvironment('INTI_API_URL');

final apiBaseUrlProvider = Provider<Uri?>(
  (ref) => _apiUrl.isEmpty ? null : Uri.parse(_apiUrl),
);
