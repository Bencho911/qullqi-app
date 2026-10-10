import 'package:flutter/material.dart';

import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/q_button.dart';

enum BannerTone { warning, danger, info }

/// Aviso dentro de la página con una acción (p. ej. "Reconectar").
/// El color nunca va solo: siempre hay ícono y texto.
class QBanner extends StatelessWidget {
  const QBanner({
    required this.title,
    required this.message,
    super.key,
    this.tone = BannerTone.warning,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final BannerTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg, icon) = switch (tone) {
      BannerTone.warning => (
        c.warningContainer,
        c.warning,
        Icons.sync_problem_rounded,
      ),
      BannerTone.danger => (
        c.dangerContainer,
        c.onDangerContainer,
        Icons.error_outline_rounded,
      ),
      BannerTone.info => (
        c.primaryContainer,
        c.onPrimaryContainer,
        Icons.info_outline_rounded,
      ),
    };
    final large = isLargeText(context);
    final button = actionLabel == null
        ? null
        : QButton.text(label: actionLabel!, onPressed: onAction, color: fg);
    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: bg, borderRadius: AppRadius.cardAll),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.md,
            AppSpace.sm,
            AppSpace.xs,
            AppSpace.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(child: Icon(icon, color: fg)),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.label.copyWith(color: fg),
                        ),
                        Text(
                          message,
                          style: AppTypography.caption.copyWith(color: fg),
                        ),
                      ],
                    ),
                  ),
                  if (button != null && !large) button,
                ],
              ),
              // Con texto grande la acción baja a su propia línea.
              if (button != null && large)
                Padding(
                  // Alineado con el texto: ícono (24) + espacio (12).
                  padding: const EdgeInsets.only(left: 24 + AppSpace.sm),
                  child: button,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
