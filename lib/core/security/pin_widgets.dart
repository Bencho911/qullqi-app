import 'package:flutter/material.dart';

import 'package:qullqi/core/security/identity.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';

/// Tamaño de cada punto del PIN.
const double _dot = AppSpace.md;

/// Puntos que muestran cuántos dígitos del PIN se escribieron.
class PinDots extends StatelessWidget {
  const PinDots({required this.filled, super.key, this.error = false});

  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      label: 'PIN: $filled de $pinLength dígitos',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < pinLength; i++)
            AnimatedContainer(
              duration: AppMotion.of(context, AppMotion.fast),
              margin: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
              width: _dot,
              height: _dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < filled
                    ? (error ? c.danger : c.ink)
                    : Colors.transparent,
                border: Border.all(
                  color: error ? c.danger : c.outlineStrong,
                  width: 2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Mensaje bajo los puntos del PIN ("PIN incorrecto…"). Reserva una línea
/// aunque no haya error, para que el teclado no salte, crece con el texto
/// grande y el lector de pantalla lo anuncia al aparecer.
class PinError extends StatelessWidget {
  const PinError(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSpace.lg),
      child: Semantics(
        liveRegion: true,
        child: message == null
            ? const SizedBox(width: double.infinity)
            : Text(
                message!,
                textAlign: TextAlign.center,
                style: AppTypography.label.copyWith(
                  color: context.colors.onDangerContainer,
                ),
              ),
      ),
    );
  }
}
