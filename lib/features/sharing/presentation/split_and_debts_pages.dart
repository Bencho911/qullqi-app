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

/// Propinas sugeridas (porcentaje).
const _tips = [0, 10, 15];

/// Dividir una cuenta: cuánto paga cada uno, y anotar lo que te deben.
class SplitBillPage extends ConsumerStatefulWidget {
  const SplitBillPage({super.key});

  @override
  ConsumerState<SplitBillPage> createState() => _SplitBillPageState();
}

class _SplitBillPageState extends ConsumerState<SplitBillPage> {
  final _bill = TextEditingController();
  final _names = <TextEditingController>[];
  int _people = 2;
  int _tip = 0;
  bool _saving = false;

  static const _maxPeople = 12;

  int get _amount => AmountInput.value(_bill.text);

  @override
  void dispose() {
    _bill.dispose();
    for (final n in _names) {
      n.dispose();
    }
    super.dispose();
  }

  void _setPeople(int n) {
    final next = n.clamp(2, _maxPeople);
    setState(() {
      _people = next;
      // Un campo de nombre por cada una de las otras personas.
      while (_names.length < next - 1) {
        _names.add(TextEditingController());
      }
      while (_names.length > next - 1) {
        _names.removeLast().dispose();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _names.add(TextEditingController());
  }

  Future<void> _record(BillSplit split) async {
    final named = [
      for (final n in _names)
        if (n.text.trim().isNotEmpty) n.text.trim(),
    ];
    if (named.isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(debtsRepositoryProvider);
      for (final person in named) {
        await repo.add(
          person: person,
          amount: split.perPerson,
          direction: DebtDirection.theyOweMe,
          concept: 'Cuenta compartida',
        );
      }
      if (!mounted) return;
      showQToast(
        context,
        named.length == 1
            ? 'Anotamos lo que te debe ${named.first}'
            : 'Anotamos ${named.length} deudas',
      );
      context.pushReplacement(Routes.personDebts);
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos guardarlo. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final split = BillSplit.of(
      bill: _amount,
      people: _people,
      tipPercent: _tip,
    );
    final hasName = _names.any((n) => n.text.trim().isNotEmpty);
    return Scaffold(
      appBar: AppBar(title: const Text('Dividir una cuenta')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.xs,
            AppSpace.gutter,
            AppSpace.xxl,
          ),
          children: [
            TextField(
              controller: _bill,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(AmountInput.maxDigits),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Total de la cuenta',
                prefixText: r'$ ',
                helperText: _amount == 0 ? null : Cop.format(_amount),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            const SectionHeader('¿Entre cuántos?'),
            const SizedBox(height: AppSpace.xs),
            Row(
              children: [
                IconButton.outlined(
                  tooltip: 'Una persona menos',
                  onPressed: _people > 2 ? () => _setPeople(_people - 1) : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    label: '$_people personas',
                    excludeSemantics: true,
                    child: Text(
                      '$_people personas',
                      textAlign: TextAlign.center,
                      style: context.text.titleMedium,
                    ),
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Una persona más',
                  onPressed: _people < _maxPeople
                      ? () => _setPeople(_people + 1)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            const SectionHeader('Propina'),
            const SizedBox(height: AppSpace.xs),
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                for (final t in _tips)
                  ChoiceChip(
                    label: Text(t == 0 ? 'Sin propina' : '$t %'),
                    selected: _tip == t,
                    onSelected: (_) => setState(() => _tip = t),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            HeroBalance(
              label: 'Cada uno paga',
              value: split.perPerson,
              caption: _amount == 0
                  ? 'Escribe el total de la cuenta'
                  : _tip == 0
                  ? 'Cuenta ${Cop.format(split.bill)} entre ${split.people}'
                  : 'Cuenta ${Cop.format(split.bill)} + propina '
                        '${Cop.format(split.tip)} entre ${split.people}',
            ),
            if (_amount > 0) ...[
              const SizedBox(height: AppSpace.xl),
              const SectionHeader('¿Quiénes te deben?'),
              const SizedBox(height: AppSpace.xs),
              Text(
                'Si pagaste tú, escribe quiénes te deben su parte y la '
                'anotamos como deuda.',
                style: AppTypography.body.copyWith(color: c.inkMuted),
              ),
              const SizedBox(height: AppSpace.sm),
              for (final (i, n) in _names.indexed) ...[
                TextField(
                  controller: n,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(labelText: 'Persona ${i + 1}'),
                ),
                const SizedBox(height: AppSpace.xs),
              ],
              const SizedBox(height: AppSpace.sm),
              QButton(
                label: 'Anotar lo que me deben',
                icon: Icons.edit_note_rounded,
                loading: _saving,
                loadingLabel: 'Guardando',
                onPressed: hasName ? () => _record(split) : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Deudas entre personas: lo que te deben y lo que debes.
class PersonDebtsPage extends ConsumerWidget {
  const PersonDebtsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(personDebtsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Deudas entre personas')),
      body: switch (debts) {
        AsyncData(:final value) when value.isEmpty => MessageBody(
          child: EmptyState(
            icon: Icons.handshake_outlined,
            title: 'Que nadie se te olvide',
            message:
                'Anota lo que le prestaste a alguien o lo que le debes, y '
                'marca cuando quede pago.',
            actionLabel: 'Anotar una deuda',
            onAction: () => context.push(Routes.newDebt),
          ),
        ),
        AsyncData(:final value) => _list(context, ref, value),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar tus deudas',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(personDebtsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando tus deudas'),
      },
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, List<PersonDebt> all) {
    final totals = DebtTotals.of(all);
    List<PersonDebt> of(DebtDirection d) =>
        all.where((x) => !x.settled && x.direction == d).toList();
    final settled = all.where((x) => x.settled).toList();
    final groups = [
      ('Te deben', of(DebtDirection.theyOweMe)),
      ('Debes', of(DebtDirection.iOwe)),
      ('Saldadas', settled),
    ].where((g) => g.$2.isNotEmpty);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xxl,
      ),
      children: [
        HeroBalance(
          label: totals.net >= 0 ? 'En total te deben' : 'En total debes',
          value: totals.net.abs(),
          caption:
              'Te deben ${Cop.format(totals.owedToMe)} · debes '
              '${Cop.format(totals.iOwe)}',
        ),
        const SizedBox(height: AppSpace.md),
        QButton.secondary(
          label: 'Anotar una deuda',
          icon: Icons.add_rounded,
          onPressed: () => context.push(Routes.newDebt),
        ),
        for (final (title, items) in groups) ...[
          const SizedBox(height: AppSpace.lg),
          SectionHeader(title),
          const SizedBox(height: AppSpace.xs),
          for (final d in items) ...[
            _DebtTile(debt: d, onTap: () => _actions(context, ref, d)),
            const SizedBox(height: AppSpace.xs),
          ],
        ],
      ],
    );
  }

  Future<void> _actions(BuildContext context, WidgetRef ref, PersonDebt d) {
    final repo = ref.read(debtsRepositoryProvider);
    return showQSheet<void>(
      context,
      title: d.person,
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${d.concept} · ${Cop.format(d.amount)} · '
            '${Dates.dayMonth(d.date)}',
            style: AppTypography.body.copyWith(color: sheet.colors.inkMuted),
          ),
          const SizedBox(height: AppSpace.lg),
          if (!d.settled) ...[
            QButton(
              label: d.direction == DebtDirection.theyOweMe
                  ? 'Ya me pagó'
                  : 'Ya le pagué',
              icon: Icons.check_rounded,
              onPressed: () async {
                Navigator.of(sheet).pop();
                await repo.markSettled(d.id);
                if (context.mounted) {
                  showQToast(context, 'Quedó saldada la deuda con ${d.person}');
                }
              },
            ),
            if (d.direction == DebtDirection.theyOweMe) ...[
              const SizedBox(height: AppSpace.xs),
              QButton.secondary(
                label: 'Copiar recordatorio',
                icon: Icons.copy_rounded,
                onPressed: () async {
                  Navigator.of(sheet).pop();
                  await Clipboard.setData(
                    ClipboardData(
                      text:
                          'Hola ${d.person}, te recuerdo los '
                          '${Cop.format(d.amount)} de '
                          '${d.concept.toLowerCase()}. ¡Gracias!',
                    ),
                  );
                  if (context.mounted) {
                    showQToast(context, 'Copiamos el recordatorio');
                  }
                },
              ),
            ],
          ],
          const SizedBox(height: AppSpace.xs),
          QButton.text(
            label: 'Eliminar',
            icon: Icons.delete_outline_rounded,
            color: sheet.colors.danger,
            onPressed: () async {
              Navigator.of(sheet).pop();
              await repo.delete(d.id);
              if (context.mounted) {
                showQToast(context, 'Eliminamos la deuda con ${d.person}');
              }
            },
          ),
        ],
      ),
    );
  }
}

class _DebtTile extends StatelessWidget {
  const _DebtTile({required this.debt, required this.onTap});

  final PersonDebt debt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final d = debt;
    final mine = d.direction == DebtDirection.theyOweMe;
    return QCard(
      onTap: onTap,
      semanticLabel:
          '${d.person}. ${d.concept}. ${mine ? 'Te debe' : 'Le debes'} '
          '${Cop.spoken(d.amount)}${d.settled ? '. Saldada' : ''}',
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: ExcludeSemantics(
        child: AmountRowLayout(
          leading: InitialsAvatar(d.person.substring(0, 1).toUpperCase()),
          title: d.person,
          titleLines: 2,
          details: [
            Text(
              '${d.concept} · ${Dates.dayMonth(d.date)}',
              style: context.text.bodySmall,
            ),
            if (d.settled) ...[
              const SizedBox(height: AppSpace.xxs),
              const StatusPill('Saldada', tone: PillTone.primary),
            ],
          ],
          trailing: MoneyText(
            d.amount,
            animate: false,
            style: AppTypography.body.copyWith(
              color: d.settled
                  ? c.inkSubtle
                  : mine
                  ? c.income
                  : c.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Anotar una deuda entre personas.
class NewDebtPage extends ConsumerStatefulWidget {
  const NewDebtPage({super.key});

  @override
  ConsumerState<NewDebtPage> createState() => _NewDebtPageState();
}

class _NewDebtPageState extends ConsumerState<NewDebtPage> {
  final _person = TextEditingController();
  final _concept = TextEditingController();
  final _amount = TextEditingController();
  DebtDirection _direction = DebtDirection.theyOweMe;
  bool _tried = false;
  bool _saving = false;

  int get _value => AmountInput.value(_amount.text);

  @override
  void dispose() {
    _person.dispose();
    _concept.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _tried = true);
    if (_person.text.trim().length < 2 || _value <= 0) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(debtsRepositoryProvider)
          .add(
            person: _person.text,
            amount: _value,
            direction: _direction,
            concept: _concept.text.trim().isEmpty
                ? 'Sin detalle'
                : _concept.text,
          );
      if (!mounted) return;
      showQToast(context, 'Anotamos la deuda con ${_person.text.trim()}');
      context.pop();
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos guardarla. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DiscardGuard(
      dirty: !_saving && (_person.text.isNotEmpty || _amount.text.isNotEmpty),
      title: '¿Descartar esta deuda?',
      confirmLabel: 'Descartar deuda',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Anotar una deuda'),
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
              SegmentedButton<DebtDirection>(
                showSelectedIcon: false,
                segments: [
                  for (final d in DebtDirection.values)
                    ButtonSegment(value: d, label: Text(d.label)),
                ],
                selected: {_direction},
                onSelectionChanged: (s) => setState(() => _direction = s.first),
              ),
              const SizedBox(height: AppSpace.lg),
              TextField(
                controller: _person,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _direction == DebtDirection.theyOweMe
                      ? '¿Quién te debe?'
                      : '¿A quién le debes?',
                  errorText: _tried && _person.text.trim().length < 2
                      ? 'Escribe el nombre de la persona.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(AmountInput.maxDigits),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '¿Cuánto?',
                  prefixText: r'$ ',
                  helperText: _value == 0 ? null : Cop.format(_value),
                  errorText: _tried && _value <= 0
                      ? 'Escribe cuánto es.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _concept,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: '¿Por qué? (opcional)',
                  hintText: 'Ej. Almuerzo, préstamo',
                ),
              ),
              const SizedBox(height: AppSpace.xl),
              QButton(
                label: 'Anotar deuda',
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
