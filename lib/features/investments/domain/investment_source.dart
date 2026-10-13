import 'package:flutter/foundation.dart' show immutable;

import 'package:qullqi/features/investments/domain/investment.dart';

/// Entidad con la que se puede conectar el portafolio (solo lectura).
@immutable
class InvestmentSource {
  const InvestmentSource({
    required this.id,
    required this.name,
    required this.badge,
    required this.kinds,
    required this.description,
    this.available = true,
  });

  final String id;
  final String name;
  final String badge;

  /// Qué tipos de inversión trae de esa entidad.
  final List<InvestmentKind> kinds;

  /// "CDT y fondos".
  final String description;

  /// `false`: todavía sin conexión automática (se registra a mano).
  final bool available;
}

/// Entidades disponibles. El backend real traerá la lista del agregador.
abstract final class InvestmentSources {
  static const all = <InvestmentSource>[
    InvestmentSource(
      id: 'bancolombia',
      name: 'Bancolombia',
      badge: 'BC',
      kinds: [InvestmentKind.cdt, InvestmentKind.fund],
      description: 'CDT y fondos de inversión',
    ),
    InvestmentSource(
      id: 'davivienda',
      name: 'Davivienda',
      badge: 'DV',
      kinds: [InvestmentKind.cdt],
      description: 'CDT',
    ),
    InvestmentSource(
      id: 'tyba',
      name: 'Tyba',
      badge: 'TY',
      kinds: [InvestmentKind.fund],
      description: 'Fondos de inversión',
    ),
    InvestmentSource(
      id: 'trii',
      name: 'Trii',
      badge: 'TR',
      kinds: [InvestmentKind.stock],
      description: 'Acciones y ETF',
    ),
    InvestmentSource(
      id: 'proteccion',
      name: 'Protección',
      badge: 'PR',
      kinds: [InvestmentKind.pension],
      description: 'Pensión voluntaria y cesantías',
    ),
    InvestmentSource(
      id: 'porvenir',
      name: 'Porvenir',
      badge: 'PV',
      kinds: [InvestmentKind.pension],
      description: 'Pensión voluntaria y cesantías',
    ),
    InvestmentSource(
      id: 'skandia',
      name: 'Skandia',
      badge: 'SK',
      kinds: [InvestmentKind.fund],
      description: 'Aún sin conexión automática',
      available: false,
    ),
  ];

  static InvestmentSource? byId(String id) =>
      all.where((s) => s.id == id).firstOrNull;
}
