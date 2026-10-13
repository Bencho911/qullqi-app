import 'package:flutter/material.dart';

import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/domain/account.dart';
import 'package:qullqi/features/investments/domain/investment.dart';

/// "Actualizada hace 5 min", "Valor del 21 de octubre".
String investmentSyncLabel(Investment i, DateTime now) {
  switch (i.status) {
    case ConnectionStatus.needsReconnect:
      return 'Reconecta para ver el valor de hoy';
    case ConnectionStatus.manual:
      return 'Valor del ${Dates.dayMonth(i.lastSync)}';
    case ConnectionStatus.connected:
      final m = now.difference(i.lastSync).inMinutes;
      if (m < 1) return 'Actualizada ahora';
      if (m < 60) return 'Actualizada hace $m min';
      final h = m ~/ 60;
      if (h < 24) return 'Actualizada hace $h h';
      return 'Actualizada el ${Dates.dayMonth(i.lastSync)}';
  }
}

SyncState investmentSyncState(Investment i) =>
    i.needsReconnect ? SyncState.reconnect : SyncState.ok;

/// "Ganó $473.800" / "Perdió $126.000" / "Sin cambio".
String gainPhrase(int gain) {
  if (gain == 0) return 'Sin ganancia ni pérdida';
  return gain > 0
      ? 'Ganaste ${Cop.format(gain)}'
      : 'Perdiste ${Cop.format(-gain)}';
}

/// Inversión en lista: nombre, entidad y rentabilidad, valor de hoy y estado.
class InvestmentTile extends StatelessWidget {
  const InvestmentTile({
    required this.investment,
    required this.now,
    required this.showOwnership,
    required this.onTap,
    super.key,
  });

  final Investment investment;
  final DateTime now;

  /// En la vista Todo se marca lo del negocio.
  final bool showOwnership;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i = investment;
    return AccountTile(
      initials: i.initials,
      name: i.name,
      detail:
          '${i.institution ?? i.kind.label} · ${signedPercent(i.returnRatio)}',
      balance: i.value,
      sync: investmentSyncState(i),
      syncLabel: investmentSyncLabel(i, now),
      ownership: showOwnership && i.ownership == Ownership.business
          ? const StatusPill('Negocio', tone: PillTone.business)
          : null,
      onTap: onTap,
    );
  }
}

/// Fila de "cómo está repartido": tipo, valor, porcentaje y barra.
class KindShareRow extends StatelessWidget {
  const KindShareRow({required this.share, super.key});

  final KindShare share;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final large = isLargeText(context);
    final amount = MoneyText(
      share.value,
      animate: false,
      style: AppTypography.body.copyWith(
        color: c.ink,
        fontWeight: FontWeight.w600,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: Semantics(
        label:
            '${share.kind.label}: ${Cop.spoken(share.value)}, '
            '${Cop.percent(share.ratio * 100)} de tus inversiones',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(share.kind.icon, size: AppSize.iconSm, color: c.inkMuted),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(
                    '${share.kind.label} · ${Cop.percent(share.ratio * 100)}',
                    style: context.text.bodyMedium,
                  ),
                ),
                if (!large) amount,
              ],
            ),
            // Con texto grande el monto baja de línea.
            if (large) amount,
            const SizedBox(height: AppSpace.xxs),
            QProgressBar(
              value: share.ratio,
              height: AppSpace.xs - AppSpace.xxs,
              semanticLabel: share.kind.label,
            ),
          ],
        ),
      ),
    );
  }
}
