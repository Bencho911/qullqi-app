import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contraste WCAG 2.x entre dos colores opacos.
double contrast(Color a, Color b) {
  double lum(Color c) {
    double ch(double v) => v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
  }

  final x = lum(a);
  final y = lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// ¿Hay un ancestro que atenúa (deshabilitado o en transición)?
bool _dimmed(Element element) {
  var dimmed = false;
  element.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Opacity && w.opacity < 1) dimmed = true;
    return !dimmed;
  });
  return dimmed;
}

/// ¿Está el elemento en una ruta tapada por otra (también en navegadores
/// anidados, como las pestañas bajo una hoja del navegador raíz)?
bool _covered(BuildContext context) {
  BuildContext? c = context;
  while (c != null) {
    final route = ModalRoute.of(c);
    if (route == null) return false;
    if (!route.isCurrent) return true;
    c = route.navigator?.context;
  }
  return false;
}

void _spans(InlineSpan span, TextStyle? inherited, void Function(TextStyle) f) {
  if (span is! TextSpan) return;
  final style = inherited?.merge(span.style) ?? span.style;
  if ((span.text?.trim().isNotEmpty ?? false) && style != null) f(style);
  for (final child in span.children ?? const <InlineSpan>[]) {
    _spans(child, style, f);
  }
}

/// Revisa el contraste de cada texto visible contra el fondo que realmente
/// tiene detrás.
///
/// - Color del texto: el que declara su estilo (no el borde suavizado).
/// - Fondo: el color más frecuente en los píxeles del rectángulo del texto,
///   medido sobre la pantalla dibujada (sirve con cualquier widget).
///
/// Texto grande (≥ 24 px, o ≥ 18,66 px en negrita) exige 3:1; el resto 4,5:1.
/// Se omiten textos atenuados o transparentes (WCAG exime los deshabilitados).
Future<void> expectTextContrast(WidgetTester tester) async {
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  final image = await layer.toImage(view.paintBounds);
  final bytes = (await tester.runAsync(image.toByteData))!;
  final w = image.width;
  final h = image.height;
  // La imagen puede venir en píxeles físicos: se escala cada rectángulo.
  final scale = w / view.size.width;

  Color? background(Rect logical) {
    final r = Rect.fromLTRB(
      logical.left * scale,
      logical.top * scale,
      logical.right * scale,
      logical.bottom * scale,
    );
    final counts = <int, int>{};
    final left = r.left.floor().clamp(0, w - 1);
    final right = r.right.ceil().clamp(0, w);
    final top = r.top.floor().clamp(0, h - 1);
    final bottom = r.bottom.ceil().clamp(0, h);
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        final v = bytes.getUint32((y * w + x) * 4);
        counts[v] = (counts[v] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    final top1 = counts.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final v = top1.key;
    return Color.fromARGB(255, v >> 24 & 0xff, v >> 16 & 0xff, v >> 8 & 0xff);
  }

  final failures = <String>[];
  for (final e in find.byType(RichText).evaluate()) {
    final rich = e.widget as RichText;
    final box = e.renderObject;
    if (box is! RenderBox || !box.hasSize || box.size.isEmpty) continue;
    if (_dimmed(e)) continue;
    // Lo que queda detrás de una hoja o diálogo está tapado e inactivo.
    if (_covered(e)) continue;
    final rect = MatrixUtils.transformRect(
      box.getTransformTo(null),
      Offset.zero & box.size,
    );
    if (!(Offset.zero & view.size).overlaps(rect)) continue;
    final bg = background(rect);
    if (bg == null) continue;
    _spans(rich.text, null, (style) {
      final color = style.color;
      if (color == null || color.a < 1) return;
      // Los íconos son glifos de una fuente de íconos, no texto.
      if (style.fontFamily == 'MaterialIcons') return;
      final size = style.fontSize ?? 14;
      final bold = (style.fontWeight?.value ?? 400) >= 700;
      final large = size >= 24 || (bold && size >= 18.66);
      final min = large ? 3.0 : 4.5;
      final r = contrast(color, bg);
      if (r < min) {
        failures.add(
          '"${rich.text.toPlainText()}" ${r.toStringAsFixed(2)}:1 '
          '(mínimo $min) color $color sobre $bg',
        );
      }
    });
  }
  image.dispose();
  expect(failures, isEmpty, reason: failures.join('\n'));
}
