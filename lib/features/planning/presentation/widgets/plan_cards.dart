import 'package:flutter/material.dart';

import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/planning/domain/plans.dart';

ProgressTone toneOf(BudgetStatus s) => switch (s) {
  BudgetStatus.ok => ProgressTone.ok,
  BudgetStatus.warning => ProgressTone.warning,
  BudgetStatus.over => ProgressTone.danger,
};

/// Frase de estado de un presupuesto ("Quedan $14.600").
String budgetLine(BudgetProgress p) => switch (p.status) {
  BudgetStatus.over => 'Te pasaste ${Cop.format(-p.left)}',
  BudgetStatus.warning => 'Cerca del límite: quedan ${Cop.format(p.left)}',
  BudgetStatus.ok => 'Quedan ${Cop.format(p.left)}',
};

/// Presupuesto en lista: categoría, gastado de cuánto y barra.
class BudgetCard extends StatelessWidget {
  const BudgetCard({required this.progress, required this.onTap, super.key});

  final BudgetProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final p = progress;
    final cat = p.budget.category;
    final large = isLargeText(context);
    final amounts = Text(
      '${Cop.format(p.spent)} de ${Cop.format(p.budget.limit)}',
      style: AppTypography.label.copyWith(
        color: c.inkMuted,
        fontFeatures: AppTypography.tabular,
      ),
    );
    final lineColor = switch (p.status) {
      BudgetStatus.ok => c.inkSubtle,
      BudgetStatus.warning => c.warning,
      BudgetStatus.over => c.onDangerContainer,
    };
    return QCard(
      onTap: onTap,
      semanticLabel:
          '${cat.name}. Gastaste ${Cop.spoken(p.spent)} de '
          '${Cop.spoken(p.budget.limit)}. ${budgetLine(p)}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconTile(icon: cat.icon),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cat.name,
                        style: AppTypography.body.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      // Con texto grande el monto baja bajo el nombre.
                      if (large) amounts,
                    ],
                  ),
                ),
                if (!large) ...[const SizedBox(width: AppSpace.sm), amounts],
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            QProgressBar(
              value: p.ratio,
              tone: toneOf(p.status),
              semanticLabel: cat.name,
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              budgetLine(p),
              style: p.status == BudgetStatus.ok
                  ? AppTypography.caption.copyWith(color: lineColor)
                  : AppTypography.label.copyWith(color: lineColor),
            ),
          ],
        ),
      ),
    );
  }
}

/// Texto de avance de una meta ("Faltan $2.280.000 · unos 6 meses").
String goalLine(Goal g, DateTime now) {
  if (g.done) return 'Meta cumplida';
  final months = monthsToGoal(g, now);
  final missing = 'Faltan ${Cop.format(g.missing)}';
  if (months == null) return '$missing · aún sin aportes recientes';
  return months == 1
      ? '$missing · llegas en 1 mes a este ritmo'
      : '$missing · llegas en $months meses a este ritmo';
}

/// Meta en lista: anillo de avance, nombre, ahorrado y cuánto falta.
class GoalCard extends StatelessWidget {
  const GoalCard({
    required this.goal,
    required this.now,
    required this.onTap,
    super.key,
  });

  final Goal goal;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = goal;
    final percent = Cop.percent(g.ratio * 100);
    return QCard(
      onTap: onTap,
      semanticLabel:
          '${g.name}. Llevas ${Cop.spoken(g.saved)} de '
          '${Cop.spoken(g.target)}, $percent. ${goalLine(g, now)}',
      child: ExcludeSemantics(
        child: Row(
          children: [
            QProgressRing(
              value: g.ratio,
              semanticLabel: g.name,
              child: Text(
                percent,
                style: AppTypography.label.copyWith(color: c.ink),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g.name,
                    style: AppTypography.body.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${Cop.format(g.saved)} de ${Cop.format(g.target)}',
                    style: AppTypography.label.copyWith(
                      color: c.inkMuted,
                      fontFeatures: AppTypography.tabular,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xxs),
                  Text(
                    goalLine(g, now),
                    style: AppTypography.caption.copyWith(color: c.inkSubtle),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
