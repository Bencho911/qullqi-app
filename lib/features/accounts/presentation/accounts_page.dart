import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/app/shell/tab_page.dart';
import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/scope/scope_provider.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/accounts/domain/account.dart';
import 'package:qullqi/features/investments/data/investments_repository.dart';
import 'package:qullqi/features/investments/domain/investment.dart';

/// Grupo de cuentas de un mismo tipo.
class _Group {
  const _Group(this.title, this.accounts, {this.isDebt = false});

  final String title;
  final List<Account> accounts;
  final bool isDebt;

  int get total =>
      accounts.fold(0, (s, a) => s + (isDebt ? a.debt : a.balance));
}

/// Texto de estado de la conexión: "Actualizada hace 5 min".
String syncLabel(Account a, DateTime now) {
  switch (a.status) {
    case ConnectionStatus.needsReconnect:
      return 'Reconecta para ver el saldo de hoy';
    case ConnectionStatus.manual:
      return 'Registrada a mano';
    case ConnectionStatus.connected:
      final m = now.difference(a.lastSync).inMinutes;
      if (m < 1) return 'Actualizada ahora';
      if (m < 60) return 'Actualizada hace $m min';
      final h = m ~/ 60;
      if (h < 24) return 'Actualizada hace $h h';
      return 'Actualizada el ${Dates.dayMonth(a.lastSync)}';
  }
}

SyncState syncState(Account a) => switch (a.status) {
  ConnectionStatus.needsReconnect => SyncState.reconnect,
  _ => SyncState.ok,
};

/// Alto aproximado del bloque destacado (para que la carga no salte).
const double _heroHeight = 168;

/// Cuentas: patrimonio, cuentas por tipo, tarjetas y cómo agregar más.
class AccountsPage extends ConsumerWidget {
  const AccountsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    // Las inversiones suman al patrimonio; si aún cargan, no frenan la lista.
    final investments = ref.watch(investmentsProvider).value ?? const [];
    final scope = ref.watch(scopeProvider);
    final now = ref.watch(clockProvider)();

    Future<void> refresh() async {
      await ref.read(accountsRepositoryProvider).sync();
      if (context.mounted) showQToast(context, 'Tus cuentas están al día');
    }

    return TabPage(
      title: 'Cuentas',
      onRefresh: accounts.hasValue ? refresh : null,
      slivers: switch (accounts) {
        AsyncData(:final value) => _content(
          context,
          value.where((a) => a.ownership.visibleIn(scope)).toList(),
          Portfolio.of(investments.where((i) => i.ownership.visibleIn(scope))),
          scope,
          now,
        ),
        AsyncError() => [
          GutterSliver(
            child: EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'No pudimos cargar tus cuentas',
              message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
              actionLabel: 'Reintentar',
              onAction: () => ref.invalidate(accountsProvider),
            ),
          ),
        ],
        _ => [
          GutterSliver(
            child: Semantics(
              label: 'Cargando tus cuentas',
              liveRegion: true,
              child: const Column(
                children: [
                  SkeletonBlock(height: _heroHeight, radius: AppRadius.card),
                  SizedBox(height: AppSpace.lg),
                  SkeletonBlock(height: AppSize.rowAmount),
                  SizedBox(height: AppSpace.xs),
                  SkeletonBlock(height: AppSize.rowAmount),
                  SizedBox(height: AppSpace.xs),
                  SkeletonBlock(height: AppSize.rowAmount),
                ],
              ),
            ),
          ),
        ],
      },
    );
  }

  List<Widget> _content(
    BuildContext context,
    List<Account> accounts,
    Portfolio portfolio,
    Scope scope,
    DateTime now,
  ) {
    if (accounts.isEmpty) {
      return [
        GutterSliver(
          child: EmptyState(
            icon: Icons.account_balance_rounded,
            title: scope == Scope.all
                ? 'Conecta tu primer banco'
                : 'No hay cuentas en esta vista',
            message: scope == Scope.all
                ? 'Verás todos tus saldos juntos, sin abrir cada app.'
                : 'Conecta una cuenta o cambia de vista arriba.',
            actionLabel: 'Conectar cuenta',
            onAction: () => context.push(Routes.connectAccount),
            secondaryLabel: 'Agregar cuenta a mano',
            onSecondary: () => context.push(Routes.manualAccount),
          ),
        ),
      ];
    }
    final groups = [
      _Group(
        'Cuentas de banco',
        accounts
            .where(
              (a) =>
                  a.kind == AccountKind.savings ||
                  a.kind == AccountKind.checking,
            )
            .toList(),
      ),
      _Group(
        'Billeteras y efectivo',
        accounts
            .where(
              (a) => a.kind == AccountKind.wallet || a.kind == AccountKind.cash,
            )
            .toList(),
      ),
      _Group(
        'Tarjetas de crédito',
        accounts.where((a) => a.isCard).toList(),
        isDebt: true,
      ),
    ].where((g) => g.accounts.isNotEmpty).toList();
    final netWorth =
        accounts.fold<int>(0, (s, a) => s + a.netValue) + portfolio.value;
    final liquid = accounts
        .where((a) => !a.isCard)
        .fold<int>(0, (s, a) => s + a.balance);
    final debt = accounts.fold<int>(0, (s, a) => s + a.debt);
    final showOwnership = scope == Scope.all;

    return [
      GutterSliver(
        child: HeroBalance(
          label: 'Patrimonio neto',
          value: netWorth,
          caption: portfolio.isEmpty
              ? 'Lo que tienes menos lo que debes en tarjetas'
              : 'Lo que tienes y lo que invertiste, menos lo que debes en '
                    'tarjetas',
          footer: Wrap(
            spacing: AppSpace.md,
            runSpacing: AppSpace.xxs,
            children: [
              _HeroFact('Tienes', liquid),
              if (!portfolio.isEmpty) _HeroFact('Invertido', portfolio.value),
              _HeroFact('Debes', debt),
            ],
          ),
        ),
      ),
      for (final g in groups) ...[
        const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
        GutterSliver(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(g.title),
              Semantics(
                label:
                    '${g.isDebt ? 'Deuda total' : 'Total'}: '
                    '${Cop.spoken(g.total)}',
                excludeSemantics: true,
                child: Text(
                  '${g.isDebt ? 'Deuda total' : 'Total'} '
                  '${Cop.format(g.total)}',
                  style: context.text.bodySmall,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              for (final a in g.accounts) ...[
                AccountTile(
                  initials: a.initials,
                  name: a.shortName,
                  detail: a.secondaryLine,
                  balance: a.isCard ? a.debt : a.balance,
                  balanceLabel: a.isCard ? 'Deuda' : null,
                  sync: syncState(a),
                  syncLabel: syncLabel(a, now),
                  // Misma regla que el resto: en Todo solo se marca lo
                  // del negocio.
                  ownership: showOwnership && a.ownership == Ownership.business
                      ? const StatusPill('Negocio', tone: PillTone.business)
                      : null,
                  onTap: () => context.push(Routes.account(a.id)),
                ),
                const SizedBox(height: AppSpace.xs),
              ],
            ],
          ),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
      GutterSliver(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader('Inversiones'),
            const SizedBox(height: AppSpace.xs),
            OptionRow(
              icon: Icons.trending_up_rounded,
              title: portfolio.isEmpty
                  ? 'Mira lo que tienes invertido'
                  : 'Tus inversiones',
              subtitle: portfolio.isEmpty
                  ? 'CDT, fondos, acciones o pensión voluntaria'
                  : '${Cop.format(portfolio.value)} · '
                        '${signedPercent(portfolio.returnRatio)} sobre lo '
                        'que pusiste',
              emphasized: portfolio.isEmpty,
              onTap: () => context.push(Routes.investments),
            ),
          ],
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xl)),
      GutterSliver(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader('Agregar una cuenta'),
            const SizedBox(height: AppSpace.xs),
            OptionRow(
              icon: Icons.link_rounded,
              title: 'Conectar cuenta',
              subtitle: 'Bancos y billeteras, con permiso de solo lectura',
              emphasized: true,
              onTap: () => context.push(Routes.connectAccount),
            ),
            const SizedBox(height: AppSpace.xs),
            OptionRow(
              icon: Icons.edit_outlined,
              title: 'Agregar cuenta a mano',
              subtitle: 'Efectivo, cooperativas o bancos sin conexión',
              onTap: () => context.push(Routes.manualAccount),
            ),
            const SizedBox(height: AppSpace.md),
            const TrustNote(
              'Nunca guardamos tus claves del banco. Puedes revocar el '
              'permiso de cada cuenta cuando quieras.',
            ),
          ],
        ),
      ),
    ];
  }
}

class _HeroFact extends StatelessWidget {
  const _HeroFact(this.label, this.value);

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: '$label: ${Cop.spoken(value)}',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label ',
            style: AppTypography.caption.copyWith(color: c.onHeroMuted),
          ),
          MoneyText(
            value,
            style: AppTypography.label.copyWith(color: c.onHero),
          ),
        ],
      ),
    );
  }
}
