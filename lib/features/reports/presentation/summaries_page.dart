import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';
import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/money/money.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/core/scope/scope_provider.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/reports/domain/summaries.dart';
import 'package:inti/features/transactions/data/transactions_repository.dart';
import 'package:inti/features/transactions/domain/transaction.dart';

enum _Period {
  week('Últimos 7 días'),
  month('Este mes'),
  lastMonth('Mes pasado');

  _Period(this.label);

  final String label;
}

/// Resumen semanal y cierre mensual: lo que entró, lo que salió y en qué se
/// fue, listo para copiar y mandar.
class SummariesPage extends ConsumerStatefulWidget {
  const SummariesPage({super.key});

  @override
  ConsumerState<SummariesPage> createState() => _SummariesPageState();
}

class _SummariesPageState extends ConsumerState<SummariesPage> {
  _Period _period = _Period.week;

  PeriodSummary _summary(List<Transaction> all, DateTime now, Scope scope) =>
      switch (_period) {
        _Period.week => lastSevenDays(all, now, scope),
        _Period.month => monthSummary(all, now, now, scope),
        _Period.lastMonth => monthSummary(
          all,
          DateTime(now.year, now.month - 1),
          now,
          scope,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final txs = ref.watch(transactionsProvider);
    final scope = ref.watch(scopeProvider);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('Resúmenes')),
      body: switch (txs) {
        AsyncData(:final value) => _content(
          context,
          _summary(value, now, scope),
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos armar tu resumen',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(transactionsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Armando tu resumen'),
      },
    );
  }

  Widget _content(BuildContext context, PeriodSummary s) {
    final c = context.colors;
    final large = isLargeText(context);
    final maxCat = s.byCategory.isEmpty ? 1 : s.byCategory.first.$2;
    final change = s.expenseChange;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xxl,
      ),
      children: [
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: [
            for (final p in _Period.values)
              ChoiceChip(
                label: Text(p.label),
                selected: _period == p,
                onSelected: (_) => setState(() => _period = p),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        HeroBalance(
          label: s.saved >= 0 ? 'Te sobró' : 'Gastaste de más',
          value: s.saved.abs(),
          caption: '${s.title} · ${s.range}',
        ),
        const SizedBox(height: AppSpace.md),
        QCard(
          child: Column(
            children: [
              DetailLine('Ingresos', Cop.format(s.income)),
              DetailLine('Gastos', Cop.format(s.expense)),
              DetailLine(
                'Gastos del periodo anterior',
                Cop.format(s.previousExpense),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          s.previousExpense == 0
              ? 'Aún no hay un periodo anterior con qué comparar.'
              : change == 0
              ? 'Gastaste lo mismo que el periodo anterior.'
              : change > 0
              ? 'Gastaste ${Cop.format(change)} más que el periodo anterior.'
              : 'Gastaste ${Cop.format(-change)} menos que el periodo '
                    'anterior.',
          style: context.text.bodySmall,
        ),
        const SizedBox(height: AppSpace.xl),
        const SectionHeader('En qué se fue'),
        const SizedBox(height: AppSpace.xs),
        if (s.byCategory.isEmpty)
          const SectionNote('No hay gastos en este periodo.')
        else
          for (final (cat, amount) in s.byCategory.take(6))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
              child: Semantics(
                label:
                    '${cat.name}: ${Cop.spoken(amount)}, '
                    '${Cop.percent(amount * 100 / s.expense)} de tus gastos',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(cat.icon, size: AppSize.iconSm, color: c.inkMuted),
                        const SizedBox(width: AppSpace.xs),
                        Expanded(
                          child: Text(cat.name, style: context.text.bodyMedium),
                        ),
                        if (!large)
                          MoneyText(
                            amount,
                            animate: false,
                            style: AppTypography.body.copyWith(
                              color: c.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    if (large)
                      MoneyText(
                        amount,
                        animate: false,
                        style: AppTypography.body.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: AppSpace.xxs),
                    QProgressBar(
                      value: amount / maxCat,
                      height: AppSpace.xs - AppSpace.xxs,
                      semanticLabel: cat.name,
                    ),
                  ],
                ),
              ),
            ),
        if (s.biggest.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xl),
          const SectionHeader('Tus gastos más grandes'),
          const SizedBox(height: AppSpace.xs),
          QCard(
            child: Column(
              children: [
                for (final t in s.biggest)
                  DetailLine(t.title, Cop.format(t.amount)),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpace.xl),
        QButton(
          label: 'Copiar resumen',
          icon: Icons.copy_rounded,
          onPressed: () {
            // Copiar no debe frenar nada: se hace sin esperar.
            unawaited(Clipboard.setData(ClipboardData(text: summaryText(s))));
            showQToast(context, 'Copiamos el resumen para que lo envíes');
          },
        ),
        const SizedBox(height: AppSpace.xs),
        QButton.text(
          label: 'Ver reportes del mes',
          onPressed: () => context.go(Routes.planning),
        ),
      ],
    );
  }
}
