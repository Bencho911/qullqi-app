import 'package:flutter/material.dart';

import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';

enum QButtonVariant { primary, secondary, text, danger }

/// Botón de Qullqi. Los textos empiezan por verbo ("Guardar gasto",
/// nunca "OK").
///
/// Con [loading] el botón queda ocupado, conserva su ancho y anuncia
/// [loadingLabel] al lector de pantalla.
class QButton extends StatelessWidget {
  const QButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.variant = QButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.loadingLabel = 'Procesando',
    this.expand = true,
  }) : color = null;

  const QButton.secondary({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.loading = false,
    this.loadingLabel = 'Procesando',
    this.expand = true,
  }) : variant = QButtonVariant.secondary,
       color = null;

  const QButton.text({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.expand = false,
    this.color,
  }) : variant = QButtonVariant.text,
       loading = false,
       loadingLabel = '';

  const QButton.danger({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.loading = false,
    this.loadingLabel = 'Procesando',
    this.expand = true,
  }) : variant = QButtonVariant.danger,
       color = null;

  final String label;
  final VoidCallback? onPressed;
  final QButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final String loadingLabel;
  final bool expand;

  /// Color del texto (solo [QButton.text], p. ej. dentro de un aviso).
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final onTap = loading ? null : onPressed;
    final filled =
        variant == QButtonVariant.primary || variant == QButtonVariant.danger;
    final child = loading
        ? Stack(
            alignment: Alignment.center,
            children: [
              // El texto invisible conserva el ancho del botón mientras carga.
              ExcludeSemantics(
                child: Opacity(
                  opacity: 0,
                  child: _Label(label: label, icon: icon),
                ),
              ),
              Semantics(
                liveRegion: true,
                label: loadingLabel,
                child: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: filled ? c.onPrimary : c.primary,
                  ),
                ),
              ),
            ],
          )
        : _Label(label: label, icon: icon);

    final Widget button = switch (variant) {
      QButtonVariant.primary => FilledButton(onPressed: onTap, child: child),
      QButtonVariant.danger => FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: c.danger,
          foregroundColor: c.onDanger,
        ),
        child: child,
      ),
      QButtonVariant.secondary => OutlinedButton(
        onPressed: onTap,
        child: child,
      ),
      QButtonVariant.text => TextButton(
        onPressed: onTap,
        style: color == null
            ? null
            : TextButton.styleFrom(foregroundColor: color),
        child: child,
      ),
    };
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = Flexible(
      child: Text(label, textAlign: TextAlign.center, maxLines: 2),
    );
    if (icon == null) {
      return Row(mainAxisSize: MainAxisSize.min, children: [text]);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppSize.iconSm),
        const SizedBox(width: AppSpace.xs),
        text,
      ],
    );
  }
}
