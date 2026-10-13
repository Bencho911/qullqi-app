import 'package:flutter/material.dart';

import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/home/domain/forecast.dart';

/// "Cómo va tu mes": cuánto puedes gastar por día y cuánto tendrías al
/// terminar. Es un estimado, y la tarjeta lo dice.
class ForecastCard extends StatelessWidget {
  const ForecastCard({
    required this.forecast,
    required this.onSeeBudgets,
    super.key,
  });

  final MonthForecast forecast;
  final VoidCallback onSeeBudgets;

  @override
  Widget build(BuildContext context) {
    final f = forecast;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Cómo va tu mes'),
        const SizedBox(height: AppSpace.xs),
        if (f.runsShort) ...[
          QBanner(
            title: 'A este ritmo te quedas corto',
            message:
                'Te faltarían ${Cop.format(-f.projectedEnd)} antes de fin de '
                'mes.',
            actionLabel: 'Ver presupuestos',
            onAction: onSeeBudgets,
          ),
          const SizedBox(height: AppSpace.xs),
        ],
        QCard(
          child: Column(
            children: [
              DetailLine('Puedes gastar por día', Cop.format(f.perDay)),
              DetailLine('Gastas en un día típico', Cop.format(f.typicalDaily)),
              DetailLine(
                'A fin de mes tendrías',
                Cop.format(f.projectedEnd),
                emphasis: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          'Estimado con tu saldo, los pagos que vencen este mes y lo que '
          'gastaste en los últimos 30 días.',
          style: context.text.bodySmall,
        ),
      ],
    );
  }
}
