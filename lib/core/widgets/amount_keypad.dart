import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:inti/core/money/money.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';

/// Monto grande que se está escribiendo con [AmountKeypad].
class AmountDisplay extends StatelessWidget {
  const AmountDisplay({
    required this.digits,
    super.key,
    this.label = 'Monto',
    this.error,
  });

  final String digits;
  final String label;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final value = AmountInput.value(digits);
    final empty = digits.isEmpty;
    return Column(
      children: [
        Text(label, style: AppTypography.label.copyWith(color: c.inkMuted)),
        const SizedBox(height: AppSpace.xxs),
        // El lector anuncia el monto completo cada vez que cambia.
        Semantics(
          liveRegion: true,
          label: empty ? 'Sin monto' : Cop.spoken(value),
          excludeSemantics: true,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              Cop.format(value),
              style: AppTypography.amountEntry.copyWith(
                color: empty ? c.inkSubtle : c.ink,
              ),
            ),
          ),
        ),
        // Reserva una línea para el error y crece si ocupa más: la
        // pantalla no salta al aparecer.
        ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.textScalerOf(context).scale(
              AppTypography.label.fontSize! * AppTypography.label.height!,
            ),
          ),
          child: AnimatedSwitcher(
            duration: AppMotion.of(context, AppMotion.fast),
            child: error == null
                ? const SizedBox.shrink()
                : Text(
                    error!,
                    key: ValueKey(error),
                    textAlign: TextAlign.center,
                    style: AppTypography.label.copyWith(
                      color: c.onDangerContainer,
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

/// Teclado numérico propio: siempre visible en las pantallas de monto, para
/// no abrir y cerrar el teclado del sistema. Vibra suave con cada tecla.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({
    required this.digits,
    required this.onChanged,
    super.key,
  });

  final String digits;
  final ValueChanged<String> onChanged;

  void _press(String key) {
    final next = AmountInput.press(digits, key);
    if (next == digits) {
      unawaited(HapticFeedback.heavyImpact());
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return NumberPad(
      label: 'Teclado numérico',
      bottomLeft: '000',
      onKey: _press,
      onClear: () => onChanged(''),
    );
  }
}

/// Teclado numérico base (montos y PIN): 1–9, una tecla extra abajo a la
/// izquierda, 0 y borrar. Mismas medidas y lectura en toda la app.
class NumberPad extends StatelessWidget {
  const NumberPad({
    required this.label,
    required this.onKey,
    super.key,
    this.bottomLeft,
    this.onClear,
    this.enabled = true,
  });

  /// Nombre del teclado para el lector de pantalla.
  final String label;

  /// Recibe '0'–'9', [bottomLeft] o 'del'.
  final ValueChanged<String> onKey;

  /// Tecla extra (p. ej. '000'); `null` la deja vacía.
  final String? bottomLeft;

  /// Mantener presionado borrar limpia todo (si se da).
  final VoidCallback? onClear;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Las teclas crecen con el tamaño de texto del sistema.
    final keyHeight = MediaQuery.textScalerOf(context)
        .scale(28)
        .clamp(AppSize.keyMin, AppSize.keyMax);
    final keys = [
      '1', '2', '3', //
      '4', '5', '6', //
      '7', '8', '9', //
      bottomLeft ?? '', '0', 'del',
    ];
    return Semantics(
      container: true,
      label: label,
      child: Column(
        children: [
          for (var r = 0; r < keys.length; r += 3)
            Padding(
              padding: EdgeInsets.only(top: r == 0 ? 0 : AppSpace.xs),
              child: Row(
                children: [
                  for (var i = r; i < r + 3; i++) ...[
                    if (i > r) const SizedBox(width: AppSpace.xs),
                    Expanded(
                      child: SizedBox(
                        height: keyHeight,
                        child: keys[i].isEmpty
                            ? null
                            : _Key(
                                label: keys[i],
                                onTap: enabled ? () => onKey(keys[i]) : null,
                                onLongPress: keys[i] == 'del' && enabled
                                    ? onClear
                                    : null,
                                color: c.ink,
                                pressed: c.surfaceSunken,
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.onTap,
    required this.color,
    required this.pressed,
    this.onLongPress,
  });

  final String label;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color color;
  final Color pressed;

  @override
  Widget build(BuildContext context) {
    final isDel = label == 'del';
    return Semantics(
      button: true,
      label: switch (label) {
        'del' when onLongPress != null =>
          'Borrar último dígito. Mantén presionado para borrar todo',
        'del' => 'Borrar último dígito',
        '000' => 'Tres ceros',
        _ => label,
      },
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.controlAll,
        child: InkWell(
          borderRadius: AppRadius.controlAll,
          highlightColor: pressed,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Center(
            child: isDel
                ? Icon(Icons.backspace_outlined, color: color)
                : Text(
                    label,
                    style: AppTypography.title.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Alto mínimo del cuerpo para dejar el teclado fijo abajo. Por debajo
/// (teléfonos pequeños o texto grande) todo se desplaza junto, para que
/// ningún campo quede escondido detrás del teclado.
const double _fixedKeypadMinHeight = 640;

/// Estructura de las pantallas de monto: arriba los campos, abajo el
/// teclado y el botón principal. El botón siempre queda a la vista.
class KeypadLayout extends StatelessWidget {
  const KeypadLayout({
    required this.fields,
    required this.keypad,
    required this.action,
    super.key,
  });

  final List<Widget> fields;
  final Widget keypad;

  /// Botón principal ("Guardar gasto", "Revisar").
  final Widget action;

  @override
  Widget build(BuildContext context) {
    const side = EdgeInsets.symmetric(horizontal: AppSpace.gutter);
    final pinnedAction = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.sm,
        AppSpace.gutter,
        AppSpace.md,
      ),
      child: action,
    );
    return LayoutBuilder(
      builder: (context, box) {
        // Con texto grande también: el teclado crece y taparía los campos.
        final compact =
            box.maxHeight < _fixedKeypadMinHeight || isLargeText(context);
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: side,
                children: [
                  ...fields,
                  if (compact) ...[const SizedBox(height: AppSpace.xs), keypad],
                ],
              ),
            ),
            if (!compact)
              Padding(
                padding: side.copyWith(top: AppSpace.xs),
                child: keypad,
              ),
            pinnedAction,
          ],
        );
      },
    );
  }
}
