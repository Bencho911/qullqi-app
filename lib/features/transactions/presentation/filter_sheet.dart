import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';
import 'package:qullqi/features/transactions/domain/transaction_filter.dart';
import 'package:qullqi/features/transactions/presentation/transactions_controller.dart';

/// Hoja de filtros. Trabaja sobre un borrador: nada cambia en la lista hasta
/// tocar "Ver resultados".
Future<void> showFilterSheet(
  BuildContext context,
  WidgetRef ref,
  TransactionsView view,
) async {
  final result = await showQSheet<TransactionFilter>(
    context,
    title: 'Filtros',
    builder: (context) => _FilterBody(view: view),
  );
  if (result != null) ref.read(transactionFilterProvider.notifier).set(result);
}

class _FilterBody extends StatefulWidget {
  const _FilterBody({required this.view});

  final TransactionsView view;

  @override
  State<_FilterBody> createState() => _FilterBodyState();
}

class _FilterBodyState extends State<_FilterBody> {
  late TransactionFilter _draft = widget.view.filter;

  Set<String> _toggle(Set<String> s, String id) =>
      s.contains(id) ? ({...s}..remove(id)) : {...s, id};

  @override
  Widget build(BuildContext context) {
    final accounts = widget.view.accounts
        .where((a) => a.ownership.visibleIn(widget.view.scope))
        .toList();

    Widget section(String title, List<Widget> chips) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title),
          const SizedBox(height: AppSpace.xs),
          Wrap(spacing: AppSpace.xs, runSpacing: AppSpace.xs, children: chips),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        section('Período', [
          for (final r in DateRange.values)
            ChoiceChip(
              label: Text(r.label),
              selected: _draft.range == r,
              onSelected: (_) =>
                  setState(() => _draft = _draft.copyWith(range: r)),
            ),
        ]),
        section('Cuentas', [
          for (final a in accounts)
            FilterChip(
              // Selección múltiple: la marca de verificación no depende solo
              // del color.
              showCheckmark: true,
              label: Text(a.shortName),
              selected: _draft.accountIds.contains(a.id),
              onSelected: (_) => setState(
                () => _draft = _draft.copyWith(
                  accountIds: _toggle(_draft.accountIds, a.id),
                ),
              ),
            ),
        ]),
        section('Categorías', [
          for (final cat in Categories.pickable)
            FilterChip(
              showCheckmark: true,
              avatar: Icon(cat.icon, size: AppSize.iconSm),
              label: Text(cat.name),
              selected: _draft.categoryIds.contains(cat.id),
              onSelected: (_) => setState(
                () => _draft = _draft.copyWith(
                  categoryIds: _toggle(_draft.categoryIds, cat.id),
                ),
              ),
            ),
        ]),
        QButton(
          label: 'Ver resultados',
          onPressed: () => Navigator.of(context).pop(_draft),
        ),
        const SizedBox(height: AppSpace.xs),
        // Mismo efecto que "Quitar filtros" de la lista: vuelve a empezar.
        QButton.secondary(
          label: 'Quitar filtros',
          onPressed: () => Navigator.of(context).pop(const TransactionFilter()),
        ),
      ],
    );
  }
}
