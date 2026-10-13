import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/app/shell/tab_page.dart';
import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope_provider.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/planning/data/plans_repository.dart';
import 'package:qullqi/features/planning/presentation/planning_controller.dart';
import 'package:qullqi/features/planning/presentation/widgets/plan_cards.dart';
import 'package:qullqi/features/recurring/data/recurring_provider.dart';
import 'package:qullqi/features/recurring/domain/recurring.dart';
import 'package:qullqi/features/sharing/data/sharing_repositories.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:qullqi/features/transactions/presentation/transaction_tile.dart';

/// Planes: presupuestos del mes, metas de ahorro y reportes.
class PlanningPage extends ConsumerWidget {
  const PlanningPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(planningViewProvider);
    final section = ref.watch(planningSectionProvider);

    return TabPage(
      title: 'Planes',
      slivers: [
        GutterSliver(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.md),
            child: SegmentedButton<PlanningSection>(
              showSelectedIcon: false,
              // Con texto grande las secciones no caben en una fila.
              direction: isLargeText(context) ? Axis.vertical : Axis.horizontal,
              segments: [
                for (final s in PlanningSection.values)
                  ButtonSegment(value: s, label: Text(s.label)),
              ],
              selected: {section},
              onSelectionChanged: (s) =>
                  ref.read(planningSectionProvider.notifier).set(s.first),
            ),
          ),
        ),
        ...switch (view) {
          AsyncData(:final value) => switch (section) {
            PlanningSection.budgets => [
              ..._budgets(context, value),
              ..._recurringEntry(context, ref),
            ],
            PlanningSection.goals => [
              ..._goals(context, value),
              ..._sharedEntry(context, ref),
            ],
            PlanningSection.reports => [
              ..._reports(context, ref, value),
              GutterSliver(
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xl),
                  child: OptionRow(
                    icon: Icons.summarize_outlined,
                    title: 'Resumen semanal y cierre mensual',
                    subtitle: 'Para copiar y mandar a quien quieras',
                    onTap: () => context.push(Routes.summaries),
                  ),
                ),
              ),
            ],
          },
          AsyncError() => [
            GutterSliver(
              child: EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'No pudimos cargar tus planes',
                message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
                actionLabel: 'Reintentar',
                onAction: () => ref
                  ..invalidate(budgetsProvider)
                  ..invalidate(goalsProvider)
                  ..invalidate(transactionsProvider),
              ),
            ),
          ],
          _ => [
            GutterSliver(
              child: Semantics(
                label: 'Cargando tus planes',
                liveRegion: true,
                child: const Column(
                  children: [
                    SkeletonBlock(height: _heroHeight, radius: AppRadius.card),
                    SizedBox(height: AppSpace.lg),
                    SkeletonBlock(height: _cardHeight, radius: AppRadius.card),
                    SizedBox(height: AppSpace.xs),
                    SkeletonBlock(height: _cardHeight, radius: AppRadius.card),
                  ],
                ),
              ),
            ),
          ],
        },
      ],
    );
  }

  /// Acceso a las metas compartidas, debajo de las metas.
  List<Widget> _sharedEntry(BuildContext context, WidgetRef ref) {
    final shared = ref.watch(sharedGoalsProvider).value ?? const [];
    return [
      const SliverToBoxAdapter(child: SizedBox(height: AppSpace.md)),
      GutterSliver(
        child: OptionRow(
          icon: Icons.volunteer_activism_outlined,
          title: 'Metas compartidas',
          subtitle: shared.isEmpty
              ? 'Ahorra con tu pareja o tus amigos'
              : '${shared.length} '
                    '${shared.length == 1 ? 'meta' : 'metas'} compartidas',
          onTap: () => context.push(Routes.sharedGoals),
        ),
      ),
    ];
  }

  /// Acceso a los cobros que se repiten, debajo de los presupuestos.
  List<Widget> _recurringEntry(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(scopeProvider);
    final charges = (ref.watch(recurringProvider).value ?? const [])
        .where((c) => c.ownership.visibleIn(scope))
        .toList();
    return [
      const SliverToBoxAdapter(child: SizedBox(height: AppSpace.md)),
      GutterSliver(
        child: OptionRow(
          icon: Icons.autorenew_rounded,
          title: 'Pagos recurrentes',
          subtitle: charges.isEmpty
              ? 'Suscripciones y cobros que se repiten'
              : '${charges.length} '
                    '${charges.length == 1 ? 'cobro' : 'cobros'} · '
                    '${Cop.format(monthlyTotal(charges))} al mes',
          onTap: () => context.push(Routes.recurring),
        ),
      ),
    ];
  }

  List<Widget> _budgets(BuildContext context, PlanningView v) {
    if (v.budgets.isEmpty) {
      return [
        GutterSliver(
          child: EmptyState(
            icon: Icons.pie_chart_outline_rounded,
            title: 'Ponle un tope a tus gastos',
            message:
                'Elige una categoría y cuánto quieres gastar al mes. Te '
                'avisamos antes de pasarte.',
            actionLabel: 'Crear presupuesto',
            onAction: () => context.push(Routes.budgetEditor),
          ),
        ),
      ];
    }
    final left = v.budgeted - v.spent;
    final days = v.budgets.first.daysLeft;
    return [
      GutterSliver(
        child: HeroBalance(
          label: 'Te queda en tus presupuestos',
          value: left,
          caption:
              'Gastaste ${Cop.format(v.spent)} de ${Cop.format(v.budgeted)} '
              'en ${Dates.month(v.now)} · quedan $days '
              '${days == 1 ? 'día' : 'días'}',
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
      GutterSliver(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              'Este mes',
              action: 'Crear',
              actionSemantics: 'Crear presupuesto',
              onAction: () => context.push(Routes.budgetEditor),
            ),
            const SizedBox(height: AppSpace.xs),
            for (final p in v.budgets) ...[
              BudgetCard(
                progress: p,
                onTap: () => context.push(Routes.budget(p.budget.id)),
              ),
              const SizedBox(height: AppSpace.xs),
            ],
          ],
        ),
      ),
    ];
  }

  List<Widget> _goals(BuildContext context, PlanningView v) {
    if (v.goals.isEmpty) {
      return [
        GutterSliver(
          child: EmptyState(
            icon: Icons.savings_outlined,
            title: 'Ahorra para algo',
            message:
                'Un fondo de emergencia, un viaje o un computador. Te decimos '
                'cuánto separar cada mes.',
            actionLabel: 'Crear meta',
            onAction: () => context.push(Routes.newGoal),
          ),
        ),
      ];
    }
    final saved = v.goals.fold<int>(0, (s, g) => s + g.saved);
    return [
      GutterSliver(
        child: HeroBalance(
          label: 'Llevas ahorrado',
          value: saved,
          caption: v.goals.length == 1
              ? 'En 1 meta'
              : 'Entre tus ${v.goals.length} metas',
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
      GutterSliver(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              'Tus metas',
              action: 'Crear',
              actionSemantics: 'Crear meta',
              onAction: () => context.push(Routes.newGoal),
            ),
            const SizedBox(height: AppSpace.xs),
            for (final g in v.goals) ...[
              GoalCard(
                goal: g,
                now: v.now,
                onTap: () => context.push(Routes.goal(g.id)),
              ),
              const SizedBox(height: AppSpace.xs),
            ],
          ],
        ),
      ),
    ];
  }

  List<Widget> _reports(BuildContext context, WidgetRef ref, PlanningView v) {
    final c = context.colors;
    final r = v.report;
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final change = r.expenseChange;
    final maxCat = r.byCategory.isEmpty ? 1 : r.byCategory.first.$2;
    final large = isLargeText(context);
    Widget amountText(int amount) => MoneyText(
      amount,
      animate: false,
      style: AppTypography.body.copyWith(
        color: c.ink,
        fontWeight: FontWeight.w600,
      ),
    );
    return [
      GutterSliver(
        child: HeroBalance(
          label: r.saved >= 0
              ? 'Te sobró en ${Dates.month(v.now)}'
              : 'Gastaste más de lo que entró',
          value: r.saved,
          caption: change == 0
              ? 'Gastaste lo mismo que el mes pasado'
              : change > 0
              ? 'Gastaste ${Cop.format(change)} más que el mes pasado'
              : 'Gastaste ${Cop.format(-change)} menos que el mes pasado',
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpace.lg)),
      GutterSliver(
        child: QCard(
          child: Column(
            children: [
              DetailLine('Ingresos', Cop.format(r.income)),
              DetailLine('Gastos', Cop.format(r.expense)),
              DetailLine('Gastos del mes pasado', Cop.format(r.prevExpense)),
            ],
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
      GutterSliver(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader('En qué se fue la plata'),
            const SizedBox(height: AppSpace.xs),
            if (r.byCategory.isEmpty)
              const SectionNote('Aún no hay gastos este mes.')
            else
              for (final (cat, amount) in r.byCategory)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                  child: Semantics(
                    label:
                        '${cat.name}: ${Cop.spoken(amount)}, '
                        '${Cop.percent(amount * 100 / r.expense)} '
                        'de tus gastos',
                    excludeSemantics: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(
                              cat.icon,
                              size: AppSize.iconSm,
                              color: c.inkMuted,
                            ),
                            const SizedBox(width: AppSpace.xs),
                            Expanded(
                              child: Text(
                                cat.name,
                                style: context.text.bodyMedium,
                              ),
                            ),
                            if (!large) amountText(amount),
                          ],
                        ),
                        // Con texto grande el monto baja de línea.
                        if (large) amountText(amount),
                        const SizedBox(height: AppSpace.xxs),
                        // Barra relativa a la categoría más grande.
                        QProgressBar(
                          value: amount / maxCat,
                          height: AppSpace.xs - AppSpace.xxs,
                          semanticLabel: cat.name,
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
      if (r.topExpenses.isNotEmpty) ...[
        const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
        GutterSliver(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader('Tus gastos más grandes'),
              for (final t in r.topExpenses)
                TransactionTile(
                  transaction: t,
                  accounts: accounts,
                  now: v.now,
                  onTap: () => context.push(Routes.transaction(t.id)),
                ),
            ],
          ),
        ),
      ],
    ];
  }
}

// Medidas aproximadas de los bloques reales para que la carga no salte.
const double _heroHeight = 140;
const double _cardHeight = 96;
