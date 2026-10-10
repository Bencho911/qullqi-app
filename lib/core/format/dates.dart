import 'package:qullqi/core/clock/clock.dart';

/// Fechas en español de Colombia, sin depender de cargar datos regionales.
abstract final class Dates {
  static const _months = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', //
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];
  static const _weekdays = [
    'lunes',
    'martes',
    'miércoles',
    'jueves',
    'viernes',
    'sábado',
    'domingo',
  ];

  static String month(DateTime d) => _months[d.month - 1];

  /// "24 de octubre".
  static String dayMonth(DateTime d) => '${d.day} de ${month(d)}';

  /// "Sábado, 24 de octubre".
  static String longDay(DateTime d) {
    final w = _weekdays[d.weekday - 1];
    return '${w[0].toUpperCase()}${w.substring(1)}, ${dayMonth(d)}';
  }

  /// "14:32".
  static String time(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';

  /// "Hoy", "Ayer" o "22 de octubre".
  static String relativeDay(DateTime d, DateTime now) {
    final diff = daysBetween(d, now);
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    return dayMonth(d);
  }

  /// "Vence hoy", "Vence mañana", "Vence en 5 días", "Venció hace 2 días".
  static String dueLabel(DateTime due, DateTime now) {
    final days = daysBetween(now, due);
    if (days < 0) {
      final n = -days;
      return 'Venció hace $n ${n == 1 ? 'día' : 'días'}';
    }
    if (days == 0) return 'Vence hoy';
    if (days == 1) return 'Vence mañana';
    return 'Vence en $days días';
  }
}
