import 'package:flutter/material.dart';

/// Tokens de color de Qullqi (dirección "Calma verde").
///
/// Regla 60/30/10: fondo y superficies neutras, tinta para el contenido y el
/// verde solo para acciones e indicadores clave. Cada par texto/fondo cumple
/// 4,5:1 y cada borde de control 3:1 (ver `test/core/theme/contrast_test.dart`).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceSunken,
    required this.outline,
    required this.outlineStrong,
    required this.ink,
    required this.inkMuted,
    required this.inkSubtle,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.hero,
    required this.onHero,
    required this.onHeroMuted,
    required this.heroAccent,
    required this.income,
    required this.transfer,
    required this.transferContainer,
    required this.warning,
    required this.warningContainer,
    required this.danger,
    required this.onDanger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.business,
    required this.businessContainer,
    required this.scrim,
    required this.shadow,
  });

  /// Fondo de las pantallas.
  final Color background;

  /// Tarjetas, hojas y campos.
  final Color surface;

  /// Relleno de chips, segmentados y botones secundarios.
  final Color surfaceMuted;

  /// Estado presionado y esqueletos.
  final Color surfaceSunken;

  /// Bordes decorativos y separadores.
  final Color outline;

  /// Bordes de controles (campos, interruptor apagado).
  /// Cumplen 3:1 sobre la superficie.
  final Color outlineStrong;

  /// Texto principal.
  final Color ink;

  /// Texto secundario.
  final Color inkMuted;

  /// Texto terciario (fechas, metadatos). Sigue cumpliendo 4,5:1.
  final Color inkSubtle;

  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;

  /// Fondo del único bloque destacado de cada pantalla (el disponible).
  final Color hero;
  final Color onHero;
  final Color onHeroMuted;
  final Color heroAccent;

  /// Montos que entran. Los gastos van en tinta: el rojo queda para lo urgente.
  final Color income;

  /// Traslados entre cuentas propias.
  final Color transfer;
  final Color transferContainer;

  /// Texto de alerta (ámbar oscuro legible) y su fondo.
  final Color warning;
  final Color warningContainer;

  final Color danger;
  final Color onDanger;
  final Color dangerContainer;
  final Color onDangerContainer;

  /// Identifica lo del negocio sin parecer una alerta.
  final Color business;
  final Color businessContainer;

  final Color scrim;

  /// Sombras teñidas del verde del fondo, nunca negro puro.
  final Color shadow;

  static const light = AppColors(
    background: Color(0xFFF7F8F6),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEFF2EF),
    surfaceSunken: Color(0xFFE4E9E5),
    outline: Color(0xFFDDE3DF),
    outlineStrong: Color(0xFF85928B),
    ink: Color(0xFF12201A),
    inkMuted: Color(0xFF43524B),
    inkSubtle: Color(0xFF5B6862),
    primary: Color(0xFF0B7554),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFDCF1E6),
    onPrimaryContainer: Color(0xFF063D2B),
    hero: Color(0xFF0B2A1F),
    onHero: Color(0xFFFFFFFF),
    onHeroMuted: Color(0xFFB7CBC1),
    heroAccent: Color(0xFF7FE3B8),
    income: Color(0xFF0A7050),
    transfer: Color(0xFF4A45B8),
    transferContainer: Color(0xFFECEBFA),
    warning: Color(0xFF7D500A),
    warningContainer: Color(0xFFFBEBCB),
    danger: Color(0xFFB83A33),
    onDanger: Color(0xFFFFFFFF),
    dangerContainer: Color(0xFFFBE4E1),
    onDangerContainer: Color(0xFF8A2621),
    business: Color(0xFF1F5E7A),
    businessContainer: Color(0xFFDDEBF1),
    scrim: Color(0x8008100C),
    shadow: Color(0x1F0B2A1F),
  );

  /// Grafito casi neutro: las capas se separan por claridad (más alto, más
  /// claro) y el verde queda solo en la marca y las acciones, sin teñir el
  /// fondo ni las tarjetas.
  static const dark = AppColors(
    background: Color(0xFF121413),
    surface: Color(0xFF1C1F1E),
    surfaceMuted: Color(0xFF262A29),
    surfaceSunken: Color(0xFF303533),
    outline: Color(0xFF323836),
    outlineStrong: Color(0xFF88928E),
    ink: Color(0xFFF3F5F4),
    inkMuted: Color(0xFFBFC7C3),
    inkSubtle: Color(0xFFA0AAA6),
    primary: Color(0xFF56BE94),
    onPrimary: Color(0xFF06231A),
    primaryContainer: Color(0xFF213B32),
    onPrimaryContainer: Color(0xFFD2EEE2),
    hero: Color(0xFF17372C),
    onHero: Color(0xFFFFFFFF),
    onHeroMuted: Color(0xFFC3D3CB),
    heroAccent: Color(0xFF9BDDBE),
    income: Color(0xFF62C79F),
    transfer: Color(0xFFA4A8F2),
    transferContainer: Color(0xFF2B2C48),
    warning: Color(0xFFEBC070),
    warningContainer: Color(0xFF3B3018),
    danger: Color(0xFFEE8F88),
    onDanger: Color(0xFF3A0B08),
    dangerContainer: Color(0xFF3C2523),
    onDangerContainer: Color(0xFFFFB8B2),
    business: Color(0xFF8CC4DD),
    businessContainer: Color(0xFF1B323C),
    scrim: Color(0x99000000),
    shadow: Color(0x66000000),
  );

  @override
  AppColors copyWith({Color? primary, Color? background}) => AppColors(
    background: background ?? this.background,
    surface: surface,
    surfaceMuted: surfaceMuted,
    surfaceSunken: surfaceSunken,
    outline: outline,
    outlineStrong: outlineStrong,
    ink: ink,
    inkMuted: inkMuted,
    inkSubtle: inkSubtle,
    primary: primary ?? this.primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,
    hero: hero,
    onHero: onHero,
    onHeroMuted: onHeroMuted,
    heroAccent: heroAccent,
    income: income,
    transfer: transfer,
    transferContainer: transferContainer,
    warning: warning,
    warningContainer: warningContainer,
    danger: danger,
    onDanger: onDanger,
    dangerContainer: dangerContainer,
    onDangerContainer: onDangerContainer,
    business: business,
    businessContainer: businessContainer,
    scrim: scrim,
    shadow: shadow,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      surfaceSunken: l(surfaceSunken, other.surfaceSunken),
      outline: l(outline, other.outline),
      outlineStrong: l(outlineStrong, other.outlineStrong),
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      inkSubtle: l(inkSubtle, other.inkSubtle),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      primaryContainer: l(primaryContainer, other.primaryContainer),
      onPrimaryContainer: l(onPrimaryContainer, other.onPrimaryContainer),
      hero: l(hero, other.hero),
      onHero: l(onHero, other.onHero),
      onHeroMuted: l(onHeroMuted, other.onHeroMuted),
      heroAccent: l(heroAccent, other.heroAccent),
      income: l(income, other.income),
      transfer: l(transfer, other.transfer),
      transferContainer: l(transferContainer, other.transferContainer),
      warning: l(warning, other.warning),
      warningContainer: l(warningContainer, other.warningContainer),
      danger: l(danger, other.danger),
      onDanger: l(onDanger, other.onDanger),
      dangerContainer: l(dangerContainer, other.dangerContainer),
      onDangerContainer: l(onDangerContainer, other.onDangerContainer),
      business: l(business, other.business),
      businessContainer: l(businessContainer, other.businessContainer),
      scrim: l(scrim, other.scrim),
      shadow: l(shadow, other.shadow),
    );
  }
}
