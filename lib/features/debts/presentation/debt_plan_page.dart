import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inti/core/format/dates.dart';
import 'package:inti/core/money/money.dart';
import 'package:inti/core/scope/scope_provider.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart';
import 'package:inti/features/accounts/domain/account.dart';
import 'package:inti/features/debts/domain/debt_plan.dart';

/// Tasa que se supone cuando la tarjeta no la trae.
const double _assumedCardRate = 0.26;

/// Dinero extra con que arranca el plan sobre los mínimos.
const int _defaultExtra = 200000;

/// Pasa tus tarjetas a deudas simulables.
List<DebtInput> debtsOf(List<Account> accounts) => [
  for (final a in accounts)
    if (a.isCard && a.balance > 0)
      DebtInput(
        id: a.id,
        name: a.shortName,
        balance: a.balance,
        annualRate: a.interestRate ?? _assumedCardRate,
        minimum: a.minimumPayment ?? (a.balance * 0.05).round(),
      ),
];

/// Plan para pagar tus tarjetas: cuánto tardas y cuánto pagas de intereses.
class DebtPlanPage extends ConsumerStatefulWidget {
  const DebtPlanPage({super.key});

  @override
  ConsumerState<DebtPlanPage> createState() => _DebtPlanPageState();
}

class _DebtPlanPageState extends ConsumerState<DebtPlanPage> {
  final _budget = TextEditingController();
  DebtStrategy _strategy = DebtStrategy.avalanche;
  bool _seeded = false;

  @override
  void dispose() {
    _budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final scope = ref.watch(scopeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Plan de deudas')),
      body: switch (accounts) {
        AsyncData(:final value) => _content(
          context,
          debtsOf(value.where((a) => a.ownership.visibleIn(scope)).toList()),
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar tus tarjetas',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(accountsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando tus tarjetas'),
      },
    );
  }

  Widget _content(BuildContext context, List<DebtInput> debts) {
    if (debts.isEmpty) {
      return const MessageBody(
        child: EmptyState(
          icon: Icons.verified_rounded,
          title: 'No debes nada en tarjetas',
          message:
              'Cuando tengas saldo en una tarjeta, aquí te armamos un plan '
              'para pagarla más rápido y con menos intereses.',
        ),
      );
    }
    final minimums = totalMinimums(debts);
    if (!_seeded) {
      _seeded = true;
      _budget.text = '${minimums + _defaultExtra}';
    }
    final typed = AmountInput.value(_budget.text);
    final belowMinimums = typed < minimums;
    final budget = belowMinimums ? minimums : typed;
    final plan = simulateDebtPlan(
      debts: debts,
      monthlyPayment: budget,
      strategy: _strategy,
    );
    final onlyMinimum = simulateDebtPlan(
      debts: debts,
      monthlyPayment: minimums,
      strategy: _strategy,
      redirectFreed: false,
    );
    final total = debts.fold<int>(0, (s, d) => s + d.balance);
    final saved = onlyMinimum.totalInterest - plan.totalInterest;
    final digitsOnly = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(AmountInput.maxDigits),
    ];

    String when(DebtResult r) =>
        r.completed ? Dates.span(r.months) : 'No las terminas de pagar';

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xxl,
      ),
      children: [
        HeroBalance(
          label: 'Debes en tarjetas',
          value: total,
          caption: plan.completed
              ? 'Con tu plan, sin deudas en ${Dates.span(plan.months)}'
              : 'Con este pago no alcanzas a terminarlas',
        ),
        const SizedBox(height: AppSpace.lg),
        TextField(
          controller: _budget,
          keyboardType: TextInputType.number,
          inputFormatters: digitsOnly,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: '¿Cuánto puedes pagar al mes en total?',
            prefixText: r'$ ',
            helperText: belowMinimums ? null : Cop.format(typed),
            errorText: belowMinimums
                ? 'Para no caer en mora necesitas al menos '
                      '${Cop.format(minimums)}.'
                : null,
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        const SectionHeader('¿Por cuál empiezas?'),
        const SizedBox(height: AppSpace.xs),
        SegmentedButton<DebtStrategy>(
          showSelectedIcon: false,
          direction: isLargeText(context) ? Axis.vertical : Axis.horizontal,
          segments: [
            for (final s in DebtStrategy.values)
              ButtonSegment(value: s, label: Text(s.label)),
          ],
          selected: {_strategy},
          onSelectionChanged: (s) => setState(() => _strategy = s.first),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(_strategy.description, style: context.text.bodySmall),
        const SizedBox(height: AppSpace.xl),
        const SectionHeader('Con tu plan o sin hacer nada más'),
        const SizedBox(height: AppSpace.xs),
        QCard(
          child: Column(
            children: [
              DetailLine('Solo el mínimo: tardas', when(onlyMinimum)),
              DetailLine(
                'Solo el mínimo: intereses',
                Cop.format(onlyMinimum.totalInterest),
              ),
              const Divider(),
              DetailLine('Con tu plan: tardas', when(plan)),
              DetailLine(
                'Con tu plan: intereses',
                Cop.format(plan.totalInterest),
              ),
              if (plan.completed && saved > 0) ...[
                const Divider(),
                DetailLine(
                  'Te ahorras en intereses',
                  Cop.format(saved),
                  emphasis: true,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        const SectionHeader('En qué orden se pagan'),
        const SizedBox(height: AppSpace.xs),
        QCard(
          child: Column(
            children: [
              for (final (i, p) in plan.payoffs.indexed)
                DetailLine('${i + 1}. ${p.name}', 'En ${Dates.span(p.month)}'),
              if (plan.payoffs.isEmpty)
                const DetailLine('Aún ninguna', 'Sube el pago mensual'),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        const QBanner(
          tone: BannerTone.info,
          title: 'Es una estimación',
          message:
              'Usa la tasa y el pago mínimo de cada tarjeta, y supone que no '
              'haces compras nuevas con ellas.',
        ),
      ],
    );
  }
}
