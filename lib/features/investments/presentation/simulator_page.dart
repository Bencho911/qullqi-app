import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/investments/domain/investment.dart';
import 'package:qullqi/features/planning/data/plans_repository.dart';
import 'package:qullqi/features/planning/domain/plans.dart';

/// Plazos que se ofrecen (en años).
const _yearOptions = <int>[1, 3, 5, 10];

/// Tasas efectivas anuales que se ofrecen (fracción). La persona elige: no
/// es la rentabilidad de ninguna inversión en particular.
const _rateOptions = <double>[0.04, 0.08, 0.12];

/// "8 %" o "9,8 %".
String _ratePct(double rate) {
  final pct = rate * 100;
  return Cop.percent(pct, decimals: pct == pct.roundToDouble() ? 0 : 1);
}

/// Simulador: cuánto podría crecer lo que aportas cada mes.
///
/// Es una estimación con una tasa que elige la persona; nunca una promesa
/// de rentabilidad.
class SimulatorPage extends ConsumerStatefulWidget {
  const SimulatorPage({super.key, this.goalId, this.initial, this.rate});

  /// Meta con la que se compara ("¿cuándo llego invirtiendo?").
  final String? goalId;

  /// Con cuánto se empieza (p. ej. lo que vale una inversión).
  final int? initial;

  /// Tasa de partida (p. ej. la de un CDT).
  final double? rate;

  @override
  ConsumerState<SimulatorPage> createState() => _SimulatorPageState();
}

class _SimulatorPageState extends ConsumerState<SimulatorPage> {
  late final _initial = TextEditingController(
    text: widget.initial == null || widget.initial == 0
        ? ''
        : '${widget.initial}',
  );
  final _monthly = TextEditingController();
  int _years = 5;
  late double _rate = widget.rate ?? 0.08;
  bool _seededFromGoal = false;

  @override
  void dispose() {
    _initial.dispose();
    _monthly.dispose();
    super.dispose();
  }

  int get _initialAmount => AmountInput.value(_initial.text);
  int get _monthlyAmount => AmountInput.value(_monthly.text);

  /// Tasas visibles: las de siempre y, si viene una, la de partida.
  List<double> get _rates {
    final extra = widget.rate;
    final all = {
      ..._rateOptions,
      if (extra != null) double.parse(extra.toStringAsFixed(4)),
    }.toList()..sort();
    return all;
  }

  /// Parte de la meta (una sola vez, cuando carga).
  void _seed(Goal g, DateTime now) {
    _seededFromGoal = true;
    _initial.text = g.saved == 0 ? '' : '${g.saved}';
    final needed = monthlyNeeded(g, now) ?? monthlyPace(g, now);
    _monthly.text = needed <= 0 ? '' : '$needed';
    final d = g.deadline;
    if (d != null) {
      final months = (d.year - now.year) * 12 + d.month - now.month;
      _years = months <= 12
          ? 1
          : months <= 36
          ? 3
          : months <= 60
          ? 5
          : 10;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = ref.watch(clockProvider)();
    final goal = widget.goalId == null
        ? null
        : ref
              .watch(goalsProvider)
              .value
              ?.where((g) => g.id == widget.goalId)
              .firstOrNull;
    if (goal != null && !_seededFromGoal) _seed(goal, now);

    final months = _years * 12;
    final p = projectGrowth(
      initial: _initialAmount,
      monthly: _monthlyAmount,
      months: months,
      annualRate: _rate,
    );
    final yearly = yearlyValues(
      initial: _initialAmount,
      monthly: _monthlyAmount,
      years: _years,
      annualRate: _rate,
    );
    final hasInput = _initialAmount > 0 || _monthlyAmount > 0;
    final digitsOnly = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(AmountInput.maxDigits),
    ];
    final yearsLabel = _years == 1 ? '1 año' : '$_years años';

    return Scaffold(
      appBar: AppBar(title: const Text('Simulador')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.xs,
            AppSpace.gutter,
            AppSpace.xxl,
          ),
          children: [
            Text(
              'Mira cuánto podría crecer lo que aportas. Tú eliges el plazo '
              'y la tasa.',
              style: AppTypography.body.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: AppSpace.lg),
            // Formulario de varios campos: los montos usan el teclado del
            // sistema (el teclado propio es para pantallas de solo monto).
            TextField(
              controller: _initial,
              keyboardType: TextInputType.number,
              inputFormatters: digitsOnly,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '¿Con cuánto empiezas?',
                prefixText: r'$ ',
                helperText: _initialAmount == 0
                    ? 'Puedes dejarlo vacío.'
                    : Cop.format(_initialAmount),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            TextField(
              controller: _monthly,
              keyboardType: TextInputType.number,
              inputFormatters: digitsOnly,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '¿Cuánto aportas cada mes?',
                prefixText: r'$ ',
                helperText: _monthlyAmount == 0
                    ? null
                    : Cop.format(_monthlyAmount),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            const SectionHeader('¿Por cuánto tiempo?'),
            const SizedBox(height: AppSpace.xs),
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                for (final y in _yearOptions)
                  ChoiceChip(
                    label: Text(y == 1 ? '1 año' : '$y años'),
                    selected: _years == y,
                    onSelected: (_) => setState(() => _years = y),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            const SectionHeader('¿A qué tasa efectiva anual?'),
            const SizedBox(height: AppSpace.xs),
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                for (final r in _rates)
                  ChoiceChip(
                    label: Text('${_ratePct(r)} e. a.'),
                    selected: _rate == r,
                    onSelected: (_) => setState(() => _rate = r),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
            HeroBalance(
              label: 'En $yearsLabel tendrías',
              value: p.finalValue,
              caption: hasInput
                  ? 'Pondrías ${Cop.format(p.contributed)} y rendiría unos '
                        '${Cop.format(p.earned)}'
                  : 'Escribe cuánto aportas para ver el resultado',
            ),
            if (hasInput) ...[
              const SizedBox(height: AppSpace.md),
              QCard(
                child: Column(
                  children: [
                    DetailLine('Empiezas con', Cop.format(_initialAmount)),
                    DetailLine('Aportas al mes', Cop.format(_monthlyAmount)),
                    DetailLine('Pondrías en total', Cop.format(p.contributed)),
                    DetailLine(
                      'Rendimiento estimado',
                      Cop.format(p.earned, signed: true),
                    ),
                    DetailLine(
                      'Total estimado',
                      Cop.format(p.finalValue),
                      emphasis: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              const SectionHeader('Cómo crece año a año'),
              const SizedBox(height: AppSpace.xxs),
              for (final (i, v) in yearly.indexed)
                _YearRow(
                  label: 'Año ${i + 1}',
                  value: v,
                  ratio: p.finalValue <= 0 ? 0 : v / p.finalValue,
                ),
            ],
            if (goal != null) ...[
              const SizedBox(height: AppSpace.xl),
              SectionHeader('Tu meta: ${goal.name}'),
              const SizedBox(height: AppSpace.xs),
              _GoalCompare(
                goal: goal,
                now: now,
                initial: _initialAmount,
                monthly: _monthlyAmount,
                rate: _rate,
              ),
            ],
            const SizedBox(height: AppSpace.xl),
            const QBanner(
              tone: BannerTone.info,
              title: 'Es una estimación',
              message:
                  'Usa la tasa que elegiste y no es una promesa de '
                  'rentabilidad. Lo real puede ser menor, y al invertir '
                  'puedes perder parte de lo que pones.',
            ),
          ],
        ),
      ),
    );
  }
}

class _YearRow extends StatelessWidget {
  const _YearRow({
    required this.label,
    required this.value,
    required this.ratio,
  });

  final String label;
  final int value;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final large = isLargeText(context);
    final amount = MoneyText(
      value,
      animate: false,
      style: AppTypography.body.copyWith(
        color: c.ink,
        fontWeight: FontWeight.w600,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Semantics(
        label: '$label: ${Cop.spoken(value)}',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: context.text.bodyMedium)),
                if (!large) amount,
              ],
            ),
            if (large) amount,
            const SizedBox(height: AppSpace.xxs),
            QProgressBar(
              value: ratio,
              height: AppSpace.xs - AppSpace.xxs,
              semanticLabel: label,
            ),
          ],
        ),
      ),
    );
  }
}

/// Cuándo llegas a la meta con y sin rendimiento, y cuánto aportar para
/// llegar a tiempo.
class _GoalCompare extends StatelessWidget {
  const _GoalCompare({
    required this.goal,
    required this.now,
    required this.initial,
    required this.monthly,
    required this.rate,
  });

  final Goal goal;
  final DateTime now;
  final int initial;
  final int monthly;
  final double rate;

  @override
  Widget build(BuildContext context) {
    final plain = monthsToReach(
      target: goal.target,
      initial: initial,
      monthly: monthly,
      annualRate: 0,
    );
    final grown = monthsToReach(
      target: goal.target,
      initial: initial,
      monthly: monthly,
      annualRate: rate,
    );
    String when(int? m) =>
        m == null ? 'No llegas con este aporte' : Dates.span(m);
    final d = goal.deadline;
    final monthsToDeadline = d == null
        ? null
        : (d.year - now.year) * 12 + d.month - now.month;
    final perMonth = monthsToDeadline == null || monthsToDeadline <= 0
        ? null
        : monthlyForTarget(
            target: goal.target,
            initial: initial,
            months: monthsToDeadline,
            annualRate: rate,
          );
    return QCard(
      child: Column(
        children: [
          DetailLine('Meta', Cop.format(goal.target)),
          DetailLine('Guardando, sin invertir', when(plain)),
          DetailLine('Invirtiendo a ${_ratePct(rate)} e. a.', when(grown)),
          if (perMonth != null)
            DetailLine(
              'Para llegar a tiempo aporta',
              '${Cop.format(perMonth)} al mes',
            ),
        ],
      ),
    );
  }
}
