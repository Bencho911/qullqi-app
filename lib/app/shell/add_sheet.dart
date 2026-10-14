import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/widgets/widgets.dart';

class _AddAction {
  const _AddAction(this.title, this.subtitle, this.icon, this.route);

  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
}

const _actions = [
  _AddAction(
    'Mover plata',
    'Entre tus cuentas, con tu confirmación',
    Icons.swap_horiz_rounded,
    Routes.moveMoney,
  ),
  _AddAction(
    'Registrar gasto',
    'Efectivo o una cuenta sin conexión',
    Icons.north_east_rounded,
    Routes.addExpense,
  ),
  _AddAction(
    'Registrar ingreso',
    'Un pago que recibiste',
    Icons.south_west_rounded,
    Routes.addIncome,
  ),
  _AddAction(
    'Escanear factura',
    'Leemos el valor, el comercio y el NIT por ti',
    Icons.document_scanner_outlined,
    Routes.scanReceipt,
  ),
  _AddAction(
    'Importar extracto',
    'PDF, Excel o CSV que descargas de tu banco',
    Icons.upload_file_rounded,
    Routes.importStatement,
  ),
];

/// Hoja del botón "+": las cosas que se pueden hacer con la plata.
Future<void> showAddSheet(BuildContext context) async {
  final route = await showQSheet<String>(
    context,
    title: '¿Qué quieres hacer?',
    builder: (context) => Column(
      children: [
        for (final (i, a) in _actions.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpace.xs),
          OptionRow(
            icon: a.icon,
            title: a.title,
            subtitle: a.subtitle,
            // Mover plata es la acción principal de la app: va primero y
            // resaltada.
            emphasized: i == 0,
            onTap: () => Navigator.of(context).pop(a.route),
          ),
        ],
      ],
    ),
  );
  if (route != null && context.mounted) await context.push(route);
}
