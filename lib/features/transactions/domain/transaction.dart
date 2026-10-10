import 'package:flutter/material.dart';

import 'package:qullqi/core/scope/scope.dart';

enum TransactionKind {
  expense('Gasto'),
  income('Ingreso'),
  transfer('Traslado');

  TransactionKind(this.label);

  final String label;
}

/// De dónde viene el movimiento.
enum TransactionSource {
  /// Lo trajo el banco: no se puede borrar, solo clasificar.
  synced,

  /// Lo registró la persona: se puede editar y borrar.
  manual,

  /// Vino de un extracto que importó la persona: se puede borrar, y borrarlo
  /// no cambia el saldo.
  imported,
}

/// Categoría de un movimiento.
@immutable
class Category {
  const Category(this.id, this.name, this.icon);

  final String id;
  final String name;
  final IconData icon;
}

/// Categorías disponibles. El backend podrá agregar las propias de la persona.
abstract final class Categories {
  static const groceries = Category(
    'mercado',
    'Mercado',
    Icons.shopping_basket_rounded,
  );
  static const transport = Category(
    'transporte',
    'Transporte',
    Icons.directions_car_rounded,
  );
  static const coffee = Category(
    'salidas',
    'Cafés y salidas',
    Icons.local_cafe_rounded,
  );
  static const health = Category('salud', 'Salud', Icons.favorite_rounded);
  static const home = Category('hogar', 'Hogar', Icons.home_rounded);
  static const software = Category(
    'software',
    'Software',
    Icons.laptop_mac_rounded,
  );
  static const fees = Category(
    'honorarios',
    'Honorarios',
    Icons.payments_rounded,
  );
  static const transferIn = Category(
    'entre-personas',
    'Entre personas',
    Icons.people_alt_rounded,
  );
  static const subscriptions = Category(
    'suscripciones',
    'Suscripciones',
    Icons.autorenew_rounded,
  );
  static const internal = Category(
    'traslado',
    'Traslado',
    Icons.swap_horiz_rounded,
  );

  static const other = Category('otros', 'Otros', Icons.category_rounded);

  static const List<Category> all = [
    groceries,
    transport,
    coffee,
    health,
    home,
    software,
    fees,
    transferIn,
    subscriptions,
    other,
    internal,
  ];

  /// Las que la persona puede elegir (los traslados se marcan aparte).
  static List<Category> get pickable =>
      all.where((c) => c != internal).toList();

  static Category byId(String id) =>
      all.firstWhere((c) => c.id == id, orElse: () => groceries);
}

/// Movimiento de dinero en una cuenta.
@immutable
class Transaction {
  const Transaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.kind,
    required this.accountId,
    required this.categoryId,
    required this.ownership,
    required this.date,
    this.needsReview = false,
    this.note,
    this.source = TransactionSource.synced,
  });

  final String id;

  /// Comercio o persona.
  final String title;

  /// Siempre positivo; el sentido lo da [kind].
  final int amount;
  final TransactionKind kind;
  final String accountId;
  final String categoryId;
  final Ownership ownership;
  final DateTime date;

  /// Traslado detectado que la persona debe confirmar.
  final bool needsReview;
  final String? note;
  final TransactionSource source;

  Category get category => Categories.byId(categoryId);

  /// Efecto en el saldo de la cuenta (negativo si sale).
  int get signedAmount => kind == TransactionKind.income ? amount : -amount;

  bool get canDelete => source != TransactionSource.synced;

  /// `note: ''` borra la nota.
  Transaction copyWith({
    TransactionKind? kind,
    String? categoryId,
    Ownership? ownership,
    bool? needsReview,
    String? note,
  }) => Transaction(
    id: id,
    title: title,
    amount: amount,
    kind: kind ?? this.kind,
    accountId: accountId,
    categoryId: categoryId ?? this.categoryId,
    ownership: ownership ?? this.ownership,
    date: date,
    needsReview: needsReview ?? this.needsReview,
    note: note == null ? this.note : (note.trim().isEmpty ? null : note.trim()),
    source: source,
  );
}
