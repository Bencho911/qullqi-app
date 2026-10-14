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

/// "Te deben $74.500", "Debes $30.000" o "Estás a mano".
String myBalanceLine(int balance) => balance > 0
    ? 'Te deben ${Cop.format(balance)}'
    : balance < 0
    ? 'Debes ${Cop.format(-balance)}'
    : 'Estás a mano';

/// Lo mismo, pero hablando de otra persona.
String balanceLineOf(Person p, int balance) {
  if (p.isMe) return myBalanceLine(balance);
  return balance > 0
      ? 'Le deben ${Cop.format(balance)}'
      : balance < 0
      ? 'Debe ${Cop.format(-balance)}'
      : 'A mano';
}

/// Datos de los grupos ya cargados.
class _GroupsData {
  const _GroupsData(this.groups, this.expenses, this.settlements);

  final List<SharedGroup> groups;
  final List<SharedExpense> expenses;
  final List<Settlement> settlements;

  int myBalance(SharedGroup g) =>
      balancesOf(g, expenses, settlements)[meId] ?? 0;
}

/// Junta las tres fuentes; `null` mientras alguna carga.
AsyncValue<_GroupsData> _watchGroups(WidgetRef ref) {
  final groups = ref.watch(groupsProvider);
  final expenses = ref.watch(sharedExpensesProvider);
  final settlements = ref.watch(settlementsProvider);
  for (final v in [groups, expenses, settlements]) {
    if (v.hasError) return AsyncError(v.error!, v.stackTrace!);
  }
  if (!groups.hasValue || !expenses.hasValue || !settlements.hasValue) {
    return const AsyncLoading();
  }
  return AsyncData(
    _GroupsData(
      groups.requireValue,
      expenses.requireValue,
      settlements.requireValue,
    ),
  );
}

/// Grupos: la casa, un viaje, una salida.
class GroupsPage extends ConsumerWidget {
  const GroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = _watchGroups(ref);
    return Scaffold(
      appBar: AppBar(title: const Text('Grupos')),
      body: switch (data) {
        AsyncData(:final value) when value.groups.isEmpty => MessageBody(
          child: EmptyState(
            icon: Icons.groups_2_outlined,
            title: 'Comparte gastos con alguien',
            message:
                'Crea un grupo para la casa, un viaje o una salida. Anota '
                'quién pagó y te decimos quién le debe a quién.',
            actionLabel: 'Crear grupo',
            onAction: () => context.push(Routes.newGroup),
          ),
        ),
        AsyncData(:final value) => _list(context, value),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar tus grupos',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref
              ..invalidate(groupsProvider)
              ..invalidate(sharedExpensesProvider)
              ..invalidate(settlementsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando tus grupos'),
      },
    );
  }

  Widget _list(BuildContext context, _GroupsData d) {
    final net = d.groups.fold<int>(0, (s, g) => s + d.myBalance(g));
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xxl,
      ),
      children: [
        HeroBalance(
          label: 'En tus grupos',
          value: net,
          caption: net > 0
              ? 'En total te deben'
              : net < 0
              ? 'En total debes'
              : 'Estás a mano con todos',
        ),
        const SizedBox(height: AppSpace.md),
        QButton.secondary(
          label: 'Crear grupo',
          icon: Icons.add_rounded,
          onPressed: () => context.push(Routes.newGroup),
        ),
        const SizedBox(height: AppSpace.lg),
        const SectionHeader('Tus grupos'),
        const SizedBox(height: AppSpace.xs),
        for (final g in d.groups) ...[
          QCard(
            onTap: () => context.push(Routes.group(g.id)),
            semanticLabel:
                '${g.name}. ${g.members.length} personas. '
                '${myBalanceLine(d.myBalance(g))}',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  IconTile(icon: g.kind.icon),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.name,
                          style: AppTypography.body.copyWith(
                            color: context.colors.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          g.members.map((m) => m.label).join(', '),
                          style: context.text.bodySmall,
                        ),
                        Text(
                          myBalanceLine(d.myBalance(g)),
                          style: AppTypography.label.copyWith(
                            color: d.myBalance(g) > 0
                                ? context.colors.income
                                : context.colors.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: context.colors.inkSubtle,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
        ],
      ],
    );
  }
}

/// Detalle de un grupo: saldos, gastos y cómo saldar.
class GroupDetailPage extends ConsumerWidget {
  const GroupDetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = _watchGroups(ref);
    final group = data.value?.groups.where((g) => g.id == id).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Grupo')),
      body: switch (data) {
        AsyncData(:final value) when group != null => _Detail(
          group: group,
          data: value,
        ),
        AsyncData() => MessageBody(
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Este grupo ya no existe',
            message: 'Puede que lo hayas eliminado.',
            actionLabel: 'Ver mis grupos',
            onAction: () => context.pushReplacement(Routes.groups),
          ),
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar el grupo',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(groupsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando el grupo'),
      },
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.group, required this.data});

  final SharedGroup group;
  final _GroupsData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final balances = balancesOf(group, data.expenses, data.settlements);
    final transfers = simplifyDebts(balances);
    final expenses = data.expenses.where((e) => e.groupId == group.id).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    String name(String id) => group.member(id)?.label ?? id;

    Future<void> deleteGroup() async {
      final ok = await confirmDestructive(
        context,
        title: '¿Eliminar el grupo ${group.name}?',
        message: 'Se borran sus gastos y saldos. No se puede deshacer.',
        confirmLabel: 'Eliminar ${group.name}',
      );
      if (!ok || !context.mounted) return;
      await ref.read(groupsRepositoryProvider).deleteGroup(group.id);
      if (context.mounted) {
        showQToast(context, 'Eliminamos ${group.name}');
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
          child: Text(group.name, style: context.text.headlineSmall),
        ),
        Text(
          '${group.kind.label} · '
          '${group.members.map((m) => m.label).join(', ')}',
          style: context.text.bodySmall,
        ),
        const SizedBox(height: AppSpace.lg),
        QCard(
          child: Column(
            children: [
              for (final m in group.members)
                DetailLine(m.label, balanceLineOf(m, balances[m.id] ?? 0)),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (transfers.isNotEmpty)
          QButton(
            label: 'Saldar cuentas',
            icon: Icons.handshake_outlined,
            onPressed: () => _settleSheet(context, ref, transfers, name),
          )
        else
          Row(
            children: [
              Icon(Icons.check_circle_rounded, color: c.income, size: 18),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text(
                  expenses.isEmpty
                      ? 'Aún no hay gastos.'
                      : 'Todos están a mano.',
                  style: context.text.bodyMedium,
                ),
              ),
            ],
          ),
        const SizedBox(height: AppSpace.xs),
        QButton.secondary(
          label: 'Agregar gasto',
          icon: Icons.add_rounded,
          onPressed: () => context.push(Routes.addSharedExpense(group.id)),
        ),
        const SizedBox(height: AppSpace.xl),
        const SectionHeader('Gastos'),
        const SizedBox(height: AppSpace.xs),
        if (expenses.isEmpty)
          const SectionNote('Anota el primero y te decimos quién debe qué.')
        else
          for (final e in expenses) ...[
            QCard(
              onTap: () => _expenseSheet(context, ref, e, name),
              semanticLabel:
                  '${e.title}. ${Cop.spoken(e.amount)}. Pagó '
                  '${name(e.paidBy)}. ${Dates.dayMonth(e.date)}',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    const IconTile(icon: Icons.receipt_long_outlined),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.title,
                            style: AppTypography.body.copyWith(
                              color: c.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Pagó ${name(e.paidBy)} · '
                            '${Dates.dayMonth(e.date)}',
                            style: context.text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    MoneyText(
                      e.amount,
                      animate: false,
                      style: AppTypography.body.copyWith(
                        color: c.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpace.xs),
          ],
        const SizedBox(height: AppSpace.xl),
        QButton.text(
          label: 'Eliminar grupo',
          icon: Icons.delete_outline_rounded,
          color: c.danger,
          onPressed: deleteGroup,
        ),
      ],
    );
  }

  Future<void> _settleSheet(
    BuildContext context,
    WidgetRef ref,
    List<Transfer> transfers,
    String Function(String) name,
  ) {
    return showQSheet<void>(
      context,
      title: 'Saldar cuentas',
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Con estos pagos quedan todos a mano.',
            style: AppTypography.body.copyWith(color: sheet.colors.inkMuted),
          ),
          const SizedBox(height: AppSpace.md),
          for (final t in transfers) ...[
            DetailLine(
              t.from == meId
                  ? 'Tú le pagas a ${name(t.to)}'
                  : t.to == meId
                  ? '${name(t.from)} te paga a ti'
                  : '${name(t.from)} le paga a ${name(t.to)}',
              Cop.format(t.amount),
            ),
            QButton.secondary(
              label: 'Ya pagó ${Cop.format(t.amount)}',
              onPressed: () async {
                Navigator.of(sheet).pop();
                await ref
                    .read(groupsRepositoryProvider)
                    .settle(
                      groupId: group.id,
                      from: t.from,
                      to: t.to,
                      amount: t.amount,
                    );
                if (context.mounted) {
                  showQToast(
                    context,
                    t.from == meId
                        ? 'Anotamos tu pago a ${name(t.to)}'
                        : t.to == meId
                        ? 'Anotamos que ${name(t.from)} te pagó'
                        : 'Anotamos que ${name(t.from)} le pagó a '
                              '${name(t.to)}',
                  );
                }
              },
            ),
            const SizedBox(height: AppSpace.sm),
          ],
        ],
      ),
    );
  }

  Future<void> _expenseSheet(
    BuildContext context,
    WidgetRef ref,
    SharedExpense e,
    String Function(String) name,
  ) {
    return showQSheet<void>(
      context,
      title: e.title,
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Pagó ${name(e.paidBy)} · ${Dates.dayMonth(e.date)}',
            style: AppTypography.body.copyWith(color: sheet.colors.inkMuted),
          ),
          const SizedBox(height: AppSpace.sm),
          for (final s in e.shares.entries)
            DetailLine('Le toca a ${name(s.key)}', Cop.format(s.value)),
          const SizedBox(height: AppSpace.lg),
          QButton.text(
            label: 'Eliminar gasto',
            icon: Icons.delete_outline_rounded,
            color: sheet.colors.danger,
            onPressed: () async {
              Navigator.of(sheet).pop();
              await ref.read(groupsRepositoryProvider).deleteExpense(e.id);
              if (context.mounted) {
                showQToast(context, 'Eliminamos ${e.title}');
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Agregar un gasto compartido: qué fue, cuánto, quién pagó y entre quiénes.
class AddSharedExpensePage extends ConsumerStatefulWidget {
  const AddSharedExpensePage({required this.groupId, super.key});

  final String groupId;

  @override
  ConsumerState<AddSharedExpensePage> createState() =>
      _AddSharedExpensePageState();
}

class _AddSharedExpensePageState extends ConsumerState<AddSharedExpensePage> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  String _paidBy = meId;
  Set<String>? _participants;
  bool _tried = false;
  bool _saving = false;

  int get _value => AmountInput.value(_amount.text);

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save(SharedGroup g) async {
    setState(() => _tried = true);
    final who = _participants ?? {for (final m in g.members) m.id};
    if (_title.text.trim().length < 2 || _value <= 0 || who.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(groupsRepositoryProvider)
          .addExpense(
            groupId: g.id,
            title: _title.text,
            amount: _value,
            paidBy: _paidBy,
            // En el orden del grupo, para que el reparto sea estable.
            participants: [
              for (final m in g.members)
                if (who.contains(m.id)) m.id,
            ],
          );
      if (!mounted) return;
      showQToast(context, 'Anotamos ${_title.text.trim()}');
      context.pop();
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos guardarlo. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupsProvider);
    final g = groups.value?.where((x) => x.id == widget.groupId).firstOrNull;
    if (g == null) {
      return Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Agregar gasto'),
        ),
        body: const PageSkeleton(label: 'Cargando el grupo', rows: 2),
      );
    }
    final who = _participants ?? {for (final m in g.members) m.id};
    final each = who.isEmpty || _value == 0 ? 0 : (_value / who.length).ceil();
    return DiscardGuard(
      dirty: !_saving && (_title.text.isNotEmpty || _amount.text.isNotEmpty),
      title: '¿Descartar este gasto?',
      confirmLabel: 'Descartar gasto',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: Text('Gasto en ${g.name}'),
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
                controller: _title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '¿Qué fue?',
                  hintText: 'Ej. Mercado, hotel, cena',
                  errorText: _tried && _title.text.trim().length < 2
                      ? 'Escribe qué fue el gasto.'
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
                  labelText: '¿Cuánto fue?',
                  prefixText: r'$ ',
                  helperText: _value == 0 ? null : Cop.format(_value),
                  errorText: _tried && _value <= 0
                      ? 'Escribe cuánto fue.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('¿Quién pagó?'),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  for (final m in g.members)
                    ChoiceChip(
                      label: Text(m.label),
                      selected: _paidBy == m.id,
                      onSelected: (_) => setState(() => _paidBy = m.id),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('¿Entre quiénes se reparte?'),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  for (final m in g.members)
                    FilterChip(
                      label: Text(m.label),
                      selected: who.contains(m.id),
                      onSelected: (on) => setState(() {
                        final next = {...who};
                        on ? next.add(m.id) : next.remove(m.id);
                        _participants = next;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                who.isEmpty
                    ? 'Elige al menos una persona.'
                    : each == 0
                    ? 'En partes iguales.'
                    : 'Le toca ${Cop.format(each)} a cada una.',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: AppSpace.xl),
              QButton(
                label: 'Guardar gasto',
                loading: _saving,
                loadingLabel: 'Guardando',
                onPressed: () => _save(g),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Crear un grupo: nombre, tipo y con quién.
class NewGroupPage extends ConsumerStatefulWidget {
  const NewGroupPage({super.key});

  @override
  ConsumerState<NewGroupPage> createState() => _NewGroupPageState();
}

class _NewGroupPageState extends ConsumerState<NewGroupPage> {
  final _name = TextEditingController();
  final _members = [TextEditingController()];
  GroupKind _kind = GroupKind.home;
  bool _tried = false;
  bool _saving = false;

  static const _maxMembers = 6;

  @override
  void dispose() {
    _name.dispose();
    for (final m in _members) {
      m.dispose();
    }
    super.dispose();
  }

  List<String> get _others => [
    for (final m in _members)
      if (m.text.trim().isNotEmpty) m.text.trim(),
  ];

  Future<void> _save() async {
    setState(() => _tried = true);
    if (_name.text.trim().length < 2 || _others.isEmpty) return;
    setState(() => _saving = true);
    try {
      final g = await ref
          .read(groupsRepositoryProvider)
          .createGroup(name: _name.text, kind: _kind, otherMembers: _others);
      if (!mounted) return;
      showQToast(context, 'Creamos el grupo ${g.name}');
      context.pushReplacement(Routes.group(g.id));
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos crearlo. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DiscardGuard(
      dirty:
          !_saving &&
          (_name.text.isNotEmpty || _members.any((m) => m.text.isNotEmpty)),
      title: '¿Descartar este grupo?',
      confirmLabel: 'Descartar grupo',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Crear grupo'),
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
                  labelText: 'Nombre del grupo',
                  hintText: 'Ej. Casa, viaje a Cartagena',
                  errorText: _tried && _name.text.trim().length < 2
                      ? 'Ponle un nombre al grupo.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('Tipo'),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  for (final k in GroupKind.values)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('¿Con quién?'),
              const SizedBox(height: AppSpace.xs),
              for (final (i, m) in _members.indexed) ...[
                TextField(
                  controller: m,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Persona ${i + 1}',
                    errorText: _tried && i == 0 && _others.isEmpty
                        ? 'Agrega al menos a una persona.'
                        : null,
                    suffixIcon: _members.length > 1
                        ? IconButton(
                            tooltip: 'Quitar persona ${i + 1}',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() {
                              _members.removeAt(i).dispose();
                            }),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
              ],
              if (_members.length < _maxMembers)
                QButton.secondary(
                  label: 'Agregar persona',
                  icon: Icons.person_add_alt_1_outlined,
                  onPressed: () =>
                      setState(() => _members.add(TextEditingController())),
                ),
              const SizedBox(height: AppSpace.md),
              const TrustNote(
                'Tú siempre estás en el grupo. Por ahora anotas tú los '
                'gastos de todos.',
              ),
              const SizedBox(height: AppSpace.xl),
              QButton(
                label: 'Crear grupo',
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
