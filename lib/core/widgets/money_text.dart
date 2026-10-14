import 'package:flutter/material.dart';

import 'package:inti/core/money/money.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';

/// Monto en pesos con cifras tabulares.
///
/// Cuando el valor cambia, cuenta desde el anterior (no desde cero al montar:
/// un número que "arranca" en cero cada vez que se abre la pantalla genera
/// desconfianza). El lector de pantalla oye el valor final completo.
class MoneyText extends StatefulWidget {
  const MoneyText(
    this.value, {
    super.key,
    this.style,
    this.signed = false,
    this.currency = false,
    this.animate = true,
  });

  final int value;
  final TextStyle? style;

  /// Antepone "+" a los valores positivos.
  final bool signed;

  /// Agrega " COP" en tamaño menor.
  final bool currency;
  final bool animate;

  @override
  State<MoneyText> createState() => _MoneyTextState();
}

class _MoneyTextState extends State<MoneyText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.count,
  );
  late int _from = widget.value;

  @override
  void didUpdateWidget(MoneyText old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _from = _shown(old.value);
      if (widget.animate && !AppMotion.reduced(context)) {
        _c.forward(from: 0);
      } else {
        _c.value = 1;
      }
    }
  }

  int _shown(int target) {
    final t = AppMotion.standardCurve.transform(_c.value);
    return (_from + (target - _from) * t).round();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = (widget.style ?? DefaultTextStyle.of(context).style).copyWith(
      fontFeatures: AppTypography.tabular,
    );
    return Semantics(
      label: Cop.spoken(widget.value),
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final v = _c.isAnimating ? _shown(widget.value) : widget.value;
          final amount = Cop.format(v, signed: widget.signed);
          if (!widget.currency) return Text(amount, style: base);
          final size = base.fontSize ?? 15;
          return Text.rich(
            TextSpan(
              text: amount,
              children: [
                TextSpan(
                  text: ' COP',
                  style: base.copyWith(
                    fontSize: (size * 0.42).clamp(13, 15).toDouble(),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
            style: base,
          );
        },
      ),
    );
  }
}
