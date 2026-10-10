import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/material.dart' show IconData, Icons;

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/features/accounts/domain/account.dart';
import 'package:qullqi/features/business/domain/business.dart';
import 'package:qullqi/features/commitments/domain/commitment.dart';
import 'package:qullqi/features/home/domain/money_summary.dart';
import 'package:qullqi/features/planning/domain/plans.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';

/// Tipos de aviso que la persona puede encender o apagar.
enum NoticeKind {
  payments(
    'Pagos próximos',
    'Te avisamos 3 días antes de cada pago y tarjeta.',
  ),
  budgets('Presupuestos', 'Cuando llegas al 80 % de un tope o te pasas.'),
  invoices('Cobros del negocio', 'Cuando una factura se vence sin pagar.'),
  bigMovements(
    'Movimientos grandes',
    r'Cada vez que entra o sale más de $1.000.000.',
  ),
  transfers(
    'Traslados por revisar',
    'Cuando detectamos plata que pasa entre tus cuentas.',
  );

  NoticeKind(this.title, this.description);

  final String title;
  final String description;
}

/// Días antes del vencimiento en que avisamos un pago.
const int paymentNoticeDays = 3;

/// Desde este valor un movimiento es "grande".
const int bigMovementAmount = 1000000;

/// Cuántos días atrás miramos los movimientos grandes.
const int bigMovementDays = 7;

enum NoticeTone { info, warning, danger }

/// Un aviso del centro de notificaciones. Se calcula a partir de los datos:
/// cuando la causa desaparece (pagaste, reconectaste), el aviso también.
@immutable
class Notice {
  const Notice({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.icon,
    required this.tone,
    required this.route,
  });

  /// Estable mientras la causa sea la misma, para recordar si ya se vio.
  final String id;

  /// `null`: aviso de seguridad o de conexión, que no se puede apagar.
  final NoticeKind? kind;
  final String title;
  final String body;
  final IconData icon;
  final NoticeTone tone;

  /// A dónde lleva tocarlo.
  final String route;
}

String _ymd(DateTime d) => '${d.year}-${d.month}-${d.day}';

/// Arma los avisos vigentes, del más urgente al menos urgente.
List<Notice> buildNotices({
  required DateTime now,
  required List<Account> accounts,
  required List<Commitment> commitments,
  required List<Transaction> transactions,
  required List<Budget> budgets,
  required List<Invoice> invoices,
  required bool hasBusiness,
  required Set<NoticeKind> enabled,
}) {
  bool visible(Ownership o) => hasBusiness || o == Ownership.personal;
  final notices = <Notice>[
    // Conexión: sin permiso no vemos movimientos nuevos. Siempre llega.
    for (final a in accounts)
      if (a.status == ConnectionStatus.needsReconnect && visible(a.ownership))
        Notice(
          id: 'reconnect:${a.id}',
          kind: null,
          title: 'Reconecta ${a.shortName}',
          body:
              'Venció el permiso con el banco y no vemos sus movimientos '
              'nuevos.',
          icon: Icons.link_off_rounded,
          tone: NoticeTone.danger,
          route: Routes.reconnect(a.id),
        ),
    if (enabled.contains(NoticeKind.invoices) && hasBusiness)
      for (final i in invoices)
        if (i.statusAt(now) == InvoiceStatus.overdue)
          Notice(
            id: 'invoice:${i.id}',
            kind: NoticeKind.invoices,
            title: 'Cobro vencido: ${i.client}',
            body:
                '${i.number} por ${Cop.format(i.total)}. '
                '${Dates.dueLabel(i.due, now)}.',
            icon: Icons.receipt_long_outlined,
            tone: NoticeTone.danger,
            route: Routes.invoice(i.id),
          ),
    if (enabled.contains(NoticeKind.payments))
      for (final p in upcomingPayments(
        accounts: accounts,
        commitments: commitments,
        scope: Scope.all,
      ))
        if (visible(p.ownership) &&
            daysBetween(now, p.due) <= paymentNoticeDays)
          Notice(
            id: 'payment:${p.id}:${_ymd(p.due)}',
            kind: NoticeKind.payments,
            title: switch (p.kind) {
              PaymentKind.card => 'Paga tu ${p.title}',
              PaymentKind.bill || PaymentKind.tax => p.title,
            },
            body: '${Dates.dueLabel(p.due, now)}: ${Cop.format(p.amount)}.',
            icon: Icons.event_rounded,
            tone: daysBetween(now, p.due) < 0
                ? NoticeTone.danger
                : NoticeTone.warning,
            route: switch (p.kind) {
              PaymentKind.card => Routes.account(p.accountId!),
              PaymentKind.tax => Routes.iva,
              PaymentKind.bill => Routes.home,
            },
          ),
    if (enabled.contains(NoticeKind.budgets))
      for (final b in budgets)
        if (visible(b.ownership))
          if (progressOf(b, transactions, now) case final p
              when p.status != BudgetStatus.ok)
            Notice(
              id: 'budget:${b.id}:${p.status.name}:${now.year}-${now.month}',
              kind: NoticeKind.budgets,
              title: p.status == BudgetStatus.over
                  ? 'Te pasaste en ${b.category.name}'
                  : 'Vas en el ${Cop.percent(p.ratio * 100)} de '
                        '${b.category.name}',
              body: p.status == BudgetStatus.over
                  ? 'Vas ${Cop.format(-p.left)} por encima del tope del mes.'
                  : 'Te quedan ${Cop.format(p.left)} para el resto del mes.',
              icon: b.category.icon,
              tone: p.status == BudgetStatus.over
                  ? NoticeTone.danger
                  : NoticeTone.warning,
              route: Routes.budget(b.id),
            ),
    if (enabled.contains(NoticeKind.transfers))
      if (transactions
              .where((t) => t.needsReview && visible(t.ownership))
              .toList()
          case final review when review.isNotEmpty)
        Notice(
          id: 'transfers:${review.map((t) => t.id).join(',')}',
          kind: NoticeKind.transfers,
          title: review.length == 1
              ? 'Un movimiento parece un traslado'
              : '${review.length} movimientos parecen traslados',
          body: 'Revísalos para que no cuenten como gasto ni como ingreso.',
          icon: Icons.compare_arrows_rounded,
          tone: NoticeTone.info,
          route: Routes.reviewTransfers,
        ),
    if (enabled.contains(NoticeKind.bigMovements))
      for (final t in transactions)
        if (visible(t.ownership) &&
            t.kind != TransactionKind.transfer &&
            t.amount >= bigMovementAmount &&
            daysBetween(t.date, now) <= bigMovementDays)
          Notice(
            id: 'big:${t.id}',
            kind: NoticeKind.bigMovements,
            title: t.kind == TransactionKind.income
                ? 'Entraron ${Cop.format(t.amount)}'
                : 'Salieron ${Cop.format(t.amount)}',
            body: '${t.title}. ${Dates.relativeDay(t.date, now)}.',
            icon: t.kind == TransactionKind.income
                ? Icons.south_west_rounded
                : Icons.north_east_rounded,
            tone: NoticeTone.info,
            route: Routes.transaction(t.id),
          ),
  ];
  // Lo urgente primero; dentro de cada tono se respeta el orden de arriba.
  final order = {for (final (i, n) in notices.indexed) n.id: i};
  return notices..sort((a, b) {
    final byTone = b.tone.index.compareTo(a.tone.index);
    return byTone != 0 ? byTone : order[a.id]!.compareTo(order[b.id]!);
  });
}
