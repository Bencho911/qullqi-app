import 'package:flutter/foundation.dart';

import 'package:inti/features/accounts/domain/account.dart';

/// Tope diario para mover plata desde la app.
const int dailyMoveLimit = 5000000;

/// Monto desde el que se pide confirmación reforzada (PIN además de huella).
const int highAmountThreshold = 2000000;

/// Por qué no se puede mover la plata, antes de intentarlo.
enum MoveProblem {
  sameAccount,
  sourceIsCard,
  noAmount,
  insufficientFunds,
  overDailyLimit,
  sourceDisconnected,
  sourceManual,
  paymentsNotEnabled,
  overCardDebt,
}

/// Revisa una orden de movimiento. Devuelve `null` si se puede intentar.
MoveProblem? validateMove({
  required Account? from,
  required Account? to,
  required int amount,
}) {
  if (amount <= 0) return MoveProblem.noAmount;
  if (from == null || to == null) return MoveProblem.noAmount;
  if (from.id == to.id) return MoveProblem.sameAccount;
  if (from.isCard) return MoveProblem.sourceIsCard;
  if (from.status == ConnectionStatus.needsReconnect) {
    return MoveProblem.sourceDisconnected;
  }
  if (from.isManual) return MoveProblem.sourceManual;
  if (!from.paymentsEnabled) return MoveProblem.paymentsNotEnabled;
  if (amount > from.balance) return MoveProblem.insufficientFunds;
  if (amount > dailyMoveLimit) return MoveProblem.overDailyLimit;
  if (to.isCard && amount > to.debt) return MoveProblem.overCardDebt;
  return null;
}

/// Mensaje para la persona: qué pasa y qué puede hacer.
String moveProblemMessage(MoveProblem p, {Account? from, Account? to}) =>
    switch (p) {
      MoveProblem.noAmount => 'Escribe cuánto quieres mover.',
      MoveProblem.sameAccount => 'Elige dos cuentas distintas.',
      MoveProblem.sourceIsCard =>
        'Desde una tarjeta de crédito no se puede mover plata.',
      MoveProblem.sourceDisconnected =>
        'Reconecta ${from?.institution ?? 'la cuenta'} para mover plata '
            'desde ahí.',
      MoveProblem.sourceManual =>
        '${from?.shortName ?? 'Esa cuenta'} está registrada a mano: desde ahí '
            'no se puede mover plata.',
      MoveProblem.paymentsNotEnabled =>
        'Aún no autorizaste mover plata desde '
            '${from?.shortName ?? 'esa cuenta'}. Actívalo en su detalle.',
      MoveProblem.insufficientFunds =>
        'No te alcanza: en ${from?.shortName ?? 'esa cuenta'} tienes menos.',
      MoveProblem.overDailyLimit =>
        'Supera tu tope diario. Divídelo en dos días o hazlo desde tu banco.',
      MoveProblem.overCardDebt =>
        'Es más de lo que debes en ${to?.shortName ?? 'la tarjeta'}.',
    };

enum MoveStatus {
  /// El banco confirmó: la plata ya está en la otra cuenta.
  done,

  /// El banco recibió la orden pero aún no confirma.
  pending,

  /// El banco la rechazó.
  rejected,
}

/// Resultado de mover plata.
@immutable
class MoveResult {
  const MoveResult({
    required this.status,
    required this.reference,
    required this.when,
    this.reason,
  });

  final MoveStatus status;

  /// Número de comprobante para soporte.
  final String reference;
  final DateTime when;

  /// Motivo del rechazo, en palabras de la persona.
  final String? reason;
}
