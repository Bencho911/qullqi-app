import 'package:flutter/foundation.dart';

import 'package:qullqi/core/scope/scope.dart';

enum CommitmentKind {
  /// Pago fijo (arriendo, internet, plan de celular).
  bill,

  /// Impuesto estimado (IVA del bimestre).
  tax,
}

/// Pago próximo que no es una tarjeta (las tarjetas se derivan de la cuenta).
@immutable
class Commitment {
  const Commitment({
    required this.id,
    required this.title,
    required this.amount,
    required this.due,
    required this.ownership,
    required this.kind,
  });

  final String id;
  final String title;
  final int amount;
  final DateTime due;
  final Ownership ownership;
  final CommitmentKind kind;
}
