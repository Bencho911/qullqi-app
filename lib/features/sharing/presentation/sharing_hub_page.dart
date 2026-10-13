import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/sharing/data/sharing_repositories.dart';
import 'package:qullqi/features/sharing/domain/sharing.dart';

/// Compartir: grupos, cuentas divididas, deudas y metas con otras personas.
class SharingHubPage extends ConsumerWidget {
  const SharingHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(groupsProvider).value ?? const <SharedGroup>[];
    final expenses =
        ref.watch(sharedExpensesProvider).value ?? const <SharedExpense>[];
    final settlements =
        ref.watch(settlementsProvider).value ?? const <Settlement>[];
    final debts = ref.watch(personDebtsProvider).value ?? const <PersonDebt>[];
    final goals = ref.watch(sharedGoalsProvider).value ?? const <SharedGoal>[];

    final groupNet = groups.fold<int>(
      0,
      (s, g) => s + (balancesOf(g, expenses, settlements)[meId] ?? 0),
    );
    final totals = DebtTotals.of(debts);

    String net(int v, String zero) => v > 0
        ? 'Te deben ${Cop.format(v)}'
        : v < 0
        ? 'Debes ${Cop.format(-v)}'
        : zero;

    Widget option(
      IconData icon,
      String title,
      String subtitle,
      String route, {
      bool emphasized = false,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: OptionRow(
        icon: icon,
        title: title,
        subtitle: subtitle,
        emphasized: emphasized,
        onTap: () => context.push(route),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Compartir')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.xs,
            AppSpace.gutter,
            AppSpace.xxl,
          ),
          children: [
            const SectionHeader('Con tu gente'),
            const SizedBox(height: AppSpace.xs),
            option(
              Icons.groups_2_outlined,
              'Grupos',
              groups.isEmpty
                  ? 'La casa, un viaje o una salida'
                  : '${groups.length} '
                        '${groups.length == 1 ? 'grupo' : 'grupos'} · '
                        '${net(groupNet, 'a mano')}',
              Routes.groups,
              emphasized: true,
            ),
            option(
              Icons.call_split_rounded,
              'Dividir una cuenta',
              'Cuánto paga cada uno y quién te debe',
              Routes.splitBill,
            ),
            option(
              Icons.handshake_outlined,
              'Deudas entre personas',
              totals.owedToMe == 0 && totals.iOwe == 0
                  ? 'Lo que te deben y lo que debes'
                  : net(totals.net, 'a mano'),
              Routes.personDebts,
            ),
            option(
              Icons.volunteer_activism_outlined,
              'Metas compartidas',
              goals.isEmpty
                  ? 'Ahorrar entre varios'
                  : '${goals.length} '
                        '${goals.length == 1 ? 'meta' : 'metas'} · '
                        '${Cop.format(goals.fold(0, (s, g) => s + g.saved))} '
                        'ahorrados',
              Routes.sharedGoals,
            ),
          ],
        ),
      ),
    );
  }
}
