import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';
import 'package:inti/core/format/dates.dart';
import 'package:inti/core/money/money.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/sharing/data/sharing_repositories.dart';
import 'package:inti/features/sharing/domain/sharing.dart';

/// Metas compartidas: ahorrar entre varias personas.
class SharedGoalsPage extends ConsumerWidget {
  const SharedGoalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(sharedGoalsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Metas compartidas')),
      body: switch (goals) {
        AsyncData(:final value) when value.isEmpty => MessageBody(
          child: EmptyState(
            icon: Icons.volunteer_activism_outlined,
            title: 'Ahorren juntos',
            message:
                'Crea una meta con tu pareja o tus amigos y vean cuánto ha '
                'puesto cada uno.',
            actionLabel: 'Crear meta compartida',
            onAction: () => context.push(Routes.newSharedGoal),
          ),
        ),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.xs,
            AppSpace.gutter,
            AppSpace.xxl,
          ),
          children: [
            HeroBalance(
              label: 'Han ahorrado juntos',
              value: value.fold(0, (s, g) => s + g.saved),
              caption: value.length == 1
                  ? 'En 1 meta compartida'
                  : 'En ${value.length} metas compartidas',
            ),
            const SizedBox(height: AppSpace.md),
            QButton.secondary(
              label: 'Crear meta compartida',
              icon: Icons.add_rounded,
              onPressed: () => context.push(Routes.newSharedGoal),
            ),
            const SizedBox(height: AppSpace.lg),
            const SectionHeader('Tus metas'),
            const SizedBox(height: AppSpace.xs),
            for (final g in value) ...[
              _GoalCard(goal: g),
              const SizedBox(height: AppSpace.xs),
            ],
          ],
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar tus metas',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(sharedGoalsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando tus metas compartidas'),
      },
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal});

  final SharedGoal goal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final g = goal;
    return QCard(
      onTap: () => context.push(Routes.sharedGoal(g.id)),
      semanticLabel:
          '${g.name}. Llevan ${Cop.spoken(g.saved)} de '
          '${Cop.spoken(g.target)}. '
          '${g.members.map((m) => m.label).join(', ')}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const IconTile(icon: Icons.volunteer_activism_outlined),
                const SizedBox(width: AppSpace.sm),
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
                        g.members.map((m) => m.label).join(', '),
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.sm),
            QProgressBar(value: g.ratio, semanticLabel: g.name),
            const SizedBox(height: AppSpace.xs),
            Text(
              '${Cop.format(g.saved)} de ${Cop.format(g.target)}',
              style: AppTypography.label.copyWith(color: c.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// Detalle de una meta compartida: avance, aporte de cada uno y aportar.
class SharedGoalDetailPage extends ConsumerWidget {
  const SharedGoalDetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(sharedGoalsProvider);
    final g = goals.value?.where((x) => x.id == id).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Meta compartida')),
      body: switch (goals) {
        AsyncValue(hasValue: true) when g != null => _Detail(goal: g),
        AsyncValue(hasValue: true) => MessageBody(
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Esta meta ya no existe',
            message: 'Puede que la hayas eliminado.',
            actionLabel: 'Ver metas compartidas',
            onAction: () => context.pushReplacement(Routes.sharedGoals),
          ),
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar la meta',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(sharedGoalsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando la meta'),
      },
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.goal});

  final SharedGoal goal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final g = goal;
    final by = g.byMember;
    final maxPut = by.values.fold<int>(1, (m, v) => v > m ? v : m);

    Future<void> delete() async {
      final ok = await confirmDestructive(
        context,
        title: '¿Eliminar la meta ${g.name}?',
        message: 'Se borra el seguimiento. La plata sigue donde esté.',
        confirmLabel: 'Eliminar ${g.name}',
      );
      if (!ok || !context.mounted) return;
      await ref.read(sharedGoalsRepositoryProvider).delete(g.id);
      if (context.mounted) {
        showQToast(context, 'Eliminamos ${g.name}');
        context.pop();
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
              size: 96,
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
                    'Llevan ${Cop.spoken(g.saved)} de ${Cop.spoken(g.target)}',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Llevan', style: context.text.bodySmall),
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
              DetailLine('Falta', Cop.format(g.missing)),
              DetailLine('A cada uno le tocaría', Cop.format(g.fairShare)),
              if (g.deadline != null)
                DetailLine(
                  'Para',
                  '${Dates.month(g.deadline!)} de ${g.deadline!.year}',
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        const SectionHeader('Cuánto ha puesto cada uno'),
        const SizedBox(height: AppSpace.xs),
        for (final m in g.members)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
            child: Semantics(
              label:
                  '${m.label}: ${Cop.spoken(by[m.id] ?? 0)} de '
                  '${Cop.spoken(g.fairShare)} que le tocan',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(m.label, style: context.text.bodyMedium),
                      ),
                      MoneyText(
                        by[m.id] ?? 0,
                        animate: false,
                        style: AppTypography.body.copyWith(
                          color: c.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xxs),
                  QProgressBar(
                    value: (by[m.id] ?? 0) / maxPut,
                    height: AppSpace.xs - AppSpace.xxs,
                    semanticLabel: m.label,
                  ),
                ],
              ),
            ),
          ),
        if (!g.done) ...[
          const SizedBox(height: AppSpace.lg),
          QButton(
            label: 'Aportar a esta meta',
            icon: Icons.savings_outlined,
            onPressed: () => _contribute(context, ref, g),
          ),
        ],
        const SizedBox(height: AppSpace.xl),
        const TrustNote(
          'Aportar solo anota lo que pones: no mueve plata entre cuentas.',
        ),
        const SizedBox(height: AppSpace.lg),
        QButton.text(
          label: 'Eliminar meta',
          icon: Icons.delete_outline_rounded,
          color: c.danger,
          onPressed: delete,
        ),
      ],
    );
  }

  Future<void> _contribute(BuildContext context, WidgetRef ref, SharedGoal g) {
    return showQSheet<void>(
      context,
      title: 'Aportar a ${g.name}',
      builder: (sheet) => _ContributeForm(
        goal: g,
        onSaved: (who, amount) async {
          Navigator.of(sheet).pop();
          await ref
              .read(sharedGoalsRepositoryProvider)
              .contribute(g.id, who.id, amount);
          if (context.mounted) {
            showQToast(
              context,
              '${who.isMe ? 'Aportaste' : '${who.name} aportó'} '
              '${Cop.format(amount)}',
            );
          }
        },
      ),
    );
  }
}

class _ContributeForm extends StatefulWidget {
  const _ContributeForm({required this.goal, required this.onSaved});

  final SharedGoal goal;
  final Future<void> Function(Person who, int amount) onSaved;

  @override
  State<_ContributeForm> createState() => _ContributeFormState();
}

class _ContributeFormState extends State<_ContributeForm> {
  final _amount = TextEditingController();
  late Person _who = widget.goal.members.first;
  bool _tried = false;

  int get _value => AmountInput.value(_amount.text);

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpace.xs,
          runSpacing: AppSpace.xs,
          children: [
            for (final m in widget.goal.members)
              ChoiceChip(
                label: Text(m.isMe ? 'Yo' : m.name),
                selected: _who.id == m.id,
                onSelected: (_) => setState(() => _who = m),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        TextField(
          controller: _amount,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(AmountInput.maxDigits),
          ],
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: '¿Cuánto aporta?',
            prefixText: r'$ ',
            helperText: _value == 0 ? null : Cop.format(_value),
            errorText: _tried && _value <= 0 ? 'Escribe cuánto.' : null,
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        QButton(
          label: _value > 0 ? 'Aportar ${Cop.format(_value)}' : 'Aportar',
          onPressed: () {
            setState(() => _tried = true);
            if (_value > 0) unawaited(widget.onSaved(_who, _value));
          },
        ),
      ],
    );
  }
}

/// Crear una meta compartida.
class NewSharedGoalPage extends ConsumerStatefulWidget {
  const NewSharedGoalPage({super.key});

  @override
  ConsumerState<NewSharedGoalPage> createState() => _NewSharedGoalPageState();
}

class _NewSharedGoalPageState extends ConsumerState<NewSharedGoalPage> {
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _others = [TextEditingController()];
  bool _tried = false;
  bool _saving = false;

  static const _maxOthers = 5;

  int get _amount => AmountInput.value(_target.text);

  List<String> get _names => [
    for (final o in _others)
      if (o.text.trim().isNotEmpty) o.text.trim(),
  ];

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    for (final o in _others) {
      o.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _tried = true);
    if (_name.text.trim().length < 2 || _amount <= 0 || _names.isEmpty) return;
    setState(() => _saving = true);
    try {
      final g = await ref
          .read(sharedGoalsRepositoryProvider)
          .create(name: _name.text, target: _amount, otherMembers: _names);
      if (!mounted) return;
      showQToast(context, 'Creamos la meta ${g.name}');
      context.pushReplacement(Routes.sharedGoal(g.id));
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos crearla. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = _names.length + 1;
    return DiscardGuard(
      dirty: !_saving && (_name.text.isNotEmpty || _target.text.isNotEmpty),
      title: '¿Descartar esta meta?',
      confirmLabel: 'Descartar meta',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Meta compartida'),
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
                  labelText: '¿Para qué ahorran?',
                  hintText: 'Ej. Viaje, regalo, muebles',
                  errorText: _tried && _name.text.trim().length < 2
                      ? 'Ponle un nombre a la meta.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _target,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(AmountInput.maxDigits),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '¿Cuánto necesitan?',
                  prefixText: r'$ ',
                  helperText: _amount == 0
                      ? null
                      : '${Cop.format(_amount)} · '
                            '${Cop.format((_amount / people).ceil())} '
                            'por persona',
                  errorText: _tried && _amount <= 0
                      ? 'Escribe cuánto necesitan.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('¿Con quién?'),
              const SizedBox(height: AppSpace.xs),
              for (final (i, o) in _others.indexed) ...[
                TextField(
                  controller: o,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Persona ${i + 1}',
                    errorText: _tried && i == 0 && _names.isEmpty
                        ? 'Agrega al menos a una persona.'
                        : null,
                    suffixIcon: _others.length > 1
                        ? IconButton(
                            tooltip: 'Quitar persona ${i + 1}',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() {
                              _others.removeAt(i).dispose();
                            }),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
              ],
              if (_others.length < _maxOthers)
                QButton.secondary(
                  label: 'Agregar persona',
                  icon: Icons.person_add_alt_1_outlined,
                  onPressed: () =>
                      setState(() => _others.add(TextEditingController())),
                ),
              const SizedBox(height: AppSpace.xl),
              QButton(
                label: 'Crear meta',
                loading: _saving,
                loadingLabel: 'Creando',
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
