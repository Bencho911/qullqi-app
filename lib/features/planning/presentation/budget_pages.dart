import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';
import 'package:inti/core/money/money.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/core/session/session.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart';
import 'package:inti/features/planning/data/plans_repository.dart';
import 'package:inti/features/planning/domain/plans.dart';
import 'package:inti/features/planning/presentation/planning_controller.dart';
import 'package:inti/features/planning/presentation/widgets/plan_cards.dart';
import 'package:inti/features/transactions/domain/transaction.dart';
import 'package:inti/features/transactions/presentation/transaction_tile.dart';

/// Detalle de un presupuesto: cómo vas, cuánto por día y en qué gastaste.
class BudgetDetailPage extends ConsumerWidget {
  const BudgetDetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(planningViewProvider);
    // Se busca entre todos (no solo la vista activa) para no "perderlo".
    final budgets = ref.watch(budgetsProvider).value;
    final budget = budgets?.where((b) => b.id == id).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Presupuesto')),
      body: switch (view) {
        AsyncData(:final value) when budget != null => _Detail(
          p: progressOf(budget, value.transactions, value.now),
          view: value,
        ),
        AsyncData() => MessageBody(
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Este presupuesto ya no existe',
            message: 'Puede que lo hayas eliminado.',
            actionLabel: 'Ver mis planes',
            onAction: () => context.go(Routes.planning),
          ),
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar el presupuesto',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(budgetsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando el presupuesto'),
      },
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.p, required this.view});

  final BudgetProgress p;
  final PlanningView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final cat = p.budget.category;
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final spentHere =
        view.transactions
            .where(
              (t) =>
                  t.kind == TransactionKind.expense &&
                  t.categoryId == p.budget.categoryId &&
                  t.ownership == p.budget.ownership &&
                  t.date.year == view.now.year &&
                  t.date.month == view.now.month,
            )
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));

    Future<void> delete() async {
      final ok = await confirmDestructive(
        context,
        title: '¿Eliminar el presupuesto de ${cat.name}?',
        message: 'Tus gastos siguen igual; solo dejamos de vigilar el tope.',
        confirmLabel: 'Eliminar presupuesto de ${cat.name}',
      );
      if (!ok || !context.mounted) return;
      try {
        await ref.read(plansRepositoryProvider).deleteBudget(p.budget.id);
        if (context.mounted) {
          showQToast(context, 'Eliminamos el presupuesto de ${cat.name}');
          context.pop();
        }
      } on Object {
        if (context.mounted) {
          showQToast(context, 'No pudimos eliminarlo. Inténtalo de nuevo.');
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
        Row(
          children: [
            IconTile(icon: cat.icon, size: AppSize.avatarLg),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(cat.name, style: context.text.headlineSmall),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        Semantics(
          label:
              'Gastaste ${Cop.spoken(p.spent)} de '
              '${Cop.spoken(p.budget.limit)}',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Gastaste este mes', style: context.text.bodySmall),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: MoneyText(
                  p.spent,
                  currency: true,
                  style: AppTypography.display.copyWith(color: c.ink),
                ),
              ),
              Text(
                'de ${Cop.format(p.budget.limit)}',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        QProgressBar(
          value: p.ratio,
          tone: toneOf(p.status),
          semanticLabel: cat.name,
        ),
        const SizedBox(height: AppSpace.md),
        QCard(
          child: Column(
            children: [
              DetailLine(
                p.left >= 0 ? 'Te queda' : 'Te pasaste',
                Cop.format(p.left.abs()),
              ),
              DetailLine(
                'Puedes gastar por día',
                p.perDay > 0 ? Cop.format(p.perDay) : 'Nada más este mes',
              ),
              DetailLine('Días que quedan', '${p.daysLeft}'),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        QButton.secondary(
          label: 'Cambiar el tope',
          icon: Icons.edit_outlined,
          onPressed: () => context.push(Routes.editBudget(p.budget.id)),
        ),
        const SizedBox(height: AppSpace.xl),
        const SectionHeader('Gastos de este mes'),
        if (spentHere.isEmpty)
          const SectionNote('Aún no gastas en esta categoría este mes.')
        else
          for (final t in spentHere)
            TransactionTile(
              transaction: t,
              accounts: accounts,
              now: view.now,
              onTap: () => context.push(Routes.transaction(t.id)),
            ),
        const SizedBox(height: AppSpace.xl),
        QButton.text(
          label: 'Eliminar presupuesto',
          icon: Icons.delete_outline_rounded,
          color: c.danger,
          onPressed: delete,
        ),
      ],
    );
  }
}

/// Crear o cambiar un presupuesto: categoría y tope del mes.
class BudgetEditorPage extends ConsumerStatefulWidget {
  const BudgetEditorPage({super.key, this.editId});

  /// Si viene, se cambia el tope de ese presupuesto.
  final String? editId;

  @override
  ConsumerState<BudgetEditorPage> createState() => _BudgetEditorPageState();
}

class _BudgetEditorPageState extends ConsumerState<BudgetEditorPage> {
  String? _categoryId;
  String _digits = '';
  Ownership _ownership = Ownership.personal;
  bool _tried = false;
  bool _saving = false;
  bool _loaded = false;

  int get _amount => AmountInput.value(_digits);

  Future<void> _save(Budget? editing) async {
    setState(() => _tried = true);
    if (_categoryId == null || _amount <= 0) return;
    setState(() => _saving = true);
    try {
      final b = await ref
          .read(plansRepositoryProvider)
          .saveBudget(
            id: editing?.id,
            categoryId: _categoryId!,
            limit: _amount,
            ownership: editing?.ownership ?? _ownership,
          );
      if (!mounted) return;
      showQToast(
        context,
        '${b.category.name}: tope de ${Cop.format(b.limit)} al mes',
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
    final budgets = ref.watch(budgetsProvider).value ?? const <Budget>[];
    final hasBusiness = ref.watch(currentUserProvider).hasBusiness;
    final editing = budgets.where((b) => b.id == widget.editId).firstOrNull;
    if (editing != null && !_loaded) {
      _loaded = true;
      _categoryId = editing.categoryId;
      _digits = '${editing.limit}';
    }
    // Al crear no se repite una categoría que ya tiene presupuesto.
    final taken = budgets
        .where((b) => b.ownership == _ownership && b.id != editing?.id)
        .map((b) => b.categoryId)
        .toSet();
    final choices = Categories.pickable
        .where((c) => !taken.contains(c.id))
        .toList();
    final error = _tried && _categoryId == null
        ? 'Elige una categoría.'
        : _tried && _amount <= 0
        ? 'Escribe el tope del mes.'
        : null;

    return DiscardGuard(
      dirty:
          !_saving &&
          (editing == null
              ? _amount > 0 || _categoryId != null
              : _digits != '${editing.limit}' ||
                    _categoryId != editing.categoryId),
      title: editing == null
          ? '¿Descartar este presupuesto?'
          : '¿Descartar el cambio del tope?',
      confirmLabel: editing == null
          ? 'Descartar presupuesto'
          : 'Descartar cambio',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: Text(
            editing == null ? 'Crear presupuesto' : 'Cambiar el tope',
          ),
        ),
        body: SafeArea(
          child: KeypadLayout(
            fields: [
              AmountDisplay(
                digits: _digits,
                label: '¿Cuánto quieres gastar al mes?',
                error: error,
              ),
              const SizedBox(height: AppSpace.sm),
              if (editing == null) ...[
                if (hasBusiness) ...[
                  const SectionHeader('¿De quién es?'),
                  const SizedBox(height: AppSpace.xs),
                  SegmentedButton<Ownership>(
                    showSelectedIcon: false,
                    segments: [
                      for (final o in Ownership.values)
                        ButtonSegment(value: o, label: Text(o.label)),
                    ],
                    selected: {_ownership},
                    onSelectionChanged: (s) => setState(() {
                      _ownership = s.first;
                      _categoryId = null;
                    }),
                  ),
                  const SizedBox(height: AppSpace.md),
                ],
                const SectionHeader('Categoría'),
                const SizedBox(height: AppSpace.xs),
                Wrap(
                  spacing: AppSpace.xs,
                  runSpacing: AppSpace.xs,
                  children: [
                    for (final cat in choices)
                      ChoiceChip(
                        avatar: Icon(cat.icon, size: AppSize.iconSm),
                        label: Text(cat.name),
                        selected: _categoryId == cat.id,
                        onSelected: (_) => setState(() => _categoryId = cat.id),
                      ),
                  ],
                ),
              ] else
                SettingsRow(
                  icon: editing.category.icon,
                  title: editing.category.name,
                  subtitle: 'Categoría',
                ),
            ],
            keypad: AmountKeypad(
              digits: _digits,
              onChanged: (d) => setState(() => _digits = d),
            ),
            action: QButton(
              label: editing == null ? 'Crear presupuesto' : 'Guardar tope',
              loading: _saving,
              loadingLabel: 'Guardando',
              onPressed: () => _save(editing),
            ),
          ),
        ),
      ),
    );
  }
}
