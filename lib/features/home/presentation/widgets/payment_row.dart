import 'package:flutter/material.dart';

import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/format/dates.dart';
import 'package:inti/core/money/money.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/home/domain/money_summary.dart';

/// Días para que un pago se marque como urgente.
const int urgentDays = 3;

/// Un pago próximo: qué es, cuándo vence y cuánto. Usa la misma estructura
/// que las filas de movimientos ([AmountRowLayout]).
class PaymentRow extends StatelessWidget {
  const PaymentRow({
    required this.payment,
    required this.now,
    super.key,
    this.onTap,
  });

  final UpcomingPayment payment;
  final DateTime now;

  /// Solo los pagos de tarjeta tienen a dónde ir (la tarjeta); los pagos
  /// fijos se gestionan en Planes (Hito 6).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = payment;
    final days = daysBetween(now, p.due);
    final overdue = days < 0;
    final urgent = !overdue && days <= urgentDays;
    final due = Dates.dueLabel(p.due, now);
    final icon = switch (p.kind) {
      PaymentKind.card => Icons.credit_card_rounded,
      PaymentKind.bill => Icons.receipt_rounded,
      PaymentKind.tax => Icons.account_balance_rounded,
    };
    final spoken = [
      p.title,
      due,
      Cop.spoken(p.amount),
      if (p.minimum != null) 'Pago mínimo ${Cop.spoken(p.minimum!)}',
    ].join('. ');
    final large = isLargeText(context);

    return Semantics(
      label: spoken,
      button: onTap != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.controlAll,
        child: AmountRowLayout(
          leading: IconTile(
            icon: icon,
            background: overdue
                ? c.dangerContainer
                : urgent
                ? c.warningContainer
                : null,
            foreground: overdue
                ? c.onDangerContainer
                : urgent
                ? c.warning
                : null,
          ),
          title: p.title,
          details: [
            if (overdue || urgent)
              // Mismo lenguaje de estado que las filas de movimientos.
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: StatusPill(
                  due,
                  tone: overdue ? PillTone.danger : PillTone.warning,
                ),
              )
            else
              Text(
                due,
                style: AppTypography.caption.copyWith(color: c.inkSubtle),
              ),
          ],
          trailing: Column(
            crossAxisAlignment: large
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              MoneyText(
                p.amount,
                animate: false,
                style: AppTypography.body.copyWith(
                  color: c.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (p.minimum != null)
                Text(
                  'Mínimo ${Cop.format(p.minimum!)}',
                  style: AppTypography.caption.copyWith(color: c.inkSubtle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
