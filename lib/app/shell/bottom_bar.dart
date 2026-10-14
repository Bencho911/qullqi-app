import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';

/// Destino de la barra inferior.
class BarDestination {
  const BarDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Barra inferior: dos pestañas, el botón "+" al centro y dos pestañas.
///
/// El "+" queda en la zona del pulgar porque registrar o mover plata es la
/// acción más frecuente. Respeta el área segura inferior (indicador de inicio
/// en iOS, barra de gestos en Android).
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    required this.onAdd,
    super.key,
  }) : assert(destinations.length == 4, 'La barra tiene 4 pestañas');

  final List<BarDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget tab(int i) => Expanded(
      child: _TabItem(
        destination: destinations[i],
        selected: i == selectedIndex,
        index: i,
        count: destinations.length,
        onTap: () => onSelect(i),
      ),
    );

    // Como las barras nativas, limita cuánto crece el texto (máx. 130 %): el
    // lector de pantalla igual lee el nombre completo de cada pestaña.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.outline)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.xs,
              vertical: AppSpace.xxs,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tab(0),
                tab(1),
                Expanded(
                  child: Center(
                    heightFactor: 1,
                    child: _AddButton(onTap: onAdd),
                  ),
                ),
                tab(2),
                tab(3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Indicador de la pestaña activa (forma de píldora de Material 3).
const double _indicatorWide = 56;
const double _indicatorNarrow = 40;
const double _indicatorHeight = 32;

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.destination,
    required this.selected,
    required this.index,
    required this.count,
    required this.onTap,
  });

  final BarDestination destination;
  final bool selected;
  final int index;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = selected ? c.onPrimaryContainer : c.inkMuted;
    return Semantics(
      selected: selected,
      button: true,
      label: '${destination.label}, pestaña ${index + 1} de $count',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.controlAll,
        onTap: () {
          unawaited(HapticFeedback.selectionClick());
          onTap();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSize.row),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: AppMotion.of(context, AppMotion.standard),
                curve: AppMotion.emphasizedCurve,
                width: selected ? _indicatorWide : _indicatorNarrow,
                height: _indicatorHeight,
                decoration: BoxDecoration(
                  color: selected ? c.primaryContainer : Colors.transparent,
                  borderRadius: AppRadius.pill,
                ),
                child: Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: AppSize.icon,
                  color: color,
                ),
              ),
              const SizedBox(height: AppSpace.xxs),
              // "Movimientos" no cabe en pantallas angostas: se reduce un poco
              // en vez de cortarse.
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  destination.label,
                  maxLines: 1,
                  style: AppTypography.label.copyWith(
                    color: selected ? c.ink : c.inkMuted,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.xxs),
      child: Tooltip(
        message: 'Registrar o mover plata',
        child: Semantics(
          button: true,
          label: 'Registrar o mover plata',
          excludeSemantics: true,
          child: Material(
            color: c.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () {
                unawaited(HapticFeedback.lightImpact());
                onTap();
              },
              child: SizedBox.square(
                dimension: AppSize.control,
                child: Icon(
                  Icons.add_rounded,
                  size: AppSize.iconLg,
                  color: c.onPrimary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
