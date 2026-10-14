import 'package:flutter/foundation.dart';

import 'package:inti/core/money/currency.dart';
import 'package:inti/core/scope/scope.dart';

enum AccountKind {
  savings('Ahorros'),
  checking('Corriente'),
  wallet('Billetera'),
  cash('Efectivo'),
  creditCard('Tarjeta de crédito');

  AccountKind(this.label);

  final String label;

  /// Dinero disponible de inmediato (las tarjetas son deuda, no dinero).
  bool get isLiquid => this != creditCard;
}

enum ConnectionStatus {
  /// Sincronizada por Open Finance.
  connected,

  /// El permiso venció: los saldos pueden estar desactualizados.
  needsReconnect,

  /// Registrada a mano o por extracto.
  manual,
}

/// Cuenta bancaria, billetera o tarjeta de crédito.
@immutable
class Account {
  const Account({
    required this.id,
    required this.institution,
    required this.kind,
    required this.last4,
    required this.ownership,
    required this.balance,
    required this.status,
    required this.lastSync,
    this.nickname,
    this.badge,
    this.creditLimit,
    this.statementBalance,
    this.minimumPayment,
    this.paymentDue,
    this.paymentsEnabled = false,
    this.interestRate,
    this.currency = Currency.cop,
    this.rate = 1,
  });

  final String id;

  /// Banco o billetera ("Bancolombia", "Nequi").
  final String institution;
  final AccountKind kind;
  final String last4;
  final Ownership ownership;

  /// Saldo en pesos. En tarjetas es la deuda total (positiva).
  final int balance;
  final ConnectionStatus status;
  final DateTime lastSync;
  final String? nickname;

  /// Abreviatura reconocible de la entidad ("BC", "NQ"). Si falta, se
  /// toman las iniciales del nombre.
  final String? badge;

  // Solo tarjetas de crédito.
  final int? creditLimit;

  /// Lo que hay que pagar en la fecha límite de este corte.
  final int? statementBalance;
  final int? minimumPayment;
  final DateTime? paymentDue;

  /// Tasa efectiva anual de la tarjeta como fracción (0.27 = 27 % e. a.).
  final double? interestRate;

  /// La persona autorizó mover plata desde esta cuenta (Open Finance).
  /// Las cuentas registradas a mano nunca lo tienen.
  final bool paymentsEnabled;

  /// Moneda en que se lleva la cuenta. [balance] siempre está en pesos.
  final Currency currency;

  /// Pesos por una unidad de [currency] con que se convirtió el saldo.
  final double rate;

  bool get isForeign => !currency.isHome;

  /// El saldo en la moneda de la cuenta (`null` si es en pesos).
  int? get foreignBalance => isForeign ? (balance / rate).round() : null;

  bool get isManual => status == ConnectionStatus.manual;

  bool get isCard => kind == AccountKind.creditCard;

  /// Deuda de la tarjeta (0 en cuentas).
  int get debt => isCard ? balance : 0;

  /// Cupo libre de la tarjeta.
  int get availableCredit => isCard ? (creditLimit ?? 0) - balance : 0;

  /// Lo que la cuenta suma al patrimonio (las tarjetas restan).
  int get netValue => isCard ? -balance : balance;

  /// Nombre corto y único en toda la app: "Nequi" o "Tarjeta Visa •• 4521".
  String get shortName =>
      isCard ? 'Tarjeta ${nickname ?? institution} •• $last4' : institution;

  /// Segunda línea bajo [shortName] sin repetir datos: el banco en una
  /// tarjeta ("Bancolombia"), el producto en una cuenta ("Ahorros •• 4521").
  String get secondaryLine {
    final base = isCard
        ? institution
        : kind == AccountKind.cash
        ? kind.label
        : detail;
    return isForeign
        ? '$base · ${formatForeign(foreignBalance!, currency)}'
        : base;
  }

  /// "Ahorros •• 4521".
  String get detail => '${nickname ?? kind.label} •• $last4';

  String get initials {
    if (badge != null) return badge!;
    final words = institution.split(' ').where((w) => w.isNotEmpty).toList();
    if (words.length == 1) return words.first.substring(0, 2).toUpperCase();
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }

  /// Aplica un movimiento de dinero: `delta` negativo es plata que sale.
  /// En una tarjeta, gastar sube la deuda y pagar la baja (también lo que
  /// queda por pagar del corte).
  Account applyDelta(int delta) {
    if (!isCard) return copyWith(balance: balance + delta);
    final debt = (balance - delta).clamp(0, 1 << 40);
    final statement = statementBalance == null || delta <= 0
        ? statementBalance
        : (statementBalance! - delta).clamp(0, 1 << 40);
    return copyWith(balance: debt, statementBalance: statement);
  }

  Account copyWith({
    int? balance,
    ConnectionStatus? status,
    DateTime? lastSync,
    int? statementBalance,
    bool? paymentsEnabled,
  }) => Account(
    id: id,
    institution: institution,
    kind: kind,
    last4: last4,
    ownership: ownership,
    balance: balance ?? this.balance,
    status: status ?? this.status,
    lastSync: lastSync ?? this.lastSync,
    nickname: nickname,
    badge: badge,
    creditLimit: creditLimit,
    statementBalance: statementBalance ?? this.statementBalance,
    minimumPayment: minimumPayment,
    paymentDue: paymentDue,
    paymentsEnabled: paymentsEnabled ?? this.paymentsEnabled,
    interestRate: interestRate,
    currency: currency,
    rate: rate,
  );
}
