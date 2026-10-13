import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/scope/scope_provider.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/recurring/data/recurring_provider.dart';
import 'package:qullqi/features/recurring/domain/recurring.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';

/// "Se cobra el 28 de octubre", "Se cobra mañana".
String nextChargeLabel(RecurringCharge c, DateTime now) {
  final days = daysBetween(now, c.nextDate);
  if (days < 0) {
    final n = -days;
    return 'Debía llegar hace $n ${n == 1 ? 'día' : 'días'}';
  }
  if (days == 0) return 'Se cobra hoy';
  if (days == 1) return 'Se cobra mañana';
  return 'Se cobra el ${Dates.dayMonth(c.nextDate)}';
}

/// Pagos recurrentes: lo que se repite cada mes y cuánto suma.
class RecurringPage extends ConsumerWidget {
  const RecurringPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recurring = ref.watch(recurringProvider);
    final scope = ref.watch(scopeProvider);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('Pagos recurrentes')),
      body: switch (recurring) {
        AsyncData(:final value) => _Content(
          charges: value.where((c) => c.ownership.visibleIn(scope)).toList(),
          scope: scope,
          now: now,
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar tus pagos',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(transactionsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando tus pagos recurrentes'),
      },
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({
    required this.charges,
    required this.scope,
    required this.now,
  });

  final List<RecurringCharge> charges;
  final Scope scope;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    if (charges.isEmpty) {
      return MessageBody(
        child: EmptyState(
          icon: Icons.autorenew_rounded,
          title: 'Aún no vemos cobros que se repitan',
          message:
              'Cuando un cobro llegue dos meses seguidos lo mostramos aquí y '
              'te avisamos si sube de precio.',
          actionLabel: 'Ver movimientos',
          onAction: () => context.go(Routes.transactions),
        ),
      );
    }
    final total = monthlyTotal(charges);
    final raised = charges.where((c) => c.priceUp).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xxl,
      ),
      children: [
        HeroBalance(
          label: 'Pagas cada mes',
          value: total,
          caption: charges.length == 1
              ? '1 cobro que se repite'
              : '${charges.length} cobros que se repiten',
        ),
        if (raised > 0) ...[
          const SizedBox(height: AppSpace.md),
          QBanner(
            tone: BannerTone.info,
            title: raised == 1
                ? 'Un cobro subió de precio'
                : '$raised cobros subieron de precio',
            message: 'Míralos abajo: cancela o cambia de plan si no lo vale.',
          ),
        ],
        const SizedBox(height: AppSpace.xl),
        const SectionHeader('Tus cobros'),
        const SizedBox(height: AppSpace.xs),
        for (final c in charges) ...[
          _RecurringTile(
            charge: c,
            now: now,
            showOwnership: scope == Scope.all,
            onTap: () => _history(context, c),
          ),
          const SizedBox(height: AppSpace.xs),
        ],
        const SizedBox(height: AppSpace.md),
        const TrustNote(
          'Los detectamos en tus movimientos: el mismo comercio, cada mes. '
          'Si uno no es tuyo o ya lo cancelaste, deja de aparecer solo.',
        ),
      ],
    );
  }

  Future<void> _history(BuildContext context, RecurringCharge c) {
    return showQSheet<void>(
      context,
      title: c.title,
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            nextChargeLabel(c, now),
            style: AppTypography.body.copyWith(color: context.colors.inkMuted),
          ),
          const SizedBox(height: AppSpace.sm),
          for (final t in c.history.take(6))
            DetailLine(Dates.dayMonth(t.date), Cop.format(t.amount)),
          const SizedBox(height: AppSpace.lg),
          QButton(
            label: 'Ver el último movimiento',
            onPressed: () {
              Navigator.of(context).pop();
              unawaited(context.push(Routes.transaction(c.history.first.id)));
            },
          ),
          const SizedBox(height: AppSpace.xs),
          QButton.secondary(
            label: 'Cerrar',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _RecurringTile extends StatelessWidget {
  const _RecurringTile({
    required this.charge,
    required this.now,
    required this.showOwnership,
    required this.onTap,
  });

  final RecurringCharge charge;
  final DateTime now;
  final bool showOwnership;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final r = charge;
    final spoken = [
      r.title,
      'Cada mes',
      Cop.spoken(r.amount),
      nextChargeLabel(r, now),
      if (r.priceUp) 'Subió ${Cop.spoken(r.change!)}',
      if (showOwnership && r.ownership == Ownership.business) 'Negocio',
    ].join('. ');
    return QCard(
      onTap: onTap,
      semanticLabel: spoken,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: ExcludeSemantics(
        child: AmountRowLayout(
          leading: IconTile(icon: r.category.icon),
          title: r.title,
          titleLines: 2,
          details: [
            Text(
              'Cada mes · ${nextChargeLabel(r, now).toLowerCase()}',
              style: AppTypography.caption.copyWith(color: c.inkSubtle),
            ),
            if (r.priceUp) ...[
              const SizedBox(height: AppSpace.xxs),
              StatusPill(
                'Subió ${Cop.format(r.change!)}',
                tone: PillTone.warning,
              ),
            ],
            if (showOwnership && r.ownership == Ownership.business) ...[
              const SizedBox(height: AppSpace.xxs),
              const StatusPill('Negocio', tone: PillTone.business),
            ],
          ],
          trailing: MoneyText(
            r.amount,
            animate: false,
            style: AppTypography.subtitle.copyWith(
              color: c.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
