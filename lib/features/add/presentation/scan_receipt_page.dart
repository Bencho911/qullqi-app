import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';
import 'package:inti/core/data/latency.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/add/presentation/add_transaction_page.dart';

/// Lee una factura y abre "Registrar gasto" con lo leído para revisarlo.
///
/// La lectura es una interfaz: hoy devuelve una factura de ejemplo; la
/// versión con cámara (`image_picker` + reconocimiento de texto) la
/// reemplaza sin tocar esta pantalla.
abstract interface class ReceiptReader {
  Future<AddPrefill> read();
}

final receiptReaderProvider = Provider<ReceiptReader>(
  (ref) => _SampleReceiptReader(ref.watch(mockLatencyProvider)),
);

class _SampleReceiptReader implements ReceiptReader {
  _SampleReceiptReader(this.latency);

  final Duration latency;

  @override
  Future<AddPrefill> read() async {
    await Future<void>.delayed(latency * 2);
    return const AddPrefill(
      amount: 85400,
      title: 'Éxito Calle 80',
      categoryId: 'mercado',
      note: 'NIT 890.900.608-9',
    );
  }
}

class ScanReceiptPage extends ConsumerStatefulWidget {
  const ScanReceiptPage({super.key});

  @override
  ConsumerState<ScanReceiptPage> createState() => _ScanReceiptPageState();
}

class _ScanReceiptPageState extends ConsumerState<ScanReceiptPage> {
  bool _reading = false;

  Future<void> _capture() async {
    setState(() => _reading = true);
    try {
      final prefill = await ref.read(receiptReaderProvider).read();
      if (!mounted) return;
      showQToast(context, 'Revisa lo que leímos antes de guardar');
      context.pushReplacement(Routes.addExpense, extra: prefill);
    } on Object {
      if (!mounted) return;
      setState(() => _reading = false);
      showQToast(
        context,
        'No pudimos leer la factura. Prueba con más luz o regístrala a mano.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: const Text('Escanear factura'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.xs,
            AppSpace.gutter,
            AppSpace.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Pon la factura dentro del marco. Leemos el valor, el '
                'comercio y el NIT por ti.',
                style: AppTypography.body.copyWith(color: c.inkMuted),
              ),
              const SizedBox(height: AppSpace.md),
              Expanded(
                child: Semantics(
                  label: 'Visor de la cámara',
                  child: Container(
                    decoration: BoxDecoration(
                      color: c.hero,
                      borderRadius: AppRadius.cardAll,
                    ),
                    padding: const EdgeInsets.all(AppSpace.xl),
                    child: CustomPaint(
                      painter: _FramePainter(c.heroAccent),
                      child: Center(
                        child: _reading
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                    color: c.heroAccent,
                                  ),
                                  const SizedBox(height: AppSpace.md),
                                  Text(
                                    'Leyendo la factura…',
                                    style: AppTypography.body.copyWith(
                                      color: c.onHero,
                                    ),
                                  ),
                                ],
                              )
                            : Icon(
                                Icons.receipt_long_rounded,
                                size: AppSize.avatarLg,
                                color: c.onHeroMuted,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              // El progreso se ve en el visor; el botón solo se desactiva.
              QButton(
                label: 'Tomar foto',
                icon: Icons.photo_camera_outlined,
                onPressed: _reading ? null : _capture,
              ),
              const SizedBox(height: AppSpace.xs),
              QButton.secondary(
                label: 'Registrar a mano',
                onPressed: _reading
                    ? null
                    : () => context.pushReplacement(Routes.addExpense),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Esquinas del marco donde va la factura.
class _FramePainter extends CustomPainter {
  _FramePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const len = 28.0;
    final p = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final r = Offset.zero & size;
    for (final (corner, dx, dy) in [
      (r.topLeft, 1.0, 1.0),
      (r.topRight, -1.0, 1.0),
      (r.bottomLeft, 1.0, -1.0),
      (r.bottomRight, -1.0, -1.0),
    ]) {
      canvas
        ..drawLine(corner, corner + Offset(len * dx, 0), p)
        ..drawLine(corner, corner + Offset(0, len * dy), p);
    }
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.color != color;
}
