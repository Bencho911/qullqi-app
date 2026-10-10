import 'package:flutter/material.dart';

import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/domain/account.dart';

/// Ancho de una cuenta en el carrusel del Inicio.
const double accountCardWidth = 168;

/// El ancho crece con el texto del sistema (hasta 160 %) para que el nombre
/// del banco no se corte.
double accountCardWidthFor(BuildContext context) =>
    accountCardWidth *
    (MediaQuery.textScalerOf(context).scale(10) / 10).clamp(1.0, 1.6);

/// Cuenta compacta para el carrusel del Inicio.
class AccountCard extends StatelessWidget {
  const AccountCard({
    required this.account,
    required this.onTap,
    super.key,
    this.showOwnership = false,
  });

  final Account account;
  final VoidCallback onTap;

  /// Marca lo del negocio (solo en la vista Todo).
  final bool showOwnership;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final a = account;
    final reconnect = a.status == ConnectionStatus.needsReconnect;
    final spoken = [
      a.institution,
      a.detail,
      if (a.isCard) 'Deuda ${Cop.spoken(a.debt)}' else Cop.spoken(a.balance),
      if (showOwnership && a.ownership == Ownership.business) 'Negocio',
      if (reconnect) 'Por reconectar',
    ].join('. ');

    return SizedBox(
      width: accountCardWidthFor(context),
      child: QCard(
        onTap: onTap,
        semanticLabel: spoken,
        child: ExcludeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InitialsAvatar(a.initials, size: AppSize.avatarSm),
                  const Spacer(),
                  if (a.isCard)
                    Icon(
                      Icons.credit_card_rounded,
                      size: AppSize.iconSm,
                      color: c.inkSubtle,
                    ),
                ],
              ),
              // Misma regla que los movimientos: en Todo solo se marca lo del
              // negocio; lo personal es lo esperado.
              if (reconnect ||
                  (showOwnership && a.ownership == Ownership.business))
                Padding(
                  padding: const EdgeInsets.only(top: AppSpace.xs),
                  child: Wrap(
                    spacing: AppSpace.xxs,
                    runSpacing: AppSpace.xxs,
                    children: [
                      if (reconnect)
                        const StatusPill(
                          'Por reconectar',
                          tone: PillTone.warning,
                          icon: Icons.sync_problem_rounded,
                        ),
                      if (showOwnership && a.ownership == Ownership.business)
                        const StatusPill('Negocio', tone: PillTone.business),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpace.sm),
              Text(
                a.institution,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(
                  color: c.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                a.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(color: c.inkSubtle),
              ),
              const Spacer(),
              const SizedBox(height: AppSpace.sm),
              if (a.isCard)
                Text(
                  'Deuda',
                  style: AppTypography.caption.copyWith(color: c.inkSubtle),
                ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MoneyText(
                  a.isCard ? a.debt : a.balance,
                  style: AppTypography.subtitle.copyWith(
                    color: reconnect ? c.inkMuted : c.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta final del carrusel para conectar otra cuenta.
class ConnectAccountCard extends StatelessWidget {
  const ConnectAccountCard({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: accountCardWidthFor(context),
      child: QCard(
        onTap: onTap,
        semanticLabel: 'Conectar cuenta. Bancos y billeteras',
        child: ExcludeSemantics(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconTile(
                icon: Icons.add_rounded,
                background: c.primaryContainer,
                foreground: c.onPrimaryContainer,
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                'Conectar cuenta',
                textAlign: TextAlign.center,
                style: AppTypography.body.copyWith(
                  color: c.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                'Bancos y billeteras',
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(color: c.inkSubtle),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
