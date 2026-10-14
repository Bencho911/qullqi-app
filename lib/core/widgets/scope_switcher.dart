import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:inti/core/scope/scope.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';

/// Selector de vista Todo · Personal · Negocio.
///
/// Un indicador se desliza bajo la opción elegida. Para el lector de pantalla
/// es un grupo de opciones con estado "seleccionado".
class ScopeSwitcher extends StatelessWidget {
  const ScopeSwitcher({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final Scope value;
  final ValueChanged<Scope> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const options = Scope.values;
    final index = options.indexOf(value);
    // Cada segmento mide al menos 48 de alto (el contenedor suma 4 + 4 de
    // margen) y crece con el tamaño de texto del sistema.
    final lineHeight = MediaQuery.textScalerOf(context).scale(18);
    final height = (lineHeight + AppSpace.lg).clamp(
      AppSize.touch + AppSpace.xs,
      104.0,
    );
    return Semantics(
      label: 'Vista',
      container: true,
      child: Container(
        height: height,
        padding: const EdgeInsets.all(AppSpace.xxs),
        decoration: BoxDecoration(
          color: c.surfaceMuted,
          borderRadius: AppRadius.pill,
        ),
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth / options.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: AppMotion.of(context, AppMotion.standard),
                  curve: AppMotion.emphasizedCurve,
                  left: w * index,
                  top: 0,
                  bottom: 0,
                  width: w,
                  child: DecoratedBox(
                    // La opción elegida usa el verde suave: se distingue en
                    // claro y en oscuro sin depender solo de una sombra.
                    decoration: BoxDecoration(
                      color: c.primaryContainer,
                      borderRadius: AppRadius.pill,
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final o in options)
                      Expanded(
                        child: Semantics(
                          inMutuallyExclusiveGroup: true,
                          selected: o == value,
                          button: true,
                          child: InkWell(
                            borderRadius: AppRadius.pill,
                            onTap: () {
                              if (o == value) return;
                              unawaited(HapticFeedback.selectionClick());
                              onChanged(o);
                            },
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: AppMotion.of(context, AppMotion.fast),
                                style: AppTypography.label.copyWith(
                                  color: o == value
                                      ? c.onPrimaryContainer
                                      : c.inkMuted,
                                  fontWeight: o == value
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpace.xs,
                                  ),
                                  // Con texto muy grande se reduce en vez de
                                  // cortarse.
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(o.label, maxLines: 1),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
