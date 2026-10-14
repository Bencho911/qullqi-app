import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inti/core/money/money.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart';
import 'package:inti/features/accounts/domain/account.dart';

/// Abre la lista de cuentas para elegir una. Muestra saldo (o deuda).
Future<String?> pickAccount(
  BuildContext context, {
  required String title,
  required List<Account> accounts,
  String? selected,
}) {
  return pickFromSheet<String>(
    context,
    title: title,
    selected: selected,
    options: [
      for (final a in accounts)
        PickOption(
          value: a.id,
          title: a.shortName,
          subtitle: a.isCard ? 'Deuda' : a.detail,
          trailing: Cop.format(a.isCard ? a.debt : a.balance),
          leading: InitialsAvatar(a.initials),
        ),
    ],
  );
}

/// Campo que muestra la cuenta elegida y abre el selector al tocarlo.
class AccountField extends StatelessWidget {
  const AccountField({
    required this.label,
    required this.account,
    required this.onTap,
    super.key,
    this.error,
    this.warning,
  });

  /// "Desde", "Hacia", "Cuenta".
  final String label;
  final Account? account;
  final VoidCallback onTap;

  /// Problema que impide seguir (p. ej. saldo insuficiente al mover).
  final String? error;

  /// Aviso que no bloquea (p. ej. un gasto mayor que el saldo).
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = account;
    final value = a == null
        ? 'Elige una cuenta'
        : a.isCard
        ? '${a.shortName} · Deuda ${Cop.format(a.debt)}'
        : '${a.shortName} · ${Cop.format(a.balance)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QCard(
          onTap: onTap,
          semanticLabel:
              '$label: ${a == null ? 'sin elegir' : a.shortName}. Cambiar',
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm,
          ),
          child: ExcludeSemantics(
            child: Row(
              children: [
                if (a == null)
                  const IconTile(icon: Icons.account_balance_wallet_outlined)
                else
                  InitialsAvatar(a.initials),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: context.text.bodySmall),
                      Text(
                        value,
                        style: AppTypography.body.copyWith(
                          color: a == null ? c.inkMuted : c.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.unfold_more_rounded, color: c.inkSubtle),
              ],
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Text(
              error!,
              style: AppTypography.label.copyWith(color: c.onDangerContainer),
            ),
          )
        else if (warning != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xxs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: AppSize.iconSm,
                  color: c.warning,
                ),
                const SizedBox(width: AppSpace.xxs),
                Expanded(
                  child: Text(
                    warning!,
                    style: AppTypography.label.copyWith(color: c.warning),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Cuerpo de una pantalla que necesita las cuentas: muestra carga o error
/// mientras no estén, y el contenido cuando lleguen.
class AccountsGate extends ConsumerWidget {
  const AccountsGate({required this.builder, super.key});

  final Widget Function(List<Account> accounts) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    return switch (accounts) {
      AsyncValue(:final value?) => builder(value),
      AsyncError() => MessageBody(
        child: EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'No pudimos cargar tus cuentas',
          message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
          actionLabel: 'Reintentar',
          onAction: () => ref.invalidate(accountsProvider),
        ),
      ),
      _ => const PageSkeleton(label: 'Cargando tus cuentas', rows: 3),
    };
  }
}
