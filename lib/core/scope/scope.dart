/// Vista activa de la app. Filtra cuentas, movimientos y planes a la vez.
enum Scope {
  all('Todo'),
  personal('Personal'),
  business('Negocio');

  Scope(this.label);

  final String label;
}

/// Ámbito de un dato (una cuenta o un movimiento pertenece a uno solo).
enum Ownership {
  personal('Personal'),
  business('Negocio');

  Ownership(this.label);

  final String label;

  bool visibleIn(Scope scope) => switch (scope) {
    Scope.all => true,
    Scope.personal => this == Ownership.personal,
    Scope.business => this == Ownership.business,
  };
}
