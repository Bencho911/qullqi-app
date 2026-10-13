import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/business/data/business_back_office.dart';
import 'package:qullqi/features/business/data/invoices_repository.dart';
import 'package:qullqi/features/business/domain/reconcile.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';

/// Conciliar: cruza cada factura abierta con el depósito que parece pagarla,
/// para no cobrar dos veces ni dejar facturas "por cobrar" que ya llegaron.
class ReconcilePage extends ConsumerWidget {
  const ReconcilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(reconcileSuggestionsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Conciliar cobros')),
      body: switch (suggestions) {
        AsyncData(:final value) when value.isEmpty => MessageBody(
          child: EmptyState(
            icon: Icons.verified_rounded,
            title: 'Todo cuadra',
            message:
                'No vemos depósitos que parezcan pagar tus facturas abiertas. '
                'Si llega uno, te avisamos aquí.',
            actionLabel: 'Ver facturas por cobrar',
            onAction: () => context.pushReplacement(Routes.invoices),
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
            Text(
              value.length == 1
                  ? 'Parece que ya te pagaron una factura.'
                  : 'Parece que ya te pagaron ${value.length} facturas.',
              style: context.text.bodyMedium,
            ),
            const SizedBox(height: AppSpace.md),
            for (final s in value) ...[
              _SuggestionCard(suggestion: s),
              const SizedBox(height: AppSpace.sm),
            ],
            const TrustNote(
              'Al confirmar, la factura queda pagada con ese depósito: no se '
              'crea un ingreso nuevo ni se suma dos veces.',
            ),
          ],
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos revisar tus cobros',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref
              ..invalidate(invoicesProvider)
              ..invalidate(transactionsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Revisando tus cobros'),
      },
    );
  }
}

class _SuggestionCard extends ConsumerStatefulWidget {
  const _SuggestionCard({required this.suggestion});

  final ReconcileSuggestion suggestion;

  @override
  ConsumerState<_SuggestionCard> createState() => _SuggestionCardState();
}

class _SuggestionCardState extends ConsumerState<_SuggestionCard> {
  bool _saving = false;

  Future<void> _confirm() async {
    final s = widget.suggestion;
    setState(() => _saving = true);
    try {
      await ref.read(invoicesRepositoryProvider).markPaid(s.invoice.id);
      await ref
          .read(transactionsRepositoryProvider)
          .update(s.deposit.copyWith(note: 'Factura ${s.invoice.number}'));
      if (!mounted) return;
      showQToast(context, 'Conciliamos ${s.invoice.number}');
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos conciliarla. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.suggestion;
    final now = ref.watch(clockProvider)();
    return QCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: StatusPill(
              s.confidence.label,
              tone: s.confidence == MatchConfidence.exact
                  ? PillTone.primary
                  : PillTone.warning,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            '${s.invoice.number} · ${s.invoice.client}',
            style: context.text.titleSmall,
          ),
          DetailLine('Te debían', Cop.format(s.invoice.total)),
          const Divider(),
          Text('Depósito', style: context.text.bodySmall),
          DetailLine(s.deposit.title, Cop.format(s.deposit.amount)),
          Text(
            Dates.relativeDay(s.deposit.date, now),
            style: context.text.bodySmall,
          ),
          const SizedBox(height: AppSpace.md),
          QButton(
            label: 'Sí, es este pago',
            icon: Icons.check_rounded,
            loading: _saving,
            loadingLabel: 'Conciliando',
            onPressed: _confirm,
          ),
          const SizedBox(height: AppSpace.xs),
          QButton.secondary(
            label: 'No es este pago',
            onPressed: _saving
                ? null
                : () => ref
                      .read(dismissedReconcileProvider.notifier)
                      .dismiss(s.id),
          ),
        ],
      ),
    );
  }
}
