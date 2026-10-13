import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/security/confirm_identity.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/business/data/business_back_office.dart';
import 'package:qullqi/features/business/data/invoices_repository.dart';
import 'package:qullqi/features/investments/data/investments_repository.dart';
import 'package:qullqi/features/planning/data/plans_repository.dart';
import 'package:qullqi/features/privacy/domain/data_export.dart';
import 'package:qullqi/features/profile/presentation/account_actions.dart';
import 'package:qullqi/features/rules/data/rules_provider.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';

/// Etiqueta legible de cada sección de la copia.
const _labels = {
  'cuentas': 'Cuentas',
  'movimientos': 'Movimientos',
  'presupuestos': 'Presupuestos',
  'metas': 'Metas',
  'reglas': 'Reglas de categorías',
  'inversiones': 'Inversiones',
  'facturas': 'Facturas',
  'cuentas_por_pagar': 'Cuentas por pagar',
};

/// Mis datos: qué guardamos, cómo llevártelos y cómo borrarlos.
class MyDataPage extends ConsumerWidget {
  const MyDataPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final now = ref.watch(clockProvider)();
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final txs = ref.watch(transactionsProvider).value ?? const [];
    final export = buildDataExport(
      user: user,
      now: now,
      accounts: accounts,
      transactions: txs,
      budgets: ref.watch(budgetsProvider).value ?? const [],
      goals: ref.watch(goalsProvider).value ?? const [],
      rules: ref.watch(categoryRulesProvider),
      investments: ref.watch(investmentsProvider).value ?? const [],
      invoices: user.hasBusiness
          ? ref.watch(invoicesProvider).value ?? const []
          : const [],
      bills: user.hasBusiness
          ? ref.watch(billsProvider).value ?? const []
          : const [],
    );

    Future<void> copy(String text, String done) async {
      final ok = await confirmIdentity(
        context,
        reason: 'Para llevarte una copia de tus datos.',
      );
      if (!ok || !context.mounted) return;
      // Copiar no debe frenar nada: se hace sin esperar.
      unawaited(Clipboard.setData(ClipboardData(text: text)));
      showQToast(context, done);
    }

    String accountName(String id) =>
        accounts.where((a) => a.id == id).firstOrNull?.shortName ?? id;

    return Scaffold(
      appBar: AppBar(title: const Text('Mis datos')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.xs,
            AppSpace.gutter,
            AppSpace.xxl,
          ),
          children: [
            Text(
              'Son tuyos. Aquí ves qué guardamos, te llevas una copia o los '
              'borras.',
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.inkMuted,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            const SectionHeader('Qué guardamos de ti'),
            const SizedBox(height: AppSpace.xs),
            QCard(
              child: Column(
                children: [
                  DetailLine('Tu nombre y contacto', user.email),
                  for (final e in export.counts.entries)
                    DetailLine(_labels[e.key] ?? e.key, '${e.value}'),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            const Text(
              'Nunca guardamos las claves de tus bancos ni tu PIN en '
              'nuestros servidores.',
            ),
            const SizedBox(height: AppSpace.xl),
            const SectionHeader('Llévate una copia'),
            const SizedBox(height: AppSpace.xs),
            QButton(
              label: 'Copiar todo (JSON)',
              icon: Icons.data_object_rounded,
              onPressed: () => copy(
                export.json,
                'Copiamos tus datos (${export.total} registros)',
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            QButton.secondary(
              label: 'Copiar movimientos (CSV)',
              icon: Icons.table_chart_outlined,
              onPressed: txs.isEmpty
                  ? null
                  : () => copy(
                      transactionsCsv(txs, accountName),
                      'Copiamos tus ${txs.length} movimientos',
                    ),
            ),
            const SizedBox(height: AppSpace.sm),
            const TrustNote(
              'La copia incluye información financiera tuya. Pégala solo en '
              'un lugar que sea seguro.',
            ),
            const SizedBox(height: AppSpace.xl),
            const SectionHeader('Tu cuenta'),
            const SizedBox(height: AppSpace.xs),
            QButton.text(
              label: 'Eliminar mi cuenta',
              icon: Icons.delete_outline_rounded,
              color: context.colors.danger,
              onPressed: () => deleteAccountFlow(context, ref),
            ),
          ],
        ),
      ),
    );
  }
}
