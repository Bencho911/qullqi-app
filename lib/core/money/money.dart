import 'package:intl/intl.dart';

/// Formato de pesos colombianos: punto de miles, sin decimales.
///
/// El dinero se maneja siempre como `int` en pesos para evitar errores de
/// redondeo de `double`.
abstract final class Cop {
  static final NumberFormat _grouped = NumberFormat('#,##0', 'es_CO');

  /// 1200000 -> "$1.200.000"; -85400 -> "-$85.400".
  static String format(int pesos, {bool signed = false}) {
    final abs = _grouped.format(pesos.abs());
    if (pesos < 0) return '-\$$abs';
    if (signed && pesos > 0) return '+\$$abs';
    return '\$$abs';
  }

  /// Versión compacta para chips y ejes.
  ///
  /// 1250000 -> "$1,3 M"; 85400 -> "$85 mil".
  static String compact(int pesos) {
    final a = pesos.abs();
    final sign = pesos < 0 ? '-' : '';
    if (a >= 1000000) {
      final m = a / 1000000;
      final txt = m >= 10 || m == m.roundToDouble()
          ? m.round().toString()
          : m.toStringAsFixed(1).replaceAll('.', ',');
      return '$sign\$$txt M';
    }
    if (a >= 1000) return '$sign\$${(a / 1000).round()} mil';
    return format(pesos);
  }

  /// Texto para lectores de pantalla: "menos 85.400 pesos".
  static String spoken(int pesos) {
    final n = _grouped.format(pesos.abs());
    return '${pesos < 0 ? 'menos ' : ''}$n pesos';
  }

  /// Porcentaje con coma decimal: 3.7 -> "3,7 %".
  static String percent(double value, {int decimals = 0}) =>
      '${value.toStringAsFixed(decimals).replaceAll('.', ',')} %';
}

/// Lógica del teclado numérico: los dígitos se guardan como texto sin formato.
abstract final class AmountInput {
  static const int maxDigits = 11;

  static String press(String digits, String key) {
    if (key == 'del') {
      return digits.isEmpty ? '' : digits.substring(0, digits.length - 1);
    }
    if (digits.isEmpty && (key == '0' || key == '000')) return '';
    final next = '$digits$key';
    // Si no cabe, la tecla no hace nada: nunca se recorta lo ya escrito.
    return next.length > maxDigits ? digits : next;
  }

  static int value(String digits) => digits.isEmpty ? 0 : int.parse(digits);
}
