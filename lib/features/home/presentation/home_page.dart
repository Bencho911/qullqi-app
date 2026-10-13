import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/app/shell/tab_page.dart';
import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/accounts/presentation/widgets/account_card.dart';
import 'package:qullqi/features/business/presentation/business_pages.dart';
import 'package:qullqi/features/commitments/data/commitments_repository.dart';
import 'package:qullqi/features/home/domain/home_data.dart';
import 'package:qullqi/features/home/domain/money_summary.dart';
import 'package:qullqi/features/home/presentation/widgets/forecast_card.dart';
import 'package:qullqi/features/home/presentation/widgets/payment_row.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:qullqi/features/transactions/presentation/transaction_tile.dart';

/// Pagos que se muestran en el Inicio (el resto, en "Ver todos").
const int _paymentsShown = 3;

/// Inicio: cuánto puedes gastar de verdad, tus cuentas, lo que viene y lo
/// último que pasó. Todo según la vista activa.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final data = ref.watch(homeDataProvider);

    Future<void> refresh() async {
      await ref.read(accountsRepositoryProvider).sync();
      if (context.mounted) showQToast(context, 'Tus cuentas están al día');
    }

    return TabPage(
      // Inicio saluda en vez de repetir su nombre: la barra ya dice dónde
      // estás y el saludo hace la app más cercana.
      title: 'Hola, ${user.firstName}',
      onRefresh: data.hasValue ? refresh : null,
      slivers: switch (data) {
        AsyncData(:final value) when !value.hasAnyAccount => [
          GutterSliver(
            child: EmptyState(
              icon: Icons.account_balance_rounded,
              title: 'Conecta tu primer banco',
              message:
                  'Verás todo tu dinero en un solo lugar y cuánto puedes '
                  'gastar de verdad, sin abrir cada app.',
              actionLabel: 'Conectar cuenta',
              onAction: () => context.push(Routes.connectAccount),
              secondaryLabel: 'Registrar gasto',
              onSecondary: () => context.push(Routes.addExpense),
            ),
          ),
        ],
        AsyncData(:final value) => _content(
          context,
          value,
          hasBusiness: user.hasBusiness,
        ),
        AsyncError() => [
          GutterSliver(
            child: EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'No pudimos cargar tus cuentas',
              message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
              actionLabel: 'Reintentar',
              onAction: () => ref
                ..invalidate(accountsProvider)
                ..invalidate(commitmentsProvider)
                ..invalidate(transactionsProvider),
            ),
          ),
        ],
        _ => const [GutterSliver(child: _HomeSkeleton())],
      },
    );
  }

  List<Widget> _content(
    BuildContext context,
    HomeData d, {
    required bool hasBusiness,
  }) {
    final c = context.colors;
    final s = d.summary;
    final soon = s.payments
        .where(
          (p) => daysBetween(d.now, p.due) <= MoneySummary.horizonDaysDefault,
        )
        .toList();
    final showOwnership = d.scope == Scope.all;

    return [
      GutterSliver(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final a in d.needsReconnect) ...[
              QBanner(
                title: '${a.institution} necesita reconectarse',
                message: 'Mientras tanto vemos el último saldo conocido.',
                actionLabel: 'Reconectar',
                onAction: () => context.push(Routes.reconnect(a.id)),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            HeroBalance(
              label: 'Disponible para gastar',
              value: s.available,
              caption: s.available < 0
                  ? 'Tus pagos de los próximos 30 días superan lo que tienes'
                  : 'Ya descontamos lo que pagas en los próximos 30 días',
              onInfo: () => _explain(context, s),
              shares: showOwnership
                  ? [
                      BalanceShare(
                        'Personal',
                        d.byOwnership[Ownership.personal]!,
                        c.heroAccent,
                      ),
                      BalanceShare(
                        'Negocio',
                        d.byOwnership[Ownership.business]!,
                        c.business,
                      ),
                    ]
                  : const [],
            ),
          ],
        ),
      ),
      // El negocio: completo en su vista; en Todo, un acceso compacto.
      if (d.scope == Scope.business) ...[
        const SliverToBoxAdapter(child: SizedBox(height: AppSpace.md)),
        GutterSliver(
          child: BusinessSummaryCard(month: d.business, now: d.now),
        ),
      ] else if (d.scope == Scope.all && hasBusiness) ...[
        const SliverToBoxAdapter(child: SizedBox(height: AppSpace.md)),
        GutterSliver(
          child: BusinessTeaser(month: d.business, now: d.now),
        ),
      ],
      const _SectionGap(),
      GutterSliver(
        child: ForecastCard(
          forecast: d.forecast,
          onSeeBudgets: () => context.go(Routes.planning),
        ),
      ),
      const _SectionGap(),
      GutterSliver(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              'Tus cuentas',
              action: 'Ver todas',
              actionSemantics: 'Ver todas tus cuentas',
              onAction: () => context.go(Routes.accounts),
            ),
            // Con texto grande el valor baja de línea en vez de desbordarse.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Patrimonio neto ', style: context.text.bodySmall),
                MoneyText(
                  s.netWorth,
                  style: AppTypography.label.copyWith(color: c.inkMuted),
                ),
              ],
            ),
          ],
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
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final a in d.accounts) ...[
                  AccountCard(
                    account: a,
                    showOwnership: showOwnership,
                    onTap: () => context.push(Routes.account(a.id)),
                  ),
                  const SizedBox(width: AppSpace.xs),
                ],
                ConnectAccountCard(
                  onTap: () => context.push(Routes.connectAccount),
                ),
              ],
            ),
          ),
        ),
      ),
      const _SectionGap(),
      GutterSliver(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              'Próximos pagos',
              action: soon.length > _paymentsShown
                  ? 'Ver todos (${soon.length})'
                  : null,
              actionSemantics: 'Ver los ${soon.length} pagos próximos',
              onAction: () => _allPayments(context, soon, d.now),
            ),
            if (soon.isEmpty)
              const SectionNote('No tienes pagos en los próximos 30 días.')
            else
              for (final p in soon.take(_paymentsShown))
                PaymentRow(
                  payment: p,
                  now: d.now,
                  onTap: p.kind == PaymentKind.card
                      ? () => context.push(Routes.account(p.accountId!))
                      : null,
                ),
          ],
        ),
      ),
      const _SectionGap(),
      GutterSliver(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              'Últimos movimientos',
              action: 'Ver todos',
              actionSemantics: 'Ver todos tus movimientos',
              onAction: () => context.go(Routes.transactions),
            ),
            if (d.recent.isEmpty)
              const SectionNote('Aún no hay movimientos en esta vista.')
            else
              for (final t in d.recent)
                TransactionTile(
                  transaction: t,
                  accounts: d.accounts,
                  now: d.now,
                  showOwnership: showOwnership,
                  onTap: () => context.push(Routes.transaction(t.id)),
                ),
          ],
        ),
      ),
    ];
  }

  Future<void> _explain(BuildContext context, MoneySummary s) {
    return showQSheet<void>(
      context,
      title: 'Cómo calculamos tu disponible',
      builder: (context) {
        final c = context.colors;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Es lo que puedes gastar sin quedarte corto: lo que tienes en '
              'tus cuentas menos lo que ya debes pagar pronto (tarjetas, '
              'pagos fijos e impuestos). Las tarjetas no suman a tu dinero.',
              style: AppTypography.body.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: AppSpace.md),
            DetailLine('En tus cuentas', Cop.format(s.liquid)),
            DetailLine(
              'Pagos de los próximos 30 días',
              Cop.format(-s.committed),
            ),
            const Divider(),
            DetailLine(
              'Disponible para gastar',
              Cop.format(s.available),
              emphasis: true,
            ),
            const SizedBox(height: AppSpace.lg),
            // Solo cierra: botón secundario (el relleno es para acciones).
            QButton.secondary(
              label: 'Cerrar',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  Future<void> _allPayments(
    BuildContext context,
    List<UpcomingPayment> payments,
    DateTime now,
  ) {
    return showQSheet<void>(
      context,
      title: 'Próximos pagos',
      builder: (context) => Column(
        children: [
          for (final p in payments)
            PaymentRow(
              payment: p,
              now: now,
              onTap: p.kind == PaymentKind.card
                  ? () {
                      Navigator.of(context).pop();
                      unawaited(context.push(Routes.account(p.accountId!)));
                    }
                  : null,
            ),
        ],
      ),
    );
  }
}

class _SectionGap extends StatelessWidget {
  const _SectionGap();

  @override
  Widget build(BuildContext context) =>
      const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl));
}

// Medidas aproximadas de los bloques reales para que la carga no salte.
const double _heroHeight = 152;
const double _cardHeight = 140;
const double _headerWidth = 150;
const double _headerHeight = 20;

/// Forma del Inicio mientras carga: la misma estructura, sin números.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Cargando tu inicio',
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBlock(height: _heroHeight, radius: AppRadius.card),
          const SizedBox(height: AppSpace.xl),
          const SkeletonBlock(width: _headerWidth, height: _headerHeight),
          const SizedBox(height: AppSpace.sm),
          // Misma forma que el carrusel: tarjetas fijas y la siguiente asoma.
          SizedBox(
            height: _cardHeight,
            child: ListView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              children: const [
                SkeletonBlock(
                  width: accountCardWidth,
                  height: _cardHeight,
                  radius: AppRadius.card,
                ),
                SizedBox(width: AppSpace.xs),
                SkeletonBlock(
                  width: accountCardWidth,
                  height: _cardHeight,
                  radius: AppRadius.card,
                ),
                SizedBox(width: AppSpace.xs),
                SkeletonBlock(
                  width: accountCardWidth,
                  height: _cardHeight,
                  radius: AppRadius.card,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          const SkeletonBlock(width: _headerWidth, height: _headerHeight),
          const SizedBox(height: AppSpace.sm),
          const SkeletonBlock(height: AppSize.rowAmount),
          const SizedBox(height: AppSpace.xs),
          const SkeletonBlock(height: AppSize.rowAmount),
        ],
      ),
    );
  }
}
