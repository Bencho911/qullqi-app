import 'package:flutter/material.dart';

/// Escala tipográfica de Inti: cinco roles, tres pesos (400, 600, 700).
///
/// Ningún texto con información baja de 13 px. Todos los tamaños escalan con
/// el tamaño de texto del sistema (no se fija `textScaler`).
abstract final class AppTypography {
  static const String family = 'PlusJakartaSans';

  /// Cifras de ancho fijo: los montos no "bailan" al cambiar.
  static const List<FontFeature> tabular = [FontFeature.tabularFigures()];

  static const TextStyle display = TextStyle(
    fontFamily: family,
    fontSize: 34,
    height: 40 / 34,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.6,
    fontFeatures: tabular,
  );

  /// Monto que se está escribiendo (pantallas con teclado): el único dato
  /// de la pantalla, por eso más grande que [display].
  static const TextStyle amountEntry = TextStyle(
    fontFamily: family,
    fontSize: 44,
    height: 52 / 44,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    fontFeatures: tabular,
  );

  static const TextStyle title = TextStyle(
    fontFamily: family,
    fontSize: 22,
    height: 28 / 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
  );

  static const TextStyle subtitle = TextStyle(
    fontFamily: family,
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body = TextStyle(
    fontFamily: family,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle label = TextStyle(
    fontFamily: family,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w600,
  );

  /// Texto secundario bajo un título (detalles, fechas, ayudas): mismo tamaño
  /// que [label], peso regular.
  static const TextStyle caption = TextStyle(
    fontFamily: family,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
  );

  /// Mapea los roles a [TextTheme] de Material para que los widgets
  /// estándar (diálogos, campos, menús) hereden la misma escala.
  static TextTheme textTheme(Color ink, Color muted, Color subtle) {
    return TextTheme(
      displaySmall: display.copyWith(color: ink),
      headlineSmall: title.copyWith(color: ink),
      // Título de barras superiores (compacto).
      titleLarge: subtitle.copyWith(color: ink),
      titleMedium: subtitle.copyWith(color: ink),
      titleSmall: body.copyWith(color: ink, fontWeight: FontWeight.w600),
      bodyLarge: body.copyWith(color: ink),
      bodyMedium: body.copyWith(color: ink),
      bodySmall: caption.copyWith(color: subtle),
      labelLarge: body.copyWith(color: ink, fontWeight: FontWeight.w600),
      labelMedium: label.copyWith(color: ink),
      labelSmall: label.copyWith(color: muted),
    );
  }
}
