import 'package:flutter/widgets.dart';

/// Espaciado sobre una grilla de 4/8. Ningún valor fuera de esta lista.
abstract final class AppSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;

  /// Margen lateral de las pantallas.
  static const double gutter = 20;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Radios: chips 8, controles 14, tarjetas 20, hojas 28.
abstract final class AppRadius {
  static const double chip = 8;
  static const double control = 14;
  static const double card = 20;
  static const double sheet = 28;

  static const BorderRadius chipAll = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius controlAll = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

/// Tamaños mínimos de interacción.
abstract final class AppSize {
  /// Área táctil mínima (iOS 44, Android 48: usamos la mayor).
  static const double touch = 48;

  /// Alto de botones y campos.
  static const double control = 52;

  /// Ícono estándar y en filas.
  static const double icon = 22;
  static const double iconSm = 18;

  /// Ícono del botón principal "+".
  static const double iconLg = 28;

  /// Avatar o ícono de fila.
  static const double leading = 44;

  /// Avatar del encabezado y del perfil.
  static const double avatarSm = 36;
  static const double avatarLg = 56;

  /// Alto de las teclas de los teclados numéricos (crece con el texto).
  static const double keyMin = 52;
  static const double keyMax = 72;

  /// Alto mínimo de filas tocables con dos líneas (opciones, pestañas).
  static const double row = 60;

  /// Alto mínimo de filas con monto a la derecha (movimientos, pagos).
  static const double rowAmount = 64;
}

/// `true` con texto del sistema grande (≥ 130 %): las filas pasan el monto
/// y las acciones a su propia línea para no partir palabras.
bool isLargeText(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(10) >= 13;

/// Movimiento con propósito: corto, sin rebotes gratuitos.
abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration emphasized = Duration(milliseconds: 320);

  /// Conteo de montos cuando cambian.
  static const Duration count = Duration(milliseconds: 600);

  /// Escalonado de listas: máximo 8 elementos se escalonan.
  static const Duration stagger = Duration(milliseconds: 30);

  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve emphasizedCurve = Cubic(0.2, 0, 0, 1);

  /// `true` cuando la persona pidió reducir el movimiento en el sistema.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Duración efectiva: cero si se reduce el movimiento.
  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;
}
