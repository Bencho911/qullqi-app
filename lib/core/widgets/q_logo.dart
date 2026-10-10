import 'package:flutter/material.dart';

/// Símbolo de Qullqi: una "Q" geométrica cuya cola es un brote
/// ("plata que crece") sobre un cuadrado redondeado verde profundo.
class QullqiMark extends StatelessWidget {
  const QullqiMark({super.key, this.size = 32});

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
  static const _ring = Color(0xFF3CC594);
  static const _leaf = Color(0xFF7FE3B8);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.3)),
      Paint()..color = _bg,
    );
    final stroke = s * 0.11;
    final center = Offset(s * 0.47, s * 0.46);
    canvas.drawCircle(
      center,
      s * 0.22,
      Paint()
        ..color = _ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );
    // Brote: una hoja que sale de la base del anillo hacia abajo a la derecha.
    final leaf = Path()
      ..moveTo(s * 0.55, s * 0.62)
      ..quadraticBezierTo(s * 0.80, s * 0.58, s * 0.80, s * 0.82)
      ..quadraticBezierTo(s * 0.58, s * 0.84, s * 0.55, s * 0.62)
      ..close();
    canvas.drawPath(leaf, Paint()..color = _leaf);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Marca con nombre, para encabezados y bienvenida.
class QullqiLockup extends StatelessWidget {
  const QullqiLockup({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Qullqi',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          QullqiMark(size: size),
          SizedBox(width: size * 0.32),
          Text(
            'Qullqi',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
          ),
        ],
      ),
    );
  }
}
