import 'package:intl/intl.dart';

/// Monedas en que se puede tener una cuenta.
enum Currency {
  cop('COP', 'Pesos colombianos'),
  usd('USD', 'Dólares'),
  eur('EUR', 'Euros');

  Currency(this.code, this.label);

  final String code;
  final String label;

  /// Los pesos colombianos son la moneda de la app: todo se suma en ellos.
  bool get isHome => this == Currency.cop;
}

/// Tasas de cambio de referencia.
///
/// Son valores de demostración fijos: el backend traerá la TRM y las tasas
/// del día. Cada cuenta guarda la tasa con que se convirtió.
abstract final class ExchangeRates {
  static const Map<Currency, double> _pesosPerUnit = {
    Currency.cop: 1,
    Currency.usd: 4100,
    Currency.eur: 4450,
  };

  /// Pesos por una unidad de [c].
  static double of(Currency c) => _pesosPerUnit[c]!;

  /// Cuántos pesos son [amount] unidades de [c].
  static int toCop(num amount, Currency c) => (amount * of(c)).round();
}

final NumberFormat _grouped = NumberFormat('#,##0', 'es_CO');

/// "USD 250" o "EUR 1.200".
String formatForeign(int amount, Currency c) =>
    '${c.code} ${_grouped.format(amount)}';
