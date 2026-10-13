import 'package:flutter/foundation.dart' show immutable;

import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/features/business/domain/bill.dart';
import 'package:qullqi/features/business/domain/business.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';

enum InviteStatus {
  pending('Invitación enviada'),
  active('Con acceso'),
  revoked('Sin acceso');

  InviteStatus(this.label);

  final String label;
}

/// Alguien a quien le diste acceso de solo lectura a tu negocio.
@immutable
class AccountantInvite {
  const AccountantInvite({
    required this.id,
    required this.email,
    required this.createdAt,
    required this.status,
  });

  final String id;
  final String email;
  final DateTime createdAt;
  final InviteStatus status;

  AccountantInvite copyWith({InviteStatus? status}) => AccountantInvite(
    id: id,
    email: email,
    createdAt: createdAt,
    status: status ?? this.status,
  );
}

/// Periodos que se pueden exportar.
enum ExportPeriod {
  thisMonth('Este mes'),
  lastMonth('Mes pasado'),
  thisYear('Este año');

  ExportPeriod(this.label);

  final String label;

  bool contains(DateTime d, DateTime now) => switch (this) {
    ExportPeriod.thisMonth => d.year == now.year && d.month == now.month,
    ExportPeriod.lastMonth =>
      d.year == DateTime(now.year, now.month - 1).year &&
          d.month == DateTime(now.year, now.month - 1).month,
    ExportPeriod.thisYear => d.year == now.year,
  };
}

/// Cabecera del archivo para el contador.
const accountantCsvHeader =
    'tipo,fecha,descripcion,tercero,valor_base,iva,total,estado';

String _cell(String v) {
  final needsQuotes =
      v.contains(',') || v.contains('"') || v.contains('\n') || v.contains(';');
  final escaped = v.replaceAll('"', '""');
  return needsQuotes ? '"$escaped"' : escaped;
}

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Resultado de armar el archivo.
@immutable
class AccountantExport {
  const AccountantExport({required this.csv, required this.rows});

  final String csv;

  /// Filas sin contar la cabecera.
  final int rows;
}

/// Arma un CSV con lo del negocio del periodo: ventas (facturas), cuentas
/// por pagar y movimientos de las cuentas del negocio. No incluye saldos ni
/// datos de acceso.
AccountantExport buildAccountantExport({
  required List<Invoice> invoices,
  required List<Bill> bills,
  required List<Transaction> transactions,
  required ExportPeriod period,
  required DateTime now,
}) {
  final rows = <(DateTime, List<String>)>[];
  for (final i in invoices.where((i) => period.contains(i.issued, now))) {
    final state = i.paidOn == null ? 'por cobrar' : 'pagada';
    rows.add((
      i.issued,
      [
        'venta',
        _date(i.issued),
        'Factura ${i.number}',
        i.client,
        '${i.base}',
        '${i.iva}',
        '${i.total}',
        state,
      ],
    ));
  }
  for (final b in bills.where((b) => period.contains(b.due, now))) {
    final state = b.paidOn == null ? 'por pagar' : 'pagada';
    rows.add((
      b.due,
      [
        'compra',
        _date(b.due),
        b.concept,
        b.supplier,
        '${b.amount}',
        '',
        '${b.amount}',
        state,
      ],
    ));
  }
  for (final t in transactions.where(
    (t) =>
        t.ownership == Ownership.business &&
        t.kind != TransactionKind.transfer &&
        !t.needsReview &&
        period.contains(t.date, now),
  )) {
    final type = t.kind == TransactionKind.income ? 'ingreso' : 'gasto';
    rows.add((
      t.date,
      [
        type,
        _date(t.date),
        t.title,
        t.category.name,
        '',
        '',
        '${t.amount}',
        'registrado',
      ],
    ));
  }
  rows.sort((a, b) => a.$1.compareTo(b.$1));
  final lines = [
    accountantCsvHeader,
    for (final r in rows) r.$2.map(_cell).join(','),
  ];
  return AccountantExport(csv: lines.join('\n'), rows: rows.length);
}
