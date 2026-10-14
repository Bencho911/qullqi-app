import 'package:flutter/material.dart';

import 'package:inti/core/money/money.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/money_text.dart';

/// Una parte del total (por ejemplo, personal y negocio en la vista Todo).
class BalanceShare {
  const BalanceShare(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;
}

/// El bloque destacado de una pantalla: un solo número grande.
///
/// Solo hay un hero por pantalla. Lo demás va en tarjetas neutras.
class HeroBalance extends StatelessWidget {
  const HeroBalance({
    required this.label,
    required this.value,
    super.key,
    this.caption,
    this.onInfo,
    this.infoSemantics = 'Cómo lo calculamos',
    this.shares = const [],
    this.footer,
  });

  final String label;
  final int value;

  /// Línea corta que explica el número ("Ya descontamos tus pagos de 30 días").
  final String? caption;
  final VoidCallback? onInfo;
  final String infoSemantics;

  /// Reparto del total en una barra fina (solo en la vista Todo).
  final List<BalanceShare> shares;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.md,
          AppSpace.xs,
          AppSpace.gutter,
        ),
        decoration: BoxDecoration(
          color: c.hero,
          borderRadius: AppRadius.cardAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.label.copyWith(color: c.onHeroMuted),
                  ),
                ),
                if (onInfo != null)
                  IconButton(
                    onPressed: onInfo,
                    tooltip: infoSemantics,
                    color: c.onHeroMuted,
                    icon: const Icon(Icons.info_outline_rounded),
                  )
                else
                  const SizedBox(height: AppSize.touch),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: AppSpace.sm),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MoneyText(
                  value,
                  currency: true,
                  style: AppTypography.display.copyWith(color: c.onHero),
                ),
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: AppSpace.xxs),
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.sm),
                child: Text(
                  caption!,
                  style: AppTypography.caption.copyWith(color: c.onHeroMuted),
                ),
              ),
            ],
            if (shares.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.sm),
                child: _ShareBar(shares: shares),
              ),
            ],
            if (footer != null) ...[
              const SizedBox(height: AppSpace.md),
              Padding(
                padding: const EdgeInsets.only(right: AppSpace.sm),
                child: footer,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.shares});

  final List<BalanceShare> shares;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final total = shares.fold<int>(
      0,
      (s, e) => s + (e.value > 0 ? e.value : 0),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: ClipRRect(
            borderRadius: AppRadius.pill,
            child: SizedBox(
              height: 6,
              child: Row(
                children: [
                  for (final s in shares)
                    if (s.value > 0 && total > 0)
                      Expanded(
                        flex: (s.value * 1000 ~/ total).clamp(1, 1000),
                        child: ColoredBox(color: s.color),
                      ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Wrap(
          spacing: AppSpace.md,
          runSpacing: AppSpace.xxs,
          children: [
            for (final s in shares)
              Semantics(
                label: '${s.label}: ${Cop.spoken(s.value)}',
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ExcludeSemantics(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: s.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.xxs),
                    Text(
                      '${s.label} ',
                      style: AppTypography.caption.copyWith(
                        color: c.onHeroMuted,
                      ),
                    ),
                    MoneyText(
                      s.value,
                      style: AppTypography.label.copyWith(color: c.onHero),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
