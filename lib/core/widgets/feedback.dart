import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/q_button.dart';

enum ProgressTone { ok, warning, danger }

Color _toneColor(BuildContext context, ProgressTone tone) {
  final c = context.colors;
  return switch (tone) {
    ProgressTone.ok => c.primary,
    ProgressTone.warning => c.warning,
    ProgressTone.danger => c.danger,
  };
}

/// Barra de progreso que se llena al aparecer (o al instante si se reduce el
/// movimiento). [value] va de 0 a 1; por encima de 1 se dibuja llena.
class QProgressBar extends StatelessWidget {
  const QProgressBar({
    required this.value,
    required this.semanticLabel,
    super.key,
    this.tone = ProgressTone.ok,
    this.height = 8,
  });

  final double value;
  final String semanticLabel;
  final ProgressTone tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final v = value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(value * 100).round()} %',
      child: ClipRRect(
        borderRadius: AppRadius.pill,
        child: SizedBox(
          height: height,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: v),
            duration: AppMotion.of(context, AppMotion.emphasized * 2),
            curve: AppMotion.emphasizedCurve,
            builder: (context, t, _) => LinearProgressIndicator(
              value: t,
              minHeight: height,
              color: _toneColor(context, tone),
              backgroundColor: c.surfaceSunken,
            ),
          ),
        ),
      ),
    );
  }
}

/// Anillo de progreso para metas, con contenido en el centro.
class QProgressRing extends StatelessWidget {
  const QProgressRing({
    required this.value,
    required this.semanticLabel,
    super.key,
    this.size = 64,
    this.child,
  });

  final double value;
  final String semanticLabel;
  final double size;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: semanticLabel,
      value: '${(value * 100).round()} %',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
          duration: AppMotion.of(context, AppMotion.emphasized * 2),
          curve: AppMotion.emphasizedCurve,
          builder: (context, t, inner) => CustomPaint(
            painter: _RingPainter(t, c.primary, c.surfaceSunken),
            child: Center(child: inner),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t, this.color, this.track);

  final double t;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 6.0;
    final rect = (Offset.zero & size).deflate(stroke / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawArc(rect, 0, math.pi * 2, false, p..color = track)
      ..drawArc(rect, -math.pi / 2, math.pi * 2 * t, false, p..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.t != t || old.color != color || old.track != track;
}

/// Estado vacío: qué pasa, por qué importa y qué hacer.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
    this.actionLabel,
    this.onAction,
    this.secondaryLabel,
    this.onSecondary,
    this.iconBackground,
    this.iconColor,
    this.celebrate = false,
  });

  final IconData icon;

  /// Colores del círculo (por defecto, verde suave). Para resultados:
  /// éxito, en proceso o error.
  final Color? iconBackground;
  final Color? iconColor;

  /// El ícono entra con un pequeño crecimiento (momento de logro).
  final bool celebrate;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
      child: Column(
        children: [
          ExcludeSemantics(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: celebrate ? 0.8 : 1, end: 1),
              duration: AppMotion.of(context, AppMotion.emphasized),
              curve: AppMotion.emphasizedCurve,
              builder: (context, s, child) =>
                  Transform.scale(scale: s, child: child),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: iconBackground ?? c.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 30,
                  color: iconColor ?? c.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: context.text.titleMedium,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: c.inkMuted),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpace.lg),
            QButton(label: actionLabel!, onPressed: onAction),
          ],
          if (secondaryLabel != null) ...[
            const SizedBox(height: AppSpace.xs),
            QButton.text(label: secondaryLabel!, onPressed: onSecondary),
          ],
        ],
      ),
    );
  }
}

/// Bloque de carga con un pulso suave (sin pulso si se reduce el movimiento).
class SkeletonBlock extends StatefulWidget {
  const SkeletonBlock({
    super.key,
    this.width = double.infinity,
    this.height = 16,
    this.radius = AppRadius.chip,
  });

  final double width;
  final double height;
  final double radius;

  @override
  State<SkeletonBlock> createState() => _SkeletonBlockState();
}

class _SkeletonBlockState extends State<SkeletonBlock>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(c.surfaceMuted, c.surfaceSunken, _c.value),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

/// Aviso breve abajo, con vibración ligera de confirmación.
void showQToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  unawaited(HapticFeedback.lightImpact());
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel == null
            ? null
            : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
}

/// Pantalla apilada que solo muestra un mensaje (no existe, error):
/// desplazable y dentro del área segura para que nunca se desborde.
class MessageBody extends StatelessWidget {
  const MessageBody({required this.child, super.key});

  final EmptyState child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
        children: [child],
      ),
    );
  }
}

/// Carga genérica de una pantalla apilada: un título y filas.
class PageSkeleton extends StatelessWidget {
  const PageSkeleton({required this.label, super.key, this.rows = 4});

  /// Lo que anuncia el lector ("Cargando el movimiento").
  final String label;
  final int rows;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      liveRegion: true,
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.gutter,
          vertical: AppSpace.xs,
        ),
        children: [
          const SkeletonBlock(height: AppSize.avatarLg, width: 220),
          const SizedBox(height: AppSpace.lg),
          for (var i = 0; i < rows; i++) ...[
            const SkeletonBlock(height: AppSize.rowAmount),
            const SizedBox(height: AppSpace.xs),
          ],
        ],
      ),
    );
  }
}

/// Pantalla de espera de una operación con el banco ("Conectando…",
/// "Moviendo…"): rueda, qué pasa y cuánto puede tardar.
class BusyMessage extends StatelessWidget {
  const BusyMessage({required this.title, super.key, this.message});

  final String title;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: title,
      excludeSemantics: true,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpace.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox.square(
                dimension: AppSize.avatarLg,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: AppSpace.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: context.text.titleMedium,
              ),
              if (message != null) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: context.text.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
