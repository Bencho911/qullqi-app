import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/app/shell/tab_page.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';
import 'package:qullqi/features/transactions/domain/transaction_filter.dart';
import 'package:qullqi/features/transactions/presentation/filter_sheet.dart';
import 'package:qullqi/features/transactions/presentation/transaction_tile.dart';
import 'package:qullqi/features/transactions/presentation/transactions_controller.dart';

/// Movimientos: búsqueda, filtros, resumen del período, traslados por
/// revisar y la lista agrupada por día.
class TransactionsPage extends ConsumerWidget {
  const TransactionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(transactionsViewProvider);

    Future<void> refresh() async {
      await ref.read(accountsRepositoryProvider).sync();
      if (context.mounted) showQToast(context, 'Tus cuentas están al día');
    }

    return TabPage(
      title: 'Movimientos',
      onRefresh: view.hasValue ? refresh : null,
      slivers: switch (view) {
        AsyncData(:final value) when value.isEmpty => [
          GutterSliver(
            child: EmptyState(
              icon: Icons.receipt_long_rounded,
              title: 'Aún no hay movimientos',
              message:
                  'Conecta un banco o registra tu primer gasto y lo verás '
                  'aquí, ordenado por día.',
              actionLabel: 'Conectar cuenta',
              onAction: () => context.push(Routes.connectAccount),
              secondaryLabel: 'Registrar gasto',
              onSecondary: () => context.push(Routes.addExpense),
            ),
          ),
        ],
        AsyncData(:final value) => _content(context, ref, value),
        AsyncError() => [
          GutterSliver(
            child: EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'No pudimos cargar tus movimientos',
              message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
              actionLabel: 'Reintentar',
              onAction: () => ref
                ..invalidate(transactionsProvider)
                ..invalidate(accountsProvider),
            ),
          ),
        ],
        _ => const [GutterSliver(child: _ListSkeleton())],
      },
    );
  }

  List<Widget> _content(
    BuildContext context,
    WidgetRef ref,
    TransactionsView v,
  ) {
    final c = context.colors;
    final f = v.filter;
    final notifier = ref.read(transactionFilterProvider.notifier);
    final showOwnership = v.scope == Scope.all;

    // Lista plana para construir solo lo visible: encabezado de día y luego
    // sus movimientos.
    final entries = <Object>[
      for (final g in v.groups) ...[g, ...g.items],
    ];

    return [
      GutterSliver(
        child: _SearchField(
          value: f.query,
          onChanged: (q) => notifier.set(f.copyWith(query: q)),
        ),
      ),
      SliverToBoxAdapter(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.sm,
            AppSpace.gutter,
            0,
          ),
          child: Row(
            children: [
              // Primero: siempre visible, aunque la fila no quepa.
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.xs),
                child: ActionChip(
                  // Con borde: abre una hoja, no filtra por sí solo.
                  side: BorderSide(color: c.outlineStrong),
                  avatar: const Icon(Icons.tune_rounded, size: AppSize.iconSm),
                  label: Text(
                    f.sheetCount == 0 ? 'Filtros' : 'Filtros (${f.sheetCount})',
                  ),
                  onPressed: () => showFilterSheet(context, ref, v),
                ),
              ),
              for (final k in <TransactionKind?>[
                null,
                ...TransactionKind.values,
              ])
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.xs),
                  child: ChoiceChip(
                    label: Text(k == null ? 'Todos' : _plural(k)),
                    selected: f.kind == k,
                    onSelected: (_) => notifier.set(f.copyWith(kind: () => k)),
                  ),
                ),
            ],
          ),
        ),
      ),
      GutterSliver(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpace.md),
            _PeriodSummary(view: v),
            if (v.toReview.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              QBanner(
                tone: BannerTone.info,
                title: v.toReview.length == 1
                    ? '1 traslado por revisar'
                    : '${v.toReview.length} traslados por revisar',
                message: 'Confírmalos para que no cuenten como gasto.',
                actionLabel: 'Revisar',
                onAction: () => context.push(Routes.reviewTransfers),
              ),
            ],
            const SizedBox(height: AppSpace.xs),
          ],
        ),
      ),
      if (entries.isEmpty)
        GutterSliver(
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No encontramos movimientos',
            message: 'Prueba con otra búsqueda o quita algún filtro.',
            actionLabel: 'Quitar filtros',
            onAction: notifier.reset,
          ),
        )
      else ...[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
          sliver: SliverList.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) => switch (entries[i]) {
              final DayGroup g => _DayHeader(group: g),
              final Transaction t => TransactionTile(
                transaction: t,
                accounts: v.accounts,
                now: v.now,
                showOwnership: showOwnership,
                showDay: false,
                onTap: () => context.push(Routes.transaction(t.id)),
              ),
              _ => const SizedBox.shrink(),
            },
          ),
        ),
        GutterSliver(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpace.md),
            child: Text(
              v.shown == 1 ? '1 movimiento' : '${v.shown} movimientos',
              textAlign: TextAlign.center,
              style: AppTypography.caption.copyWith(color: c.inkSubtle),
            ),
          ),
        ),
      ],
    ];
  }

  static String _plural(TransactionKind k) => switch (k) {
    TransactionKind.expense => 'Gastos',
    TransactionKind.income => 'Ingresos',
    TransactionKind.transfer => 'Traslados',
  };
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(_SearchField old) {
    super.didUpdateWidget(old);
    // "Limpiar filtros" vacía la búsqueda desde fuera.
    if (widget.value != _c.text) _c.text = widget.value;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      onChanged: widget.onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        labelText: 'Buscar movimientos',
        hintText: 'Comercio, categoría o cuenta',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Borrar búsqueda',
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _c.clear();
                  widget.onChanged('');
                },
              ),
      ),
    );
  }
}

/// Entradas y salidas del período filtrado (sin traslados).
class _PeriodSummary extends StatelessWidget {
  const _PeriodSummary({required this.view});

  final TransactionsView view;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = view.totals;
    Widget side(String label, int value, Color color, {bool signed = false}) {
      return Expanded(
        child: Semantics(
          label: '$label: ${Cop.spoken(value)}',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: context.text.bodySmall),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MoneyText(
                  value,
                  signed: signed,
                  style: AppTypography.subtitle.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return QCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${view.filter.range.label} · sin traslados',
            style: AppTypography.label.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: AppSpace.xs),
          Row(
            children: [
              side('Ingresos', t.income, c.income, signed: true),
              const SizedBox(width: AppSpace.md),
              side('Gastos', -t.expense, c.ink),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.group});

  final DayGroup group;

  @override
  Widget build(BuildContext context) {
    final n = group.items.length;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md, bottom: AppSpace.xxs),
      child: Semantics(
        header: true,
        label: '${group.label}, ${n == 1 ? '1 movimiento' : '$n movimientos'}',
        excludeSemantics: true,
        child: Text(
          group.label,
          style: AppTypography.label.copyWith(color: context.colors.inkMuted),
        ),
      ),
    );
  }
}

/// Forma de la lista mientras carga.
class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Cargando tus movimientos',
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBlock(height: AppSize.control),
          const SizedBox(height: AppSpace.md),
          const SkeletonBlock(height: _summaryHeight, radius: AppRadius.card),
          const SizedBox(height: AppSpace.lg),
          for (var i = 0; i < 5; i++) ...[
            const SkeletonBlock(height: AppSize.rowAmount),
            const SizedBox(height: AppSpace.xs),
          ],
        ],
      ),
    );
  }
}

/// Alto aproximado del resumen del período (para que la carga no salte).
const double _summaryHeight = 88;
