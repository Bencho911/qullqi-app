import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/q_button.dart';

/// Abre una hoja inferior con título. Se cierra arrastrando, tocando fuera o
/// con el botón atrás del sistema.
Future<T?> showQSheet<T>(
  BuildContext context, {
  required String title,
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    // Encima de todo, incluida la barra de pestañas: mientras la hoja está
    // abierta nada de atrás se puede tocar.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: AppMotion.reduced(context)
        ? AnimationStyle.noAnimation
        : null,
    builder: (context) => _SheetBody(title: title, child: builder(context)),
  );
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bottom =
        MediaQuery.viewInsetsOf(context).bottom +
        MediaQuery.paddingOf(context).bottom;
    final content = Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpace.gutter,
        0,
        AppSpace.gutter,
        AppSpace.lg + bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: context.text.headlineSmall),
          ),
          const SizedBox(height: AppSpace.md),
          child,
        ],
      ),
    );
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: title,
      explicitChildNodes: true,
      // Siempre desplazable: con texto grande o pantallas bajas, el
      // contenido nunca se corta.
      child: SingleChildScrollView(child: content),
    );
  }
}

/// Confirmación de una acción que no se puede deshacer. El botón nombra lo
/// que se va a perder ("Eliminar Éxito Chapinero"). Devuelve `true` si se
/// confirma.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Mejor no',
}) async {
  final ok = await showQSheet<bool>(
    context,
    title: title,
    builder: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          message,
          style: AppTypography.body.copyWith(color: context.colors.inkMuted),
        ),
        const SizedBox(height: AppSpace.lg),
        QButton.danger(
          label: confirmLabel,
          onPressed: () {
            unawaited(HapticFeedback.mediumImpact());
            Navigator.of(context).pop(true);
          },
        ),
        const SizedBox(height: AppSpace.xs),
        QButton.secondary(
          label: cancelLabel,
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Opción de una lista de selección.
class PickOption<T> {
  const PickOption({
    required this.value,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
  });

  final T value;
  final String title;
  final String? subtitle;
  final String? trailing;
  final Widget? leading;
}

/// Hoja con una lista de opciones de selección única. Devuelve la elegida.
Future<T?> pickFromSheet<T>(
  BuildContext context, {
  required String title,
  required List<PickOption<T>> options,
  T? selected,
}) {
  return showQSheet<T>(
    context,
    title: title,
    builder: (context) {
      final c = context.colors;
      return Column(
        children: [
          for (final o in options)
            Semantics(
              inMutuallyExclusiveGroup: true,
              selected: o.value == selected,
              button: true,
              child: InkWell(
                borderRadius: AppRadius.controlAll,
                onTap: () {
                  unawaited(HapticFeedback.selectionClick());
                  Navigator.of(context).pop(o.value);
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: AppSize.row),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpace.xs,
                      horizontal: AppSpace.xxs,
                    ),
                    child: Row(
                      children: [
                        if (o.leading != null) ...[
                          o.leading!,
                          const SizedBox(width: AppSpace.sm),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                o.title,
                                style: AppTypography.body.copyWith(
                                  color: c.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (o.subtitle != null)
                                Text(
                                  o.subtitle!,
                                  style: AppTypography.caption.copyWith(
                                    color: c.inkSubtle,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (o.trailing != null) ...[
                          const SizedBox(width: AppSpace.sm),
                          Text(
                            o.trailing!,
                            style: AppTypography.body.copyWith(
                              color: c.ink,
                              fontWeight: FontWeight.w600,
                              fontFeatures: AppTypography.tabular,
                            ),
                          ),
                        ],
                        const SizedBox(width: AppSpace.sm),
                        Icon(
                          o.value == selected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: o.value == selected
                              ? c.primary
                              : c.outlineStrong,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// Protege un formulario: si hay algo escrito, cerrar (o "atrás") pregunta
/// antes de descartarlo.
class DiscardGuard extends StatelessWidget {
  const DiscardGuard({
    required this.dirty,
    required this.title,
    required this.confirmLabel,
    required this.child,
    super.key,
    this.message = 'No se guarda nada de lo que escribiste.',
  });

  /// Si hay algo que se perdería (y no se está guardando).
  final bool dirty;

  /// "¿Descartar esta meta?".
  final String title;

  /// "Descartar meta".
  final String confirmLabel;
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final ok = await confirmDestructive(
          context,
          title: title,
          message: message,
          confirmLabel: confirmLabel,
          cancelLabel: 'Seguir editando',
        );
        if (ok) nav.pop();
      },
      child: child,
    );
  }
}
