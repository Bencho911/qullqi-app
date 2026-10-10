import 'package:flutter_test/flutter_test.dart';
import 'package:qullqi/core/format/dates.dart';

void main() {
  final now = DateTime(2026, 10, 24, 14, 45); // sábado

  test('día largo en español', () {
    expect(Dates.longDay(now), 'Sábado, 24 de octubre');
  });

  test('hoy, ayer y fecha', () {
    expect(Dates.relativeDay(DateTime(2026, 10, 24, 1), now), 'Hoy');
    expect(Dates.relativeDay(DateTime(2026, 10, 23, 23, 59), now), 'Ayer');
    expect(Dates.relativeDay(DateTime(2026, 10, 20), now), '20 de octubre');
  });

  test('vencimientos', () {
    expect(Dates.dueLabel(DateTime(2026, 10, 24), now), 'Vence hoy');
    expect(Dates.dueLabel(DateTime(2026, 10, 25), now), 'Vence mañana');
    expect(Dates.dueLabel(DateTime(2026, 10, 27), now), 'Vence en 3 días');
    expect(Dates.dueLabel(DateTime(2026, 10, 23), now), 'Venció hace 1 día');
    expect(Dates.dueLabel(DateTime(2026, 10, 20), now), 'Venció hace 4 días');
  });

  test('hora con dos dígitos', () {
    expect(Dates.time(DateTime(2026, 1, 1, 9, 5)), '09:05');
  });
}
