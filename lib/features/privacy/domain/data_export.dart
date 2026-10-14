import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

import 'package:inti/core/session/session.dart';
import 'package:inti/features/accounts/domain/account.dart';
import 'package:inti/features/business/domain/accountant.dart' show csvCell;
import 'package:inti/features/business/domain/bill.dart';
import 'package:inti/features/business/domain/business.dart';
import 'package:inti/features/investments/domain/investment.dart';
import 'package:inti/features/planning/domain/plans.dart';
import 'package:inti/features/rules/domain/category_rule.dart';
import 'package:inti/features/transactions/domain/transaction.dart';

/// Copia de los datos de la persona, tal como los guarda Inti.
@immutable
class DataExport {
  const DataExport({required this.json, required this.counts});

  /// Los datos completos, en JSON legible.
  final String json;

  /// Cuántos registros hay de cada cosa (solo las que tienen alguno).
  final Map<String, int> counts;

  int get total => counts.values.fold(0, (s, n) => s + n);
}

String? _date(DateTime? d) => d?.toIso8601String().split('T').first;

/// Arma la copia de datos. No incluye PIN, contraseña ni permisos con
/// bancos: esos nunca salen del teléfono ni del servidor.
DataExport buildDataExport({
  required AppUser user,
  required DateTime now,
  required List<Account> accounts,
  required List<Transaction> transactions,
  required List<Budget> budgets,
  required List<Goal> goals,
  required List<CategoryRule> rules,
  required List<Investment> investments,
  required List<Invoice> invoices,
  required List<Bill> bills,
}) {
  final sections = <String, List<Map<String, Object?>>>{
    'cuentas': [
      for (final a in accounts)
        {
          'id': a.id,
          'entidad': a.institution,
          'tipo': a.kind.label,
          'ultimos4': a.last4,
          'ambito': a.ownership.label,
          'saldo': a.balance,
          'moneda': a.currency.code,
        },
    ],
    'movimientos': [
      for (final t in transactions)
        {
          'id': t.id,
          'fecha': _date(t.date),
          'descripcion': t.title,
          'valor': t.amount,
          'tipo': t.kind.label,
          'cuenta': t.accountId,
          'categoria': t.category.name,
          'ambito': t.ownership.label,
          'nota': t.note,
        },
    ],
    'presupuestos': [
      for (final b in budgets)
        {
          'categoria': b.category.name,
          'tope': b.limit,
          'ambito': b.ownership.label,
        },
    ],
    'metas': [
      for (final g in goals)
        {
          'nombre': g.name,
          'meta': g.target,
          'ahorrado': g.saved,
          'fecha': _date(g.deadline),
        },
    ],
    'reglas': [
      for (final r in rules)
        {'palabra': r.keyword, 'categoria': r.category.name},
    ],
    'inversiones': [
      for (final i in investments)
        {
          'nombre': i.name,
          'tipo': i.kind.label,
          'entidad': i.institution,
          'puesto': i.invested,
          'valor': i.value,
        },
    ],
    'facturas': [
      for (final i in invoices)
        {
          'numero': i.number,
          'cliente': i.client,
          'valor': i.base,
          'iva': i.iva,
          'total': i.total,
          'emitida': _date(i.issued),
          'vence': _date(i.due),
          'pagada': _date(i.paidOn),
        },
    ],
    'cuentas_por_pagar': [
      for (final b in bills)
        {
          'proveedor': b.supplier,
          'concepto': b.concept,
          'valor': b.amount,
          'vence': _date(b.due),
          'pagada': _date(b.paidOn),
        },
    ],
  };
  final document = <String, Object?>{
    'version': 1,
    'generado': _date(now),
    'persona': {
      'nombre': user.fullName,
      'correo': user.email,
      'celular': user.phone,
      'tiene_negocio': user.hasBusiness,
    },
    ...sections,
  };
  return DataExport(
    json: const JsonEncoder.withIndent('  ').convert(document),
    counts: {
      for (final e in sections.entries)
        if (e.value.isNotEmpty) e.key: e.value.length,
    },
  );
}

/// Cabecera del CSV de movimientos.
const transactionsCsvHeader =
    'fecha,descripcion,cuenta,categoria,tipo,ambito,valor,nota';

/// Los movimientos en CSV, del más reciente al más antiguo.
String transactionsCsv(
  List<Transaction> transactions,
  String Function(String accountId) accountName,
) {
  final sorted = [...transactions]..sort((a, b) => b.date.compareTo(a.date));
  return [
    transactionsCsvHeader,
    for (final t in sorted)
      [
        _date(t.date) ?? '',
        t.title,
        accountName(t.accountId),
        t.category.name,
        t.kind.label,
        t.ownership.label,
        '${t.amount}',
        t.note ?? '',
      ].map(csvCell).join(','),
  ].join('\n');
}
