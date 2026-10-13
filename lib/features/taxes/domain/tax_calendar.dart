import 'package:flutter/foundation.dart' show immutable;

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';

enum TaxDocumentType {
  cedula('Cédula'),
  nit('NIT');

  TaxDocumentType(this.label);

  final String label;
}

/// Documento con el que se asignan las fechas de la DIAN: sus últimos
/// dígitos deciden el día.
@immutable
class TaxDocument {
  const TaxDocument({required this.type, required this.number});

  factory TaxDocument.fromJson(Map<String, dynamic> j) => TaxDocument(
    type: TaxDocumentType.values.firstWhere(
      (t) => t.name == j['type'],
      orElse: () => TaxDocumentType.cedula,
    ),
    number: j['number'] as String,
  );

  final TaxDocumentType type;

  /// Solo dígitos, sin dígito de verificación ni puntos.
  final String number;

  bool get isValid => number.length >= 5;

  int get lastDigit => int.parse(number[number.length - 1]);

  /// Los dos últimos dígitos; "00" va de último.
  int get order {
    final two = number.length >= 2
        ? int.parse(number.substring(number.length - 2))
        : lastDigit;
    return two == 0 ? 100 : two;
  }

  /// "Cédula •••• 4821".
  String get masked =>
      '${type.label} •••• ${number.substring(number.length - 4)}';

  Map<String, dynamic> toJson() => {'type': type.name, 'number': number};
}

enum ObligationKind { renta, retencion, pila, prima, cesantias, intereses }

/// Algo que hay que presentar o pagar en una fecha.
@immutable
class Obligation {
  const Obligation({
    required this.kind,
    required this.title,
    required this.detail,
    required this.due,
    this.ifEmployer = false,
  });

  final ObligationKind kind;
  final String title;
  final String detail;
  final DateTime due;

  /// Solo aplica si tienes empleados.
  final bool ifEmployer;

  String get id => '${kind.name}:${due.year}-${due.month}-${due.day}';
}

/// El día hábil número [n] del mes (lunes a viernes; los festivos no se
/// descuentan: las fechas son de referencia).
DateTime nthBusinessDay(int year, int month, int n) {
  var d = DateTime(year, month);
  var count = 0;
  while (true) {
    if (d.weekday <= DateTime.friday) {
      count++;
      if (count == n) return d;
    }
    d = d.add(const Duration(days: 1));
  }
}

DateTime _addBusinessDays(DateTime from, int n) {
  var d = from;
  var left = n;
  while (left > 0) {
    d = d.add(const Duration(days: 1));
    if (d.weekday <= DateTime.friday) left--;
  }
  return d;
}

/// Calendario de referencia según tu documento.
///
/// Sigue la mecánica de la DIAN (el día lo decide el último dígito o los dos
/// últimos), pero las fechas exactas las publica cada año un decreto: por eso
/// toda fecha se muestra como "de referencia" y el backend las traerá
/// oficiales.
List<Obligation> buildTaxCalendar({
  required TaxDocument document,
  required DateTime now,
  required bool hasBusiness,
}) {
  final today = dateOnly(now);
  final out = <Obligation>[];

  // Renta de personas naturales: agosto a octubre, de a dos dígitos por día.
  for (final year in [now.year, now.year + 1]) {
    final start = nthBusinessDay(year, 8, 8);
    final due = _addBusinessDays(start, (document.order - 1) ~/ 2);
    if (!due.isBefore(today)) {
      out.add(
        Obligation(
          kind: ObligationKind.renta,
          title: 'Declaración de renta',
          detail: 'Año gravable ${year - 1}',
          due: due,
        ),
      );
      break;
    }
  }

  if (hasBusiness) {
    // Mensuales: este mes y el siguiente, los que no hayan pasado.
    for (var k = 0; k < 3; k++) {
      final m = DateTime(now.year, now.month + k);
      final retention = nthBusinessDay(
        m.year,
        m.month,
        9 + (document.lastDigit == 0 ? 9 : document.lastDigit - 1),
      );
      if (!retention.isBefore(today)) {
        out.add(
          Obligation(
            kind: ObligationKind.retencion,
            title: 'Retención en la fuente',
            detail: 'Mes anterior',
            due: retention,
          ),
        );
      }
      final pila = nthBusinessDay(
        m.year,
        m.month,
        1 + (document.order - 1) ~/ 8,
      );
      if (!pila.isBefore(today)) {
        out.add(
          Obligation(
            kind: ObligationKind.pila,
            title: 'Seguridad social (PILA)',
            detail: 'Aportes del mes',
            due: pila,
          ),
        );
      }
    }
    // Fechas fijas de ley para quien tiene empleados.
    DateTime nextFixed(int month, int day) {
      final d = DateTime(now.year, month, day);
      return d.isBefore(today) ? DateTime(now.year + 1, month, day) : d;
    }

    out
      ..add(
        Obligation(
          kind: ObligationKind.prima,
          title: 'Prima de servicios',
          detail: 'Primer semestre',
          due: nextFixed(6, 30),
          ifEmployer: true,
        ),
      )
      ..add(
        Obligation(
          kind: ObligationKind.prima,
          title: 'Prima de servicios',
          detail: 'Segundo semestre',
          due: nextFixed(12, 20),
          ifEmployer: true,
        ),
      )
      ..add(
        Obligation(
          kind: ObligationKind.intereses,
          title: 'Intereses de cesantías',
          detail: 'A tus empleados',
          due: nextFixed(1, 31),
          ifEmployer: true,
        ),
      )
      ..add(
        Obligation(
          kind: ObligationKind.cesantias,
          title: 'Consignar cesantías',
          detail: 'Al fondo de tus empleados',
          due: nextFixed(2, 14),
          ifEmployer: true,
        ),
      );
  }
  // Una de cada tipo y fecha, la más cercana primero.
  final seen = <String>{};
  return out.where((o) => seen.add('${o.title}|${o.detail}|${o.due}')).toList()
    ..sort((a, b) => a.due.compareTo(b.due));
}

// ---------------------------------------------------------------------------
// 4x1000
// ---------------------------------------------------------------------------

/// Tarifa del gravamen a los movimientos financieros: 4 por mil.
const int gmfPerThousand = 4;

/// Cuánto se estima que pagaste del 4x1000 en el mes. Sin descontar la cuenta
/// exenta (hasta 350 UVT al mes), que depende de que la hayas marcado en tu
/// banco.
@immutable
class GmfEstimate {
  const GmfEstimate({required this.base, required this.estimated});

  factory GmfEstimate.of(
    List<Transaction> all, {
    required Set<String> debitAccountIds,
    required Scope scope,
    required DateTime now,
  }) {
    final base = all
        .where(
          (t) =>
              t.kind == TransactionKind.expense &&
              debitAccountIds.contains(t.accountId) &&
              t.ownership.visibleIn(scope) &&
              t.date.year == now.year &&
              t.date.month == now.month,
        )
        .fold<int>(0, (s, t) => s + t.amount);
    return GmfEstimate(base: base, estimated: base * gmfPerThousand ~/ 1000);
  }

  /// Lo que salió de tus cuentas (no de tarjetas) en el mes.
  final int base;
  final int estimated;
}

// ---------------------------------------------------------------------------
// Resumen para la renta
// ---------------------------------------------------------------------------

/// Ingresos y gastos del año que ayudan a armar la declaración de renta.
@immutable
class YearSummary {
  const YearSummary({
    required this.year,
    required this.income,
    required this.incomeByCategory,
    required this.health,
  });

  factory YearSummary.of(
    List<Transaction> all, {
    required Scope scope,
    required DateTime now,
  }) {
    final inYear = all.where(
      (t) =>
          t.date.year == now.year &&
          t.ownership.visibleIn(scope) &&
          !t.needsReview,
    );
    final incomes = inYear.where((t) => t.kind == TransactionKind.income);
    final byCat = <String, int>{};
    for (final t in incomes) {
      byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amount;
    }
    final ranked = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return YearSummary(
      year: now.year,
      income: incomes.fold(0, (s, t) => s + t.amount),
      incomeByCategory: [
        for (final e in ranked) (Categories.byId(e.key), e.value),
      ],
      health: inYear
          .where(
            (t) =>
                t.kind == TransactionKind.expense &&
                t.categoryId == Categories.health.id,
          )
          .fold(0, (s, t) => s + t.amount),
    );
  }

  final int year;
  final int income;

  /// De mayor a menor.
  final List<(Category, int)> incomeByCategory;
  final int health;
}
