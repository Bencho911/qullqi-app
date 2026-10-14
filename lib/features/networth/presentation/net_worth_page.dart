import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';
import 'package:inti/core/money/money.dart';
import 'package:inti/core/scope/scope_provider.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart';
import 'package:inti/features/accounts/domain/account.dart';
import 'package:inti/features/investments/data/investments_repository.dart';
import 'package:inti/features/investments/domain/investment.dart';
import 'package:inti/features/networth/data/net_worth_provider.dart';
import 'package:inti/features/networth/domain/net_worth_history.dart';
import 'package:inti/features/networth/presentation/widgets/net_worth_chart.dart';

/// "+$1.234.000 (+5,8 %)" con signo y porcentaje.
String changePhrase(List<NetWorthPoint> points) {
  final change = changeOf(points);
  return '${Cop.format(change, signed: true)} '
      '(${signedPercent(changeRatio(points))})';
}

/// Patrimonio: cuánto vales hoy, cómo has crecido y de qué está hecho.
class NetWorthPage extends ConsumerStatefulWidget {
  const NetWorthPage({super.key});

  @override
  ConsumerState<NetWorthPage> createState() => _NetWorthPageState();
}

class _NetWorthPageState extends ConsumerState<NetWorthPage> {
  HistoryRange _range = HistoryRange.quarter;

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(netWorthHistoryProvider);
    final scope = ref.watch(scopeProvider);
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final investments =
        ref.watch(investmentsProvider).value ?? const <Investment>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Patrimonio')),
      body: switch (history) {
        AsyncData(:final value) => Builder(
          builder: (context) {
            final all = value.forScope(scope);
            final points = lastDays(all, _range.days);
            final change = changeOf(points);
            final mine = accounts.where((a) => a.ownership.visibleIn(scope));
            final liquid = mine
                .where((a) => !a.isCard)
                .fold<int>(0, (s, a) => s + a.balance);
            final debt = mine.fold<int>(0, (s, a) => s + a.debt);
            final invested = investments
                .where((i) => i.ownership.visibleIn(scope))
                .fold<int>(0, (s, i) => s + i.value);
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter,
                AppSpace.xs,
                AppSpace.gutter,
                AppSpace.xxl,
              ),
              children: [
                HeroBalance(
                  label: 'Tu patrimonio vale',
                  value: all.last.value,
                  caption:
                      'En ${_range.label.toLowerCase()}: '
                      '${changePhrase(points)}',
                ),
                const SizedBox(height: AppSpace.lg),
                Wrap(
                  spacing: AppSpace.xs,
                  runSpacing: AppSpace.xs,
                  children: [
                    for (final r in HistoryRange.values)
                      ChoiceChip(
                        label: Text(r.label),
                        selected: _range == r,
                        onSelected: (_) => setState(() => _range = r),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                QCard(child: NetWorthChart(points: points)),
                const SizedBox(height: AppSpace.xs),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    change >= 0
                        ? 'Subió ${Cop.format(change)} en '
                              '${_range.label.toLowerCase()}.'
                        : 'Bajó ${Cop.format(-change)} en '
                              '${_range.label.toLowerCase()}.',
                    style: context.text.bodySmall,
                  ),
                ),
                const SizedBox(height: AppSpace.xl),
                const SectionHeader('De qué está hecho'),
                const SizedBox(height: AppSpace.xs),
                QCard(
                  child: Column(
                    children: [
                      DetailLine('En tus cuentas', Cop.format(liquid)),
                      DetailLine('En inversiones', Cop.format(invested)),
                      DetailLine('Lo que debes en tarjetas', Cop.format(-debt)),
                      const Divider(),
                      DetailLine(
                        'Tu patrimonio',
                        Cop.format(liquid + invested - debt),
                        emphasis: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
                if (invested > 0)
                  OptionRow(
                    icon: Icons.trending_up_rounded,
                    title: 'Tus inversiones',
                    subtitle: 'Mira cuánto han crecido',
                    onTap: () => context.push(Routes.investments),
                  ),
                if (debt > 0) ...[
                  const SizedBox(height: AppSpace.xs),
                  OptionRow(
                    icon: Icons.credit_card_rounded,
                    title: 'Plan para pagar tus tarjetas',
                    subtitle: 'Cuánto tardas y cuánto te ahorras en intereses',
                    emphasized: true,
                    onTap: () => context.push(Routes.debtPlan),
                  ),
                ],
                const SizedBox(height: AppSpace.md),
                const TrustNote(
                  'Es la suma de tus cuentas y tus inversiones menos lo que '
                  'debes en tarjetas. Los días anteriores se arman con los '
                  'saldos que guardamos.',
                ),
              ],
            );
          },
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar tu patrimonio',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(accountsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando tu patrimonio'),
      },
    );
  }
}
