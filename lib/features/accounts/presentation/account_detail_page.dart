import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/security/confirm_identity.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/accounts/domain/account.dart';
import 'package:qullqi/features/accounts/presentation/accounts_page.dart';
import 'package:qullqi/features/move_money/presentation/move_money_page.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:qullqi/features/transactions/domain/transaction_filter.dart';
import 'package:qullqi/features/transactions/presentation/transaction_tile.dart';
import 'package:qullqi/features/transactions/presentation/transactions_controller.dart';

/// Movimientos recientes que se muestran en el detalle.
const int _recentShown = 5;

/// Detalle de una cuenta o tarjeta.
class AccountDetailPage extends ConsumerWidget {
  const AccountDetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final account = accounts.value?.where((a) => a.id == id).firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: Text(account?.isCard ?? false ? 'Tarjeta' : 'Cuenta'),
      ),
      body: switch (accounts) {
        AsyncValue(hasValue: true) when account != null => _Detail(a: account),
        AsyncValue(hasValue: true) => MessageBody(
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Esta cuenta ya no está en Qullqi',
            message: 'Puede que la hayas desconectado.',
            actionLabel: 'Ver mis cuentas',
            onAction: () => context.go(Routes.accounts),
          ),
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar la cuenta',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(accountsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando la cuenta'),
      },
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.a});

  final Account a;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final now = ref.watch(clockProvider)();
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final recent = (ref.watch(transactionsProvider).value ?? const [])
        .where((t) => t.accountId == a.id)
        .take(_recentShown)
        .toList();
    final repo = ref.read(accountsRepositoryProvider);

    Future<void> disconnect() async {
      final ok = await confirmDestructive(
        context,
        title: a.isManual
            ? '¿Quitar ${a.shortName}?'
            : '¿Desconectar ${a.shortName}?',
        message: a.isManual
            ? 'Se quita de Qullqi junto con su saldo. Tus movimientos ya '
                  'registrados se conservan.'
            : 'Revocamos el permiso con ${a.institution} y dejamos de ver '
                  'sus saldos. Puedes conectarla de nuevo cuando quieras.',
        confirmLabel: a.isManual
            ? 'Quitar ${a.shortName}'
            : 'Desconectar ${a.shortName}',
      );
      if (!ok || !context.mounted) return;
      try {
        await repo.remove(a.id);
        if (context.mounted) {
          showQToast(
            context,
            a.isManual
                ? 'Quitamos ${a.shortName}'
                : 'Desconectamos ${a.shortName}',
          );
          context.pop();
        }
      } on Object {
        if (context.mounted) {
          showQToast(context, 'No pudimos hacerlo. Inténtalo de nuevo.');
        }
      }
    }

    Future<void> togglePayments({required bool enable}) async {
      if (enable) {
        final ok = await confirmIdentity(
          context,
          reason:
              'Para autorizar mover plata desde ${a.shortName}. Siempre te '
              'pediremos confirmar cada movimiento.',
        );
        if (!ok) return;
      }
      try {
        await repo.setPaymentsEnabled(a.id, enabled: enable);
      } on Object {
        if (context.mounted) {
          showQToast(context, 'No pudimos cambiarlo. Inténtalo de nuevo.');
        }
        return;
      }
      if (context.mounted) {
        showQToast(
          context,
          enable
              ? 'Ya puedes mover plata desde ${a.shortName}'
              : 'Ya no se puede mover plata desde ${a.shortName}',
        );
      }
    }

    void seeAll() {
      ref
          .read(transactionFilterProvider.notifier)
          .set(TransactionFilter(range: DateRange.all, accountIds: {a.id}));
      context.go(Routes.transactions);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xxl,
      ),
      children: [
        Row(
          children: [
            InitialsAvatar(a.initials, size: AppSize.avatarLg),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(a.shortName, style: context.text.headlineSmall),
                  ),
                  Text(a.secondaryLine, style: context.text.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        if (a.status == ConnectionStatus.needsReconnect) ...[
          QBanner(
            title: '${a.institution} necesita reconectarse',
            message: 'Mientras tanto vemos el último saldo conocido.',
            actionLabel: 'Reconectar',
            onAction: () => context.push(Routes.reconnect(a.id)),
          ),
          const SizedBox(height: AppSpace.md),
        ],
        Semantics(
          label:
              '${a.isCard ? 'Deuda' : 'Saldo'}: '
              '${Cop.spoken(a.isCard ? a.debt : a.balance)}',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.isCard ? 'Deuda' : 'Saldo', style: context.text.bodySmall),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MoneyText(
                  a.isCard ? a.debt : a.balance,
                  currency: true,
                  style: AppTypography.display.copyWith(color: c.ink),
                ),
              ),
            ],
          ),
        ),
        Text(syncLabel(a, now), style: context.text.bodySmall),
        if (a.isCard) ...[
          const SizedBox(height: AppSpace.md),
          _CardSummary(a: a, now: now),
        ],
        const SizedBox(height: AppSpace.lg),
        if (a.isCard)
          QButton(
            label: 'Pagar tarjeta',
            icon: Icons.payments_outlined,
            onPressed: a.debt == 0
                ? null
                : () => context.push(
                    Routes.moveMoney,
                    extra: MovePreset(toId: a.id),
                  ),
          ),
        if (a.isCard && a.debt == 0)
          const Padding(
            padding: EdgeInsets.only(top: AppSpace.xs),
            child: SectionNote('No tienes deuda en esta tarjeta.'),
          )
        else if (!a.isManual && a.paymentsEnabled)
          QButton(
            label: 'Mover plata desde aquí',
            icon: Icons.swap_horiz_rounded,
            onPressed: () =>
                context.push(Routes.moveMoney, extra: MovePreset(fromId: a.id)),
          ),
        // Sin conexión, el extracto es la forma de traer su historial.
        if (a.isManual)
          QButton.secondary(
            label: 'Importar extracto',
            icon: Icons.upload_file_rounded,
            onPressed: () => context.push(Routes.importStatementTo(a.id)),
          ),
        if (!a.isCard && !a.isManual) ...[
          const SizedBox(height: AppSpace.md),
          QCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: SwitchRow(
              title: 'Mover plata desde esta cuenta',
              subtitle: a.status == ConnectionStatus.needsReconnect
                  ? 'Reconecta la cuenta para poder activarlo.'
                  : a.paymentsEnabled
                  ? 'Autorizado. Cada movimiento pide tu huella o PIN.'
                  : 'Desactivado. Solo vemos tus saldos y movimientos.',
              value: a.paymentsEnabled,
              // Con el permiso vencido primero hay que reconectar.
              onChanged: a.status == ConnectionStatus.needsReconnect
                  ? null
                  : (v) => togglePayments(enable: v),
            ),
          ),
        ],
        const SizedBox(height: AppSpace.xl),
        SectionHeader(
          'Últimos movimientos',
          action: recent.isEmpty ? null : 'Ver todos',
          actionSemantics: 'Ver todos los movimientos de ${a.shortName}',
          onAction: seeAll,
        ),
        if (recent.isEmpty)
          const SectionNote('Aún no hay movimientos en esta cuenta.')
        else
          for (final t in recent)
            TransactionTile(
              transaction: t,
              accounts: accounts,
              now: now,
              onTap: () => context.push(Routes.transaction(t.id)),
            ),
        const SizedBox(height: AppSpace.xl),
        QButton.text(
          label: a.isManual
              ? 'Quitar ${a.shortName}'
              : 'Desconectar ${a.shortName}',
          icon: a.isManual
              ? Icons.delete_outline_rounded
              : Icons.link_off_rounded,
          color: c.danger,
          onPressed: disconnect,
        ),
      ],
    );
  }
}

/// Cupo, pago del corte y fecha límite de una tarjeta.
class _CardSummary extends StatelessWidget {
  const _CardSummary({required this.a, required this.now});

  final Account a;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final limit = a.creditLimit ?? 0;
    final used = limit == 0 ? 0.0 : a.debt / limit;
    return QCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Usas ${Cop.percent(used * 100)} de tu cupo',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: AppSpace.xs),
          QProgressBar(
            value: used,
            semanticLabel: 'Cupo usado',
            tone: used >= 0.9
                ? ProgressTone.danger
                : used >= 0.7
                ? ProgressTone.warning
                : ProgressTone.ok,
          ),
          const SizedBox(height: AppSpace.sm),
          DetailLine('Cupo libre', Cop.format(a.availableCredit)),
          DetailLine('Cupo total', Cop.format(limit)),
          if (a.statementBalance != null)
            DetailLine('Pago del corte', Cop.format(a.statementBalance!)),
          if (a.minimumPayment != null)
            DetailLine('Pago mínimo', Cop.format(a.minimumPayment!)),
          if (a.paymentDue != null)
            DetailLine(
              'Fecha límite',
              '${Dates.dayMonth(a.paymentDue!)} · '
                  '${Dates.dueLabel(a.paymentDue!, now).toLowerCase()}',
            ),
        ],
      ),
    );
  }
}
