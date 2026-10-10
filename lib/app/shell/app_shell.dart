import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/shell/add_sheet.dart';
import 'package:qullqi/app/shell/bottom_bar.dart';
import 'package:qullqi/core/theme/app_tokens.dart';

const _destinations = [
  BarDestination(
    label: 'Inicio',
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
  ),
  BarDestination(
    label: 'Movimientos',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long_rounded,
  ),
  BarDestination(
    label: 'Planes',
    icon: Icons.pie_chart_outline_rounded,
    selectedIcon: Icons.pie_chart_rounded,
  ),
  BarDestination(
    label: 'Cuentas',
    icon: Icons.account_balance_wallet_outlined,
    selectedIcon: Icons.account_balance_wallet_rounded,
  ),
];

/// Marco de las pestañas: contenido + barra inferior.
///
/// - Tocar la pestaña activa vuelve a su pantalla inicial.
/// - En Android, "atrás" desde otra pestaña vuelve a Inicio antes de salir.
class AppShell extends StatelessWidget {
  const AppShell({
    required this.navigationShell,
    required this.children,
    super.key,
  });

  final StatefulNavigationShell navigationShell;
  final List<Widget> children;

  void _select(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final index = navigationShell.currentIndex;
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _select(0);
      },
      child: Scaffold(
        body: _FadeIndexedStack(index: index, children: children),
        bottomNavigationBar: AppBottomBar(
          destinations: _destinations,
          selectedIndex: index,
          onSelect: _select,
          onAdd: () => showAddSheet(context),
        ),
      ),
    );
  }
}

/// Mantiene vivas las pestañas (conservan scroll e historial) y funde la que
/// entra en 200 ms. Sin animación si se reduce el movimiento.
class _FadeIndexedStack extends StatefulWidget {
  const _FadeIndexedStack({required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  State<_FadeIndexedStack> createState() => _FadeIndexedStackState();
}

class _FadeIndexedStackState extends State<_FadeIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
    value: 1,
  );

  @override
  void didUpdateWidget(_FadeIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      if (AppMotion.reduced(context)) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _c, curve: AppMotion.standardCurve),
      child: IndexedStack(
        index: widget.index,
        sizing: StackFit.expand,
        children: [
          for (final (i, child) in widget.children.indexed)
            // Las pestañas ocultas no reciben foco ni se leen.
            ExcludeFocus(excluding: i != widget.index, child: child),
        ],
      ),
    );
  }
}
