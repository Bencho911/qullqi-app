import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Símbolo de Inti ("sol" en quechua): un disco con ocho rayos cortos sobre
/// un cuadrado redondeado verde profundo. Es el mismo dibujo del ícono de la
/// app (ver `tool/make_icons.py`).
class IntiMark extends StatelessWidget {
  const IntiMark({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _MarkPainter()),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  static const _bg = Color(0xFF0B2A1F);
  static const _ray = Color(0xFF3CC594);
  static const _disc = Color(0xFF7FE3B8);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.3)),
      Paint()..color = _bg,
    );
    final center = Offset(s / 2, s / 2);
    final rays = Paint()
      ..color = _ray
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = s * 0.075;
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        center + dir * (s * 0.29),
        center + dir * (s * 0.39),
        rays,
      );
    }
    canvas.drawCircle(center, s * 0.19, Paint()..color = _disc);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Marca con nombre, para encabezados y bienvenida.
class IntiLockup extends StatelessWidget {
  const IntiLockup({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Inti',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IntiMark(size: size),
          SizedBox(width: size * 0.32),
          Text(
            'Inti',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
          ),
        ],
      ),
    );
  }
}
