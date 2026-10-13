import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/planning/data/plans_repository.dart';
import 'package:qullqi/features/planning/domain/plans.dart';
import 'package:qullqi/features/planning/presentation/widgets/plan_cards.dart';

/// "Marzo de 2027".
String _monthYear(DateTime d) {
  final m = Dates.month(d);
  return '${m[0].toUpperCase()}${m.substring(1)} de ${d.year}';
}

/// Detalle de una meta: cuánto llevas, cuánto separar y tus aportes.
class GoalDetailPage extends ConsumerWidget {
  const GoalDetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(goalsProvider);
    final goal = goals.value?.where((g) => g.id == id).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Meta')),
      body: switch (goals) {
        AsyncValue(hasValue: true) when goal != null => _GoalDetail(g: goal),
        AsyncValue(hasValue: true) => MessageBody(
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Esta meta ya no existe',
            message: 'Puede que la hayas eliminado.',
            actionLabel: 'Ver mis planes',
            onAction: () => context.go(Routes.planning),
          ),
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar la meta',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(goalsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando la meta'),
      },
    );
  }
}

class _GoalDetail extends ConsumerWidget {
  const _GoalDetail({required this.g});

  final Goal g;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final now = ref.watch(clockProvider)();
    final needed = monthlyNeeded(g, now);
    final pace = monthlyPace(g, now);

    Future<void> delete() async {
      final ok = await confirmDestructive(
        context,
        title: '¿Eliminar la meta ${g.name}?',
        message:
            'Se borra el seguimiento. La plata que separaste sigue en tus '
            'cuentas.',
        confirmLabel: 'Eliminar ${g.name}',
      );
      if (!ok || !context.mounted) return;
      try {
        await ref.read(plansRepositoryProvider).deleteGoal(g.id);
        if (context.mounted) {
          showQToast(context, 'Eliminamos ${g.name}');
          context.pop();
        }
      } on Object {
        if (context.mounted) {
          showQToast(context, 'No pudimos eliminarla. Inténtalo de nuevo.');
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xxl,
      ),
      children: [
        Semantics(
          header: true,
          child: Text(g.name, style: context.text.headlineSmall),
        ),
        const SizedBox(height: AppSpace.lg),
        Row(
          children: [
            QProgressRing(
              value: g.ratio,
              size: _ringSize,
              semanticLabel: g.name,
              child: Text(
                Cop.percent(g.ratio * 100),
                style: AppTypography.subtitle.copyWith(color: c.ink),
              ),
            ),
            const SizedBox(width: AppSpace.lg),
            Expanded(
              child: Semantics(
                label:
                    'Llevas ${Cop.spoken(g.saved)} de ${Cop.spoken(g.target)}',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Llevas', style: context.text.bodySmall),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MoneyText(
                        g.saved,
                        style: AppTypography.title.copyWith(color: c.ink),
                      ),
                    ),
                    Text(
                      'de ${Cop.format(g.target)}',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        QCard(
          child: Column(
            children: [
              DetailLine('Te falta', Cop.format(g.missing)),
              DetailLine(
                'Tu ritmo',
                pace > 0
                    ? '${Cop.format(pace)} al mes'
                    : 'Sin aportes recientes',
              ),
              if (g.deadline != null)
                DetailLine('Fecha meta', _monthYear(g.deadline!)),
              if (needed != null)
                DetailLine('Separa al mes', Cop.format(needed)),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(goalLine(g, now), style: context.text.bodySmall),
        // Cumplida, la línea de arriba ya lo dice: no hay botón que no hace
        // nada.
        if (!g.done) ...[
          const SizedBox(height: AppSpace.lg),
          QButton(
            label: 'Separar plata',
            icon: Icons.savings_outlined,
            onPressed: () => context.push(Routes.contribute(g.id)),
          ),
          const SizedBox(height: AppSpace.xs),
          QButton.secondary(
            label: 'Simular invirtiéndola',
            icon: Icons.trending_up_rounded,
            onPressed: () => context.push(Routes.simulatorForGoal(g.id)),
          ),
        ],
        const SizedBox(height: AppSpace.xl),
        const SectionHeader('Tus aportes'),
        if (g.contributions.isEmpty)
          const SectionNote('Aún no separas plata para esta meta.')
        else
          for (final a in g.contributions)
            DetailLine(Dates.dayMonth(a.date), '+${Cop.format(a.amount)}'),
        const SizedBox(height: AppSpace.xl),
        QButton.text(
          label: 'Eliminar meta',
          icon: Icons.delete_outline_rounded,
          color: c.danger,
          onPressed: delete,
        ),
      ],
    );
  }
}

/// Tamaño del anillo de avance en el detalle.
const double _ringSize = 96;

/// Plazos sugeridos para una meta (en meses); `null` = sin fecha.
const _terms = <int?>[null, 3, 6, 12, 24];

/// Crear una meta: nombre, cuánto y para cuándo.
class NewGoalPage extends ConsumerStatefulWidget {
  const NewGoalPage({super.key});

  @override
  ConsumerState<NewGoalPage> createState() => _NewGoalPageState();
}

class _NewGoalPageState extends ConsumerState<NewGoalPage> {
  final _name = TextEditingController();
  final _target = TextEditingController();
  int? _months = 6;
  Ownership _ownership = Ownership.personal;
  bool _tried = false;
  bool _saving = false;

  int get _amount => AmountInput.value(_target.text);

  DateTime? _deadline(DateTime now) =>
      _months == null ? null : DateTime(now.year, now.month + _months!);

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _tried = true);
    if (_name.text.trim().length < 2 || _amount <= 0) return;
    setState(() => _saving = true);
    final now = ref.read(clockProvider)();
    try {
      final g = await ref
          .read(plansRepositoryProvider)
          .createGoal(
            name: _name.text,
            target: _amount,
            ownership: _ownership,
            deadline: _months == null
                ? null
                : DateTime(now.year, now.month + _months!),
          );
      if (!mounted) return;
      showQToast(context, 'Creamos tu meta ${g.name}');
      context.pushReplacement(Routes.goal(g.id));
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos crearla. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBusiness = ref.watch(currentUserProvider).hasBusiness;
    final now = ref.watch(clockProvider)();
    final perMonth = _months == null || _amount == 0
        ? null
        : (_amount / _months!).ceil();
    return DiscardGuard(
      dirty: !_saving && (_name.text.isNotEmpty || _target.text.isNotEmpty),
      title: '¿Descartar esta meta?',
      confirmLabel: 'Descartar meta',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Crear meta'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.xs,
              AppSpace.gutter,
              AppSpace.xl,
            ),
            children: [
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '¿Para qué ahorras?',
                  hintText: 'Ej. Fondo de emergencia, viaje, computador',
                  errorText: _tried && _name.text.trim().length < 2
                      ? 'Ponle un nombre a tu meta.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              // Formulario de varios campos: el monto usa el teclado del
              // sistema (el teclado propio es para pantallas de solo monto).
              TextField(
                controller: _target,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(AmountInput.maxDigits),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '¿Cuánto necesitas?',
                  prefixText: r'$ ',
                  helperText: _amount == 0 ? null : Cop.format(_amount),
                  errorText: _tried && _amount <= 0
                      ? 'Escribe cuánto necesitas.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('¿Para cuándo?'),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  for (final m in _terms)
                    ChoiceChip(
                      label: Text(
                        m == null
                            ? 'Sin fecha'
                            : m < 12
                            ? '$m meses'
                            : m == 12
                            ? '1 año'
                            : '${m ~/ 12} años',
                      ),
                      selected: _months == m,
                      onSelected: (_) => setState(() => _months = m),
                    ),
                ],
              ),
              if (perMonth != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  'Separa ${Cop.format(perMonth)} al mes para llegar en '
                  '${_monthYear(_deadline(now)!).toLowerCase()}.',
                  style: context.text.bodySmall,
                ),
              ],
              if (hasBusiness) ...[
                const SizedBox(height: AppSpace.lg),
                const SectionHeader('¿De quién es?'),
                const SizedBox(height: AppSpace.xs),
                SegmentedButton<Ownership>(
                  showSelectedIcon: false,
                  segments: [
                    for (final o in Ownership.values)
                      ButtonSegment(value: o, label: Text(o.label)),
                  ],
                  selected: {_ownership},
                  onSelectionChanged: (s) =>
                      setState(() => _ownership = s.first),
                ),
              ],
              const SizedBox(height: AppSpace.xl),
              QButton(
                label: 'Crear meta',
                loading: _saving,
                loadingLabel: 'Guardando',
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Separar plata para una meta.
class ContributePage extends ConsumerStatefulWidget {
  const ContributePage({required this.goalId, super.key});

  final String goalId;

  @override
  ConsumerState<ContributePage> createState() => _ContributePageState();
}

class _ContributePageState extends ConsumerState<ContributePage> {
  String _digits = '';
  bool _tried = false;
  bool _saving = false;

  int get _amount => AmountInput.value(_digits);

  Future<void> _save(Goal g) async {
    setState(() => _tried = true);
    if (_amount <= 0) return;
    setState(() => _saving = true);
    try {
      await ref.read(plansRepositoryProvider).contribute(g.id, _amount);
      if (!mounted) return;
      final after = g.saved + _amount;
      showQToast(
        context,
        after >= g.target
            ? '¡Lo lograste! Completaste ${g.name}'
            : 'Separaste ${Cop.format(_amount)} para ${g.name}',
      );
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos guardarlo. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final goals = ref.watch(goalsProvider);
    final goal = goals.value?.where((g) => g.id == widget.goalId).firstOrNull;
    final now = ref.watch(clockProvider)();
    return DiscardGuard(
      dirty: !_saving && _amount > 0,
      title: '¿Descartar este aporte?',
      confirmLabel: 'Descartar aporte',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Separar plata'),
        ),
        body: SafeArea(
          child: goal == null
              ? switch (goals) {
                  AsyncValue(hasValue: true) => MessageBody(
                    child: EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'Esta meta ya no existe',
                      message: 'Puede que la hayas eliminado.',
                      actionLabel: 'Ver mis planes',
                      onAction: () => context.go(Routes.planning),
                    ),
                  ),
                  AsyncError() => MessageBody(
                    child: EmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'No pudimos cargar la meta',
                      message:
                          'Revisa tu conexión a internet e inténtalo de nuevo.',
                      actionLabel: 'Reintentar',
                      onAction: () => ref.invalidate(goalsProvider),
                    ),
                  ),
                  _ => const PageSkeleton(label: 'Cargando la meta', rows: 2),
                }
              : KeypadLayout(
                  fields: [
                    AmountDisplay(
                      digits: _digits,
                      label: '¿Cuánto separas para ${goal.name}?',
                      error: _tried && _amount <= 0 ? 'Escribe cuánto.' : null,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    if (monthlyNeeded(goal, now) case final n?)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: QButton.text(
                          label: 'Usar lo del mes: ${Cop.format(n)}',
                          onPressed: () => setState(() => _digits = '$n'),
                        ),
                      ),
                    const TrustNote(
                      'Separar no mueve plata: sigue en tu cuenta y la cuentas '
                      'como parte de tu meta.',
                    ),
                  ],
                  keypad: AmountKeypad(
                    digits: _digits,
                    onChanged: (d) => setState(() => _digits = d),
                  ),
                  action: QButton(
                    label: _amount > 0
                        ? 'Separar ${Cop.format(_amount)}'
                        : 'Separar plata',
                    loading: _saving,
                    loadingLabel: 'Guardando',
                    onPressed: () => _save(goal),
                  ),
                ),
        ),
      ),
    );
  }
}
