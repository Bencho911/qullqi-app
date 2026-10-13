import 'package:flutter/material.dart';

import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/networth/domain/net_worth_history.dart';

/// Gráfica de línea del patrimonio. Tocando o arrastrando el dedo se ve el
/// valor de cada día; el lector de pantalla oye un resumen.
class NetWorthChart extends StatefulWidget {
  const NetWorthChart({required this.points, super.key, this.height = 180});

  final List<NetWorthPoint> points;
  final double height;

  @override
  State<NetWorthChart> createState() => _NetWorthChartState();
}

class _NetWorthChartState extends State<NetWorthChart> {
  int? _selected;

  void _pick(double dx, double width) {
    final n = widget.points.length;
    if (n < 2 || width <= 0) return;
    final i = (dx / width * (n - 1)).round().clamp(0, n - 1);
    setState(() => _selected = i);
  }

  @override
  void didUpdateWidget(NetWorthChart old) {
    super.didUpdateWidget(old);
    // Al cambiar de rango la selección ya no apunta a nada.
    if (old.points.length != widget.points.length) _selected = null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final points = widget.points;
    if (points.length < 2) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: Text('Aún no hay suficiente historia.')),
      );
    }
    final first = points.first;
    final last = points.last;
    final shown = _selected == null ? last : points[_selected!];
    final summary =
        'Gráfica de tu patrimonio. El ${Dates.dayMonth(first.date)} era '
        '${Cop.spoken(first.value)}. Hoy es ${Cop.spoken(last.value)}.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _selected == null
                      ? 'Hoy · ${Cop.format(shown.value)}'
                      : '${Dates.dayMonth(shown.date)} · '
                            '${Cop.format(shown.value)}',
                  style: AppTypography.label.copyWith(color: c.ink),
                ),
              ),
            ),
            if (_selected != null)
              QButton.text(
                label: 'Ver hoy',
                onPressed: () => setState(() => _selected = null),
              ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        Semantics(
          label: summary,
          image: true,
          excludeSemantics: true,
          child: SizedBox(
            height: widget.height,
            child: LayoutBuilder(
              builder: (context, box) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _pick(d.localPosition.dx, box.maxWidth),
                onHorizontalDragUpdate: (d) =>
                    _pick(d.localPosition.dx, box.maxWidth),
                child: CustomPaint(
                  size: Size(box.maxWidth, widget.height),
                  painter: _ChartPainter(
                    values: [for (final p in points) p.value],
                    selected: _selected,
                    line: c.primary,
                    area: c.primaryContainer,
                    grid: c.outline,
                    dot: c.primary,
                    ring: c.surface,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(Dates.dayMonth(first.date), style: context.text.bodySmall),
            Text('Hoy', style: context.text.bodySmall),
          ],
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.values,
    required this.selected,
    required this.line,
    required this.area,
    required this.grid,
    required this.dot,
    required this.ring,
  });

  final List<int> values;
  final int? selected;
  final Color line;
  final Color area;
  final Color grid;
  final Color dot;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final n = values.length;
    if (n < 2) return;
    var lo = values.reduce((a, b) => a < b ? a : b).toDouble();
    var hi = values.reduce((a, b) => a > b ? a : b).toDouble();
    if (hi == lo) {
      hi += 1;
      lo -= 1;
    }
    final pad = (hi - lo) * 0.12;
    lo -= pad;
    hi += pad;
    double x(int i) => size.width * i / (n - 1);
    double y(int v) => size.height * (1 - (v - lo) / (hi - lo));

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var g = 0; g < 3; g++) {
      final gy = size.height * g / 2;
      canvas.drawLine(Offset(0, gy), Offset(size.width, gy), gridPaint);
    }

    final path = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < n; i++) {
      path.lineTo(x(i), y(values[i]));
    }
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas
      ..drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [area, area.withValues(alpha: 0)],
          ).createShader(Offset.zero & size),
      )
      ..drawPath(
        path,
        Paint()
          ..color = line
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );

    final s = selected ?? n - 1;
    final p = Offset(x(s), y(values[s]));
    if (selected != null) {
      canvas.drawLine(
        Offset(p.dx, 0),
        Offset(p.dx, size.height),
        Paint()
          ..color = line.withValues(alpha: 0.4)
          ..strokeWidth = 1.5,
      );
    }
    canvas
      ..drawCircle(p, 7, Paint()..color = ring)
      ..drawCircle(p, 4.5, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_ChartPainter old) =>
      old.values != values ||
      old.selected != selected ||
      old.line != line ||
      old.area != area;
}
