import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Hora actual inyectable: las pruebas fijan una fecha y todo lo que depende
/// de "hoy" (vencimientos, "Ayer", saludos) se vuelve reproducible.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Fecha sin hora (medianoche local).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Días calendario entre dos fechas (sin importar la hora).
int daysBetween(DateTime from, DateTime to) =>
    dateOnly(to).difference(dateOnly(from)).inDays;
