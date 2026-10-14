import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:inti/core/theme/app_colors.dart';

import '../../helpers/contrast.dart';

void main() {
  for (final (name, c) in [
    ('claro', AppColors.light),
    ('oscuro', AppColors.dark),
  ]) {
    group('Contraste tema $name', () {
      // Texto: 4,5:1 como mínimo (WCAG AA texto normal).
      final text = <String, (Color, Color)>{
        'tinta / fondo': (c.ink, c.background),
        'tinta secundaria / fondo': (c.inkMuted, c.background),
        'tinta terciaria / fondo': (c.inkSubtle, c.background),
        'tinta terciaria / superficie': (c.inkSubtle, c.surface),
        'tinta secundaria / relleno': (c.inkMuted, c.surfaceMuted),
        'tinta terciaria / hundido': (c.inkSubtle, c.surfaceSunken),
        'botón primario': (c.onPrimary, c.primary),
        'primario / superficie (enlaces)': (c.primary, c.surface),
        'primario / fondo (enlaces)': (c.primary, c.background),
        'contenedor primario': (c.onPrimaryContainer, c.primaryContainer),
        'hero': (c.onHero, c.hero),
        'hero secundario': (c.onHeroMuted, c.hero),
        'acento hero': (c.heroAccent, c.hero),
        'ingreso / superficie': (c.income, c.surface),
        'ingreso / fondo': (c.income, c.background),
        'traslado / superficie': (c.transfer, c.surface),
        'traslado / contenedor': (c.transfer, c.transferContainer),
        'alerta / contenedor': (c.warning, c.warningContainer),
        'alerta / superficie': (c.warning, c.surface),
        'peligro / superficie': (c.danger, c.surface),
        'botón peligro': (c.onDanger, c.danger),
        'contenedor peligro': (c.onDangerContainer, c.dangerContainer),
        'error de campo / superficie': (c.onDangerContainer, c.surface),
        'negocio / contenedor': (c.business, c.businessContainer),
        'aviso (snackbar)': (c.surface, c.ink),
      };
      for (final MapEntry(key: label, value: pair) in text.entries) {
        test('$label ≥ 4,5:1', () {
          final r = contrast(pair.$1, pair.$2);
          expect(r, greaterThanOrEqualTo(4.5), reason: '$label = $r');
        });
      }

      // Elementos que no son texto (bordes de control, foco): 3:1.
      final ui = <String, (Color, Color)>{
        'borde de control / superficie': (c.outlineStrong, c.surface),
        'borde de control / fondo': (c.outlineStrong, c.background),
        'foco (primario) / superficie': (c.primary, c.surface),
        'barra de progreso / pista': (c.primary, c.surfaceSunken),
      };
      for (final MapEntry(key: label, value: pair) in ui.entries) {
        test('$label ≥ 3:1', () {
          final r = contrast(pair.$1, pair.$2);
          expect(r, greaterThanOrEqualTo(3), reason: '$label = $r');
        });
      }
    });
  }
}
