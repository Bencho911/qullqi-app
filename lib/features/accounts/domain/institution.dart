import 'package:flutter/foundation.dart';

import 'package:inti/features/accounts/domain/account.dart';

/// Banco o billetera con la que se puede conectar una cuenta.
@immutable
class Institution {
  const Institution({
    required this.id,
    required this.name,
    required this.badge,
    required this.kind,
    this.description = '',
    this.available = true,
    this.supportsPayments = true,
  });

  final String id;
  final String name;
  final String badge;

  /// Tipo de cuenta que se crea al conectar.
  final AccountKind kind;

  /// "Ahorros, corriente y tarjetas".
  final String description;

  /// `false`: todavía no tiene Open Finance (se puede agregar a mano).
  final bool available;

  /// Si permite iniciar pagos (mover plata) desde Inti.
  final bool supportsPayments;
}

/// Entidades disponibles. El backend real traerá la lista del agregador.
abstract final class Institutions {
  static const all = <Institution>[
    Institution(
      id: 'bancolombia',
      name: 'Bancolombia',
      badge: 'BC',
      kind: AccountKind.savings,
      description: 'Ahorros, corriente y tarjetas',
    ),
    Institution(
      id: 'nequi',
      name: 'Nequi',
      badge: 'NQ',
      kind: AccountKind.wallet,
      description: 'Billetera',
    ),
    Institution(
      id: 'davivienda',
      name: 'Davivienda',
      badge: 'DV',
      kind: AccountKind.savings,
      description: 'Ahorros, corriente y tarjetas',
    ),
    Institution(
      id: 'daviplata',
      name: 'Daviplata',
      badge: 'DP',
      kind: AccountKind.wallet,
      description: 'Billetera',
    ),
    Institution(
      id: 'bogota',
      name: 'Banco de Bogotá',
      badge: 'BB',
      kind: AccountKind.savings,
      description: 'Ahorros y corriente',
    ),
    Institution(
      id: 'bbva',
      name: 'BBVA',
      badge: 'BV',
      kind: AccountKind.savings,
      description: 'Ahorros, corriente y tarjetas',
    ),
    Institution(
      id: 'nu',
      name: 'Nu',
      badge: 'NU',
      kind: AccountKind.savings,
      description: 'Cuenta y tarjeta',
    ),
    Institution(
      id: 'lulo',
      name: 'Lulo Bank',
      badge: 'LB',
      kind: AccountKind.savings,
      description: 'Cuenta de ahorros',
    ),
    Institution(
      id: 'colpatria',
      name: 'Scotiabank Colpatria',
      badge: 'SC',
      kind: AccountKind.savings,
      description: 'Ahorros y tarjetas',
      supportsPayments: false,
    ),
    Institution(
      id: 'occidente',
      name: 'Banco de Occidente',
      badge: 'BO',
      kind: AccountKind.savings,
      description: 'Ahorros y corriente',
      supportsPayments: false,
    ),
    Institution(
      id: 'cajasocial',
      name: 'Banco Caja Social',
      badge: 'CS',
      kind: AccountKind.savings,
      description: 'Aún sin conexión automática',
      available: false,
    ),
    Institution(
      id: 'rappipay',
      name: 'RappiPay',
      badge: 'RP',
      kind: AccountKind.wallet,
      description: 'Aún sin conexión automática',
      available: false,
    ),
  ];

  static Institution? byId(String id) =>
      all.where((i) => i.id == id).firstOrNull;
}
