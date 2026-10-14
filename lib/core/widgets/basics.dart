import 'package:flutter/material.dart';

import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/q_button.dart';

/// Superficie con borde fino. Es la tarjeta estándar: sin sombra.
class QCard extends StatelessWidget {
  const QCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(AppSpace.md),
    this.onTap,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = Padding(padding: padding, child: child);
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      container: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: c.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

enum PillTone { neutral, primary, warning, danger, transfer, business }

/// Etiqueta corta de estado. El color nunca es la única señal: siempre
/// lleva texto.
class StatusPill extends StatelessWidget {
  const StatusPill(
    this.label, {
    super.key,
    this.tone = PillTone.neutral,
    this.icon,
  });

  final String label;
  final PillTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = switch (tone) {
      PillTone.neutral => (c.surfaceMuted, c.inkMuted),
      PillTone.primary => (c.primaryContainer, c.onPrimaryContainer),
      PillTone.warning => (c.warningContainer, c.warning),
      PillTone.danger => (c.dangerContainer, c.onDangerContainer),
      PillTone.transfer => (c.transferContainer, c.transfer),
      PillTone.business => (c.businessContainer, c.business),
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.pill),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xs,
          vertical: 2,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: AppSpace.xxs),
            ],
            // Con texto grande la etiqueta baja de línea en vez de cortarse.
            Flexible(
              child: Text(
                label,
                style: AppTypography.label.copyWith(color: fg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Título de sección con acción opcional a la derecha ("Ver todo").
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.action,
    this.onAction,
    this.actionSemantics,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  /// Texto completo para el lector de pantalla ("Ver todos los movimientos").
  final String? actionSemantics;

  @override
  Widget build(BuildContext context) {
    final heading = Semantics(
      header: true,
      child: Text(title, style: context.text.titleMedium),
    );
    final button = action == null
        ? null
        : Semantics(
            label: actionSemantics,
            excludeSemantics: actionSemantics != null,
            button: true,
            child: QButton.text(label: action!, onPressed: onAction),
          );
    // Con texto grande la acción baja de línea y el título no se parte.
    if (isLargeText(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          // Compensa el relleno propio del botón para alinearlo al título.
          if (button != null)
            Transform.translate(
              offset: const Offset(-AppSpace.sm, 0),
              child: button,
            ),
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: heading),
        ?button,
      ],
    );
  }
}

/// Ícono dentro de un cuadro de color suave (categorías, cuentas).
class IconTile extends StatelessWidget {
  const IconTile({
    required this.icon,
    super.key,
    this.background,
    this.foreground,
    this.size = AppSize.leading,
  });

  final IconData icon;
  final Color? background;
  final Color? foreground;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? c.surfaceMuted,
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: size * 0.5, color: foreground ?? c.inkMuted),
      ),
    );
  }
}

/// Iniciales de una entidad (banco, persona) en un círculo.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(
    this.initials, {
    super.key,
    this.size = AppSize.leading,
    this.background,
    this.foreground,
  });

  final String initials;
  final double size;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? c.surfaceMuted,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: AppTypography.label.copyWith(
            color: foreground ?? c.inkMuted,
            fontWeight: FontWeight.w700,
          ),
          textScaler: TextScaler.noScaling,
        ),
      ),
    );
  }
}

/// Mensaje breve dentro de una sección vacía ("No tienes pagos…").
/// Para pantallas enteras sin contenido se usa `EmptyState`.
class SectionNote extends StatelessWidget {
  const SectionNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Text(
        text,
        style: context.text.bodyMedium?.copyWith(
          color: context.colors.inkMuted,
        ),
      ),
    );
  }
}
