import 'package:flutter/material.dart';

import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/basics.dart';
import 'package:qullqi/core/widgets/money_text.dart';

enum FlowKind { income, expense, transfer }

/// Estructura común de las filas con monto (movimientos, pagos):
/// ícono, título y detalles, y el monto a la derecha. Con texto grande el
/// monto baja bajo el título para que nada se parta a la mitad.
class AmountRowLayout extends StatelessWidget {
  const AmountRowLayout({
    required this.leading,
    required this.title,
    required this.details,
    required this.trailing,
    super.key,
    this.titleLines = 1,
  });

  final Widget leading;
  final String title;

  /// Líneas del título con texto normal (con texto grande, hasta 3).
  final int titleLines;
  final List<Widget> details;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final large = isLargeText(context);
    final titleText = Text(
      title,
      maxLines: large ? 3 : titleLines,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.body.copyWith(
        color: c.ink,
        fontWeight: FontWeight.w600,
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: AppSize.rowAmount),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: Row(
          crossAxisAlignment: large
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            leading,
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleText,
                  ...details,
                  if (large) ...[
                    const SizedBox(height: AppSpace.xxs),
                    trailing,
                  ],
                ],
              ),
            ),
            if (!large) ...[const SizedBox(width: AppSpace.sm), trailing],
          ],
        ),
      ),
    );
  }
}

/// Fila de movimiento: ícono, comercio, detalle y monto.
///
/// Gastos en tinta, ingresos en verde con "+", traslados en índigo sin signo.
/// El lector de pantalla oye una sola frase con todo.
class TransactionRow extends StatelessWidget {
  const TransactionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.kind,
    super.key,
    this.categoryLabel,
    this.pill,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Nombre de lo que representa el ícono (para el lector de pantalla).
  final String? categoryLabel;

  /// Siempre positivo; el signo lo pone [kind].
  final int amount;
  final FlowKind kind;
  final StatusPill? pill;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (tileBg, tileFg, amountColor) = switch (kind) {
      FlowKind.income => (c.primaryContainer, c.onPrimaryContainer, c.income),
      FlowKind.expense => (c.surfaceMuted, c.inkMuted, c.ink),
      FlowKind.transfer => (c.transferContainer, c.transfer, c.transfer),
    };
    final signed = switch (kind) {
      FlowKind.income => amount.abs(),
      FlowKind.expense => -amount.abs(),
      FlowKind.transfer => amount.abs(),
    };
    final kindWord = switch (kind) {
      FlowKind.income => 'Ingreso',
      FlowKind.expense => 'Gasto',
      FlowKind.transfer => 'Traslado',
    };
    final spoken = [
      title,
      kindWord,
      ?categoryLabel,
      Cop.spoken(amount.abs()),
      subtitle,
      if (pill != null) pill!.label,
    ].join('. ');

    return Semantics(
      button: onTap != null,
      label: spoken,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.controlAll,
        child: AmountRowLayout(
          leading: IconTile(icon: icon, background: tileBg, foreground: tileFg),
          title: title,
          details: [
            Text(
              subtitle,
              maxLines: isLargeText(context) ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(color: c.inkSubtle),
            ),
            // Las etiquetas de estado van bajo el detalle en todas las filas
            // con monto (igual que en PaymentRow).
            if (pill != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xxs),
                child: pill,
              ),
          ],
          trailing: MoneyText(
            signed,
            signed: kind == FlowKind.income,
            animate: false,
            style: AppTypography.body.copyWith(
              color: amountColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

enum SyncState { ok, syncing, reconnect }

/// Cuenta o tarjeta en lista: entidad, nombre, saldo y estado de conexión.
class AccountTile extends StatelessWidget {
  const AccountTile({
    required this.initials,
    required this.name,
    required this.detail,
    required this.balance,
    super.key,
    this.balanceLabel,
    this.sync = SyncState.ok,
    this.syncLabel,
    this.ownership,
    this.onTap,
  });

  final String initials;
  final String name;

  /// "Ahorros •• 4521".
  final String detail;
  final int balance;

  /// "Deuda" para tarjetas; por defecto no se muestra.
  final String? balanceLabel;
  final SyncState sync;
  final String? syncLabel;

  /// Etiqueta de ámbito; solo se muestra en la vista Todo.
  final StatusPill? ownership;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final needsAction = sync == SyncState.reconnect;
    final spoken = [
      name,
      detail,
      ?balanceLabel,
      Cop.spoken(balance),
      if (ownership != null) ownership!.label,
      ?syncLabel,
    ].join('. ');
    final large = isLargeText(context);
    return QCard(
      onTap: onTap,
      semanticLabel: spoken,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      // Misma estructura que las filas con monto: con texto grande el saldo
      // baja bajo el nombre y nada se parte a la mitad.
      child: ExcludeSemantics(
        child: AmountRowLayout(
          leading: InitialsAvatar(initials),
          title: name,
          titleLines: 2,
          details: [
            Text(
              detail,
              style: AppTypography.caption.copyWith(color: c.inkSubtle),
            ),
            if (ownership != null) ...[
              const SizedBox(height: AppSpace.xxs),
              ownership!,
            ],
            if (syncLabel != null) ...[
              const SizedBox(height: AppSpace.xxs),
              _SyncLine(state: sync, label: syncLabel!),
            ],
          ],
          trailing: Column(
            crossAxisAlignment: large
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              if (balanceLabel != null)
                Text(
                  balanceLabel!,
                  style: AppTypography.caption.copyWith(color: c.inkSubtle),
                ),
              MoneyText(
                balance,
                style: AppTypography.subtitle.copyWith(
                  color: needsAction ? c.inkMuted : c.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SyncLine extends StatelessWidget {
  const _SyncLine({required this.state, required this.label});

  final SyncState state;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, color) = switch (state) {
      SyncState.ok => (Icons.check_circle_rounded, c.income),
      SyncState.syncing => (Icons.sync_rounded, c.inkMuted),
      SyncState.reconnect => (Icons.error_rounded, c.warning),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: AppSpace.xxs),
        Flexible(
          child: Text(
            label,
            style: state == SyncState.reconnect
                ? AppTypography.label.copyWith(color: c.warning)
                : AppTypography.caption.copyWith(color: c.inkSubtle),
          ),
        ),
      ],
    );
  }
}

/// Fila de ajustes o de opción: ícono, título, detalle y acción final.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.title,
    super.key,
    this.icon,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  final String title;
  final IconData? icon;

  /// En lugar de [icon], p. ej. las iniciales de un banco.
  final Widget? leading;

  /// `false` la muestra atenuada y sin acción (p. ej. "Muy pronto").
  final bool enabled;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MergeSemantics(
      child: ListTile(
        onTap: enabled ? onTap : null,
        enabled: enabled,
        // Sin margen propio: se alinea con el margen lateral de la pantalla.
        contentPadding: EdgeInsets.zero,
        minTileHeight: AppSize.row,
        leading:
            leading ?? (icon == null ? null : Icon(icon, color: c.inkMuted)),
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing:
            trailing ??
            (onTap != null && enabled
                ? Icon(Icons.chevron_right_rounded, color: c.inkSubtle)
                : null),
      ),
    );
  }
}

/// Opción tocable en tarjeta: ícono, título, explicación y chevron.
/// Se usa en hojas de acciones y listas de caminos posibles.
class OptionRow extends StatelessWidget {
  const OptionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
    this.emphasized = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Resalta el ícono en verde: la opción recomendada o principal.
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return QCard(
      semanticLabel: '$title. $subtitle',
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.sm,
      ),
      child: ExcludeSemantics(
        child: Row(
          children: [
            IconTile(
              icon: icon,
              background: emphasized ? c.primaryContainer : null,
              foreground: emphasized ? c.onPrimaryContainer : null,
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.body.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: AppTypography.caption.copyWith(color: c.inkSubtle),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: c.inkSubtle),
          ],
        ),
      ),
    );
  }
}

/// Interruptor con título y explicación, alineado al margen de la pantalla.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool value;

  /// `null` lo deja deshabilitado (explica el porqué en [subtitle]).
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Casilla de aceptación (términos, autorizaciones), alineada al margen.
class CheckRow extends StatelessWidget {
  const CheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
      // Sin el margen extra del ícono: el texto queda alineado al bloque.
      visualDensity: const VisualDensity(
        horizontal: VisualDensity.minimumDensity,
      ),
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      title: Text(label, style: context.text.bodyMedium),
    );
  }
}

/// Fila "etiqueta → valor" dentro de una tarjeta de resumen.
class DetailLine extends StatelessWidget {
  const DetailLine(this.label, this.value, {super.key, this.emphasis = false});

  final String label;
  final String value;

  /// Resalta el total (p. ej. "Disponible para gastar").
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labelStyle = emphasis
        ? AppTypography.subtitle.copyWith(color: c.ink)
        : AppTypography.body.copyWith(color: c.inkMuted);
    final valueStyle = (emphasis ? AppTypography.subtitle : AppTypography.body)
        .copyWith(
          color: c.ink,
          fontWeight: emphasis ? FontWeight.w700 : FontWeight.w600,
          fontFeatures: AppTypography.tabular,
        );
    // Con texto grande el valor baja bajo la etiqueta: una cifra nunca se
    // parte en dos líneas.
    if (isLargeText(context)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
        child: MergeSemantics(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label, style: labelStyle),
              Text(value, style: valueStyle),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label, style: labelStyle)),
            const SizedBox(width: AppSpace.md),
            // Align llena el espacio libre: el valor queda pegado a la
            // derecha y, si es largo, baja de línea sin desbordarse.
            Flexible(
              child: Align(
                alignment: AlignmentDirectional.topEnd,
                child: Text(value, textAlign: TextAlign.end, style: valueStyle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nota de confianza con candado ("Nunca guardamos tus claves…").
class TrustNote extends StatelessWidget {
  const TrustNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(
            Icons.lock_outline_rounded,
            size: AppSize.iconSm,
            color: c.inkSubtle,
          ),
        ),
        const SizedBox(width: AppSpace.xs),
        Expanded(child: Text(text, style: context.text.bodySmall)),
      ],
    );
  }
}
