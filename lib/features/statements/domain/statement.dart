import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';

/// Tamaño máximo de un extracto (los de un año caben de sobra).
const int maxStatementBytes = 10 * 1024 * 1024;

/// Formatos que acepta la importación.
enum StatementFormat {
  csv,
  excel,
  pdf;

  static const extensions = ['pdf', 'xlsx', 'xls', 'csv'];

  /// `null` si el archivo no es de un formato que leamos.
  static StatementFormat? of(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return null;
    return switch (fileName.substring(dot + 1).toLowerCase()) {
      'csv' || 'txt' => StatementFormat.csv,
      'xlsx' || 'xls' => StatementFormat.excel,
      'pdf' => StatementFormat.pdf,
      _ => null,
    };
  }
}

/// El archivo que eligió la persona.
@immutable
class StatementFile {
  const StatementFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  StatementFormat? get format => StatementFormat.of(name);
}

/// Un renglón del extracto.
@immutable
class StatementLine {
  const StatementLine({
    required this.date,
    required this.description,
    required this.amount,
  });

  final DateTime date;
  final String description;

  /// Con signo: negativo si salió de la cuenta.
  final int amount;

  @override
  bool operator ==(Object other) =>
      other is StatementLine &&
      other.date == date &&
      other.description == description &&
      other.amount == amount;

  @override
  int get hashCode => Object.hash(date, description, amount);
}

enum StatementProblem {
  unsupported(
    'Ese archivo no es un extracto que podamos leer',
    'Usa el PDF, el Excel (.xlsx) o el CSV que descargas de tu banco.',
  ),
  tooLarge(
    'El archivo es muy grande',
    'Descarga el extracto de menos meses (hasta 10 MB) e inténtalo de nuevo.',
  ),
  noMovements(
    'No encontramos movimientos en el archivo',
    'Revisa que sea el extracto de la cuenta y no un certificado o un '
        'resumen.',
  ),
  protected(
    'El PDF tiene clave',
    'Ábrelo en tu banco, descárgalo sin clave o usa el Excel o CSV.',
  ),
  failed(
    'No pudimos leer el extracto',
    'Revisa tu conexión a internet e inténtalo de nuevo.',
  );

  StatementProblem(this.title, this.message);

  final String title;
  final String message;
}

class StatementException implements Exception {
  const StatementException(this.problem);

  final StatementProblem problem;

  @override
  String toString() => 'StatementException(${problem.name})';
}

/// Texto del archivo: UTF-8 y, si no lo es, Latin-1 (común en los CSV de
/// bancos colombianos exportados desde Excel).
String decodeStatementText(Uint8List bytes) {
  var start = 0;
  // Marca de orden de bytes de UTF-8.
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    start = 3;
  }
  final body = bytes.sublist(start);
  try {
    return utf8.decode(body);
  } on FormatException {
    return latin1.decode(body);
  }
}

/// Minúsculas y sin tildes, para reconocer encabezados.
String _plain(String s) {
  const from = 'áéíóúüñ';
  const to = 'aeiouun';
  final lower = s.toLowerCase().trim();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    final i = from.indexOf(ch);
    out.write(i < 0 ? ch : to[i]);
  }
  return out.toString();
}

/// Divide un renglón CSV respetando las comillas.
List<String> _splitCsv(String line, String sep) {
  final cells = <String>[];
  final cell = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        cell.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == sep && !quoted) {
      cells.add(cell.toString().trim());
      cell.clear();
    } else {
      cell.write(ch);
    }
  }
  cells.add(cell.toString().trim());
  return cells;
}

/// Monto en pesos desde "1.234.567,89", "-85400", "$ 1,234.00" o "(3.500)".
/// `null` si no es un número.
int? parseStatementAmount(String raw) {
  var s = raw.replaceAll(RegExp(r'[\s$]|COP', caseSensitive: false), '');
  if (s.isEmpty) return null;
  var negative = false;
  if (s.startsWith('(') && s.endsWith(')')) {
    negative = true;
    s = s.substring(1, s.length - 1);
  }
  if (s.endsWith('-')) {
    negative = true;
    s = s.substring(0, s.length - 1);
  }
  if (s.startsWith('-')) {
    negative = !negative;
    s = s.substring(1);
  } else if (s.startsWith('+')) {
    s = s.substring(1);
  }
  if (!RegExp(r'^[\d.,]+$').hasMatch(s)) return null;
  final lastDot = s.lastIndexOf('.');
  final lastComma = s.lastIndexOf(',');
  String? decimalSep;
  if (lastDot >= 0 && lastComma >= 0) {
    decimalSep = lastDot > lastComma ? '.' : ',';
  } else if (lastComma >= 0 || lastDot >= 0) {
    final sep = lastComma >= 0 ? ',' : '.';
    final count = sep.allMatches(s).length;
    final tail = s.length - s.lastIndexOf(sep) - 1;
    // Un solo separador seguido de 1 o 2 cifras es decimal ("85400,50");
    // con 3 cifras o repetido, es de miles ("85.400", "1.234.567").
    if (count == 1 && tail <= 2) decimalSep = sep;
  }
  String whole;
  var fraction = '';
  if (decimalSep == null) {
    whole = s.replaceAll(RegExp('[.,]'), '');
  } else {
    final at = s.lastIndexOf(decimalSep);
    whole = s.substring(0, at).replaceAll(RegExp('[.,]'), '');
    fraction = s.substring(at + 1);
  }
  if (whole.isEmpty && fraction.isEmpty) return null;
  final value = double.parse(
    '${whole.isEmpty ? '0' : whole}.${fraction.isEmpty ? '0' : fraction}',
  ).round();
  return negative ? -value : value;
}

/// Fecha desde "24/10/2026", "24-10-26", "2026-10-24" o "20261024".
DateTime? parseStatementDate(String raw) {
  final s = raw.trim().split(RegExp(r'\s+')).first;
  Match? m;
  if ((m = RegExp(r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$').firstMatch(s)) !=
      null) {
    return _date(m!.group(1)!, m.group(2)!, m.group(3)!);
  }
  if ((m = RegExp(r'^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$').firstMatch(s)) !=
      null) {
    var y = m!.group(3)!;
    if (y.length == 2) y = '20$y';
    return _date(y, m.group(2)!, m.group(1)!);
  }
  if ((m = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(s)) != null) {
    return _date(m!.group(1)!, m.group(2)!, m.group(3)!);
  }
  return null;
}

DateTime? _date(String y, String m, String d) {
  final year = int.parse(y);
  final month = int.parse(m);
  final day = int.parse(d);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  // Descarta fechas imposibles como el 31 de febrero.
  return date.month == month ? date : null;
}

const _dateHeaders = ['fecha'];
const _descriptionHeaders = [
  'descripcion',
  'concepto',
  'detalle',
  'movimiento',
  'referencia',
  'comercio',
];
const _amountHeaders = ['valor', 'monto', 'importe'];
const _debitHeaders = ['debito', 'cargo', 'retiro', 'salida'];
const _creditHeaders = ['credito', 'abono', 'deposito', 'entrada'];

int _column(List<String> headers, List<String> names) =>
    headers.indexWhere((h) => names.any(h.contains));

/// Lee un extracto CSV. Reconoce los encabezados en español (Fecha,
/// Descripción, Valor, o Débito/Crédito), el separador (`;`, `,` o
/// tabulador) y los montos en formato colombiano. Los renglones que no son
/// movimientos (saldos, totales) se ignoran.
List<StatementLine> parseCsvStatement(String text) {
  final rows = const LineSplitter()
      .convert(text)
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (rows.isEmpty) {
    throw const StatementException(StatementProblem.noMovements);
  }
  final sample = rows.take(10).join('\n');
  final sep = [
    ';',
    '\t',
    ',',
  ].reduce((a, b) => sample.split(b).length > sample.split(a).length ? b : a);

  // El encabezado puede venir después de unas líneas con datos del banco.
  for (var h = 0; h < rows.length && h < 20; h++) {
    final headers = _splitCsv(rows[h], sep).map(_plain).toList();
    final date = _column(headers, _dateHeaders);
    final description = _column(headers, _descriptionHeaders);
    final amount = _column(headers, _amountHeaders);
    final debit = _column(headers, _debitHeaders);
    final credit = _column(headers, _creditHeaders);
    if (date < 0 || (amount < 0 && debit < 0 && credit < 0)) continue;

    final lines = <StatementLine>[];
    for (final row in rows.skip(h + 1)) {
      final cells = _splitCsv(row, sep);
      String cell(int i) => i >= 0 && i < cells.length ? cells[i] : '';
      final when = parseStatementDate(cell(date));
      if (when == null) continue;
      int? value;
      if (amount >= 0) {
        value = parseStatementAmount(cell(amount));
      } else {
        final out = parseStatementAmount(cell(debit))?.abs() ?? 0;
        final into = parseStatementAmount(cell(credit))?.abs() ?? 0;
        value = into - out;
      }
      if (value == null || value == 0) continue;
      final text = cell(description);
      lines.add(
        StatementLine(
          date: when,
          description: text.isEmpty ? 'Movimiento' : tidyDescription(text),
          amount: value,
        ),
      );
    }
    if (lines.isEmpty) break;
    return lines;
  }
  throw const StatementException(StatementProblem.noMovements);
}

/// "COMPRA EN  EXITO CALLE 80" → "Compra en Exito Calle 80".
String tidyDescription(String raw) {
  final s = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s != s.toUpperCase()) return s;
  const small = {'en', 'de', 'del', 'la', 'el', 'a', 'y', 'por', 'con'};
  final words = s.toLowerCase().split(' ');
  return [
    for (final (i, w) in words.indexed)
      if (i > 0 && small.contains(w))
        w
      else if (w.isEmpty)
        w
      else
        '${w[0].toUpperCase()}${w.substring(1)}',
  ].join(' ');
}

const _categoryWords = {
  'mercado': [
    'exito',
    'carulla',
    'jumbo',
    'olimpica',
    'ara ',
    'd1',
    'makro',
    'mercado',
  ],
  'transporte': [
    'uber',
    'didi',
    'cabify',
    'terpel',
    'texaco',
    'primax',
    'peaje',
    'gasolina',
    'transmilenio',
  ],
  'salidas': ['juan valdez', 'tostao', 'restaurante', 'rappi', 'cafe', 'bar '],
  'salud': ['drogueria', 'farmacia', 'cruz verde', 'colsubsidio', 'eps'],
  'hogar': ['arriendo', 'administracion', 'enel', 'codensa', 'epm', 'vanti'],
  'software': ['google', 'microsoft', 'adobe', 'figma', 'aws', 'github'],
  'suscripciones': ['netflix', 'spotify', 'disney', 'youtube', 'claro', 'tigo'],
};

/// Palabras de un traslado entre cuentas propias o un pago de tarjeta.
const _transferWords = [
  'traslado',
  'transferencia a cuenta propia',
  'pago tarjeta',
  'pago tc',
  'abono tarjeta',
];

/// Categoría sugerida para un renglón; la persona puede cambiarla después.
String guessCategory(StatementLine line) {
  final text = ' ${_plain(line.description)} ';
  for (final MapEntry(key: id, value: words) in _categoryWords.entries) {
    if (words.any(text.contains)) return id;
  }
  if (line.amount > 0) return Categories.transferIn.id;
  return Categories.other.id;
}

/// Si el renglón parece plata entre cuentas propias (se marca para revisar).
bool looksLikeTransfer(StatementLine line) {
  final text = _plain(line.description);
  return _transferWords.any(text.contains);
}

/// Un renglón listo para importar: si ya estaba en Qullqi, viene marcado.
@immutable
class ImportCandidate {
  const ImportCandidate({required this.line, required this.duplicate});

  final StatementLine line;

  /// Ya hay un movimiento de la cuenta con la misma fecha y el mismo valor.
  final bool duplicate;
}

/// Compara el extracto con lo que ya tiene la cuenta, del más reciente al
/// más antiguo. Cada movimiento existente cubre a un solo renglón: dos
/// compras iguales el mismo día no se confunden con una.
List<ImportCandidate> matchStatement(
  List<StatementLine> lines,
  List<Transaction> existing,
  String accountId,
) {
  final pool = [
    for (final t in existing)
      if (t.accountId == accountId) (dateOnly(t.date), t.signedAmount),
  ];
  final sorted = [...lines]..sort((a, b) => b.date.compareTo(a.date));
  return [
    for (final l in sorted)
      ImportCandidate(
        line: l,
        duplicate: pool.remove((dateOnly(l.date), l.amount)),
      ),
  ];
}
