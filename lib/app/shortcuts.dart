import 'dart:async';

import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';

/// Clave en las preferencias donde Siri y la app Atajos anotan qué abrir.
const String pendingShortcutKey = 'pending_route';

/// Atajos de la app: los que salen al mantener presionado el ícono, los de la
/// app Atajos y Siri, y los que abren los widgets.
///
/// Todos comparten un identificador corto y un enlace
/// `inti:///atajo/<id>` que abre la pantalla correspondiente.
abstract final class AppShortcuts {
  static const addExpense = 'registrar-gasto';
  static const addIncome = 'registrar-ingreso';
  static const moveMoney = 'mover-plata';
  static const scanReceipt = 'escanear-factura';
  static const importStatement = 'importar-extracto';
  static const available = 'disponible';
  static const payments = 'pagos';
  static const notices = 'avisos';

  /// Los que salen al mantener presionado el ícono (iOS muestra hasta 4).
  static const List<({String id, String title})> quickActions = [
    (id: addExpense, title: 'Registrar gasto'),
    (id: moveMoney, title: 'Mover plata'),
    (id: scanReceipt, title: 'Escanear factura'),
    (id: available, title: 'Ver mi disponible'),
  ];

  /// La pantalla a la que lleva cada atajo; `null` si no existe.
  static String? routeFor(String id) => switch (id) {
    addExpense => Routes.addExpense,
    addIncome => Routes.addIncome,
    moveMoney => Routes.moveMoney,
    scanReceipt => Routes.scanReceipt,
    importStatement => Routes.importStatement,
    available || payments => Routes.home,
    notices => Routes.notifications,
    _ => null,
  };

  /// Enlace que abre el atajo desde fuera de la app (widgets, Atajos).
  static String linkFor(String id) => 'inti:///atajo/$id';
}

/// Pestañas: se abren con `go`; lo demás se apila sobre el Inicio para que
/// al cerrar vuelva a algo.
const Set<String> _tabs = {
  Routes.home,
  Routes.transactions,
  Routes.planning,
  Routes.accounts,
};

/// Abre [route] de forma segura desde fuera de la pantalla actual (una
/// notificación, un atajo, un widget).
void openFromOutside(GoRouter router, String route) {
  if (_tabs.contains(route)) {
    router.go(route);
    return;
  }
  router.go(Routes.home);
  unawaited(router.push<void>(route));
}
