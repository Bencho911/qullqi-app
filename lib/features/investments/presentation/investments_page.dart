import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/scope/scope_provider.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/investments/data/investments_repository.dart';
import 'package:qullqi/features/investments/domain/investment.dart';
import 'package:qullqi/features/investments/presentation/widgets/investment_widgets.dart';

/// Días antes del vencimiento de un CDT en que lo destacamos arriba.
const int _maturityBannerDays = 30;

/// Inversiones: cuánto tienes invertido, cuánto ha crecido y dónde está.
class InvestmentsPage extends ConsumerWidget {
  const InvestmentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final investments = ref.watch(investmentsProvider);
    final scope = ref.watch(scopeProvider);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('Inversiones')),
      body: switch (investments) {
        AsyncData(:final value) => _Content(
          all: value,
          visible: value.where((i) => i.ownership.visibleIn(scope)).toList(),
          scope: scope,
          now: now,
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar tus inversiones',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(investmentsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando tus inversiones'),
      },
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({
    required this.all,
    required this.visible,
    required this.scope,
    required this.now,
  });

  final List<Investment> all;
  final List<Investment> visible;
  final Scope scope;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (visible.isEmpty) {
      final elsewhere = all.isNotEmpty;
      return MessageBody(
        child: EmptyState(
          icon: Icons.trending_up_rounded,
          title: elsewhere
              ? 'No hay inversiones en esta vista'
              : 'Aquí verás lo que tienes invertido',
          message: elsewhere
              ? 'Cambia de vista arriba o agrega una inversión.'
              : 'CDT, fondos, acciones o pensión voluntaria. Conéctalos o '
                    'regístralos a mano y mira cuánto han crecido.',
          actionLabel: 'Conectar entidad',
          onAction: () => context.push(Routes.connectInvestment),
          secondaryLabel: 'Agregar a mano',
          onSecondary: () => context.push(Routes.addInvestment),
        ),
      );
    }
    final p = Portfolio.of(visible);
    final showOwnership = scope == Scope.all;
    final soon =
        visible
            .where(
              (i) =>
                  i.daysToMaturity(now) != null &&
                  i.daysToMaturity(now)! >= 0 &&
                  i.daysToMaturity(now)! <= _maturityBannerDays,
            )
            .toList()
          ..sort((a, b) => a.maturity!.compareTo(b.maturity!));
    final next = soon.firstOrNull;

    Future<void> refresh() async {
      await ref.read(investmentsRepositoryProvider).sync();
      if (context.mounted) {
        showQToast(context, 'Tus inversiones están al día');
      }
    }

    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.xs,
          AppSpace.gutter,
          AppSpace.xxl,
        ),
        children: [
          HeroBalance(
            label: 'Tus inversiones valen',
            value: p.value,
            // Dos líneas: el porcentaje nunca queda partido de su cifra.
            caption:
                'Pusiste ${Cop.format(p.invested)}\n'
                '${gainPhrase(p.gain)} (${signedPercent(p.returnRatio)})',
          ),
          if (next != null) ...[
            const SizedBox(height: AppSpace.md),
            QBanner(
              tone: next.daysToMaturity(now)! <= 7
                  ? BannerTone.warning
                  : BannerTone.info,
              title: 'Se acerca el vencimiento de ${next.name}',
              message:
                  '${Dates.dueLabel(next.maturity!, now)}. Decide en tu '
                  'entidad si lo renuevas o lo retiras.',
              actionLabel: 'Ver detalle',
              onAction: () => context.push(Routes.investment(next.id)),
            ),
          ],
          const SizedBox(height: AppSpace.xl),
          const SectionHeader('Cómo está repartido'),
          const SizedBox(height: AppSpace.xxs),
          for (final s in p.byKind) KindShareRow(share: s),
          const SizedBox(height: AppSpace.xl),
          SectionHeader(
            'Tus inversiones',
            action: 'Agregar',
            actionSemantics: 'Agregar una inversión',
            onAction: () => context.push(Routes.addInvestment),
          ),
          const SizedBox(height: AppSpace.xs),
          for (final i in visible) ...[
            InvestmentTile(
              investment: i,
              now: now,
              showOwnership: showOwnership,
              onTap: () => context.push(Routes.investment(i.id)),
            ),
            const SizedBox(height: AppSpace.xs),
          ],
          const SizedBox(height: AppSpace.lg),
          const SectionHeader('Hacer crecer lo que tienes'),
          const SizedBox(height: AppSpace.xs),
          OptionRow(
            icon: Icons.calculate_outlined,
            title: 'Simular una inversión',
            subtitle: 'Mira cuánto podría crecer lo que aportas cada mes',
            emphasized: true,
            onTap: () => context.push(Routes.simulator),
          ),
          const SizedBox(height: AppSpace.xs),
          OptionRow(
            icon: Icons.link_rounded,
            title: 'Conectar entidad',
            subtitle: 'Bancos, comisionistas y fondos, solo lectura',
            onTap: () => context.push(Routes.connectInvestment),
          ),
          const SizedBox(height: AppSpace.xs),
          OptionRow(
            icon: Icons.edit_outlined,
            title: 'Agregar a mano',
            subtitle: 'Cripto, cooperativas o lo que no tenga conexión',
            onTap: () => context.push(Routes.addInvestment),
          ),
          const SizedBox(height: AppSpace.md),
          const TrustNote(
            'Qullqi solo te muestra lo que tienes: no compra ni vende '
            'inversiones. La rentabilidad pasada no garantiza la futura.',
          ),
        ],
      ),
    );
  }
}
