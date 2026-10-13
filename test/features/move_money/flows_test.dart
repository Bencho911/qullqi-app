import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump.dart';

/// Toca teclas del teclado numérico propio.
Future<void> typeAmount(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.bySemanticsLabel(d).last);
    await tester.pump();
  }
}

Future<void> openPlus(WidgetTester tester, String action) async {
  await tester.tap(find.byTooltip('Registrar o mover plata'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

const tall = Size(390, 1000);

void main() {
  group('Registrar gasto', () {
    testWidgets('guarda con tres toques y baja el disponible', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: tall, prefs: {'scope': 'personal'});
      expect(semanticsLabel('991.000 pesos'), findsOneWidget);
      await openPlus(tester, 'Registrar gasto');
      expect(find.text('¿Cuánto gastaste?'), findsOneWidget);
      await typeAmount(tester, '50000');
      expect(semanticsLabel('50.000 pesos'), findsOneWidget);
      await tester.tap(find.text('Guardar gasto'));
      await tester.pumpAndSettle();
      expect(find.text(r'Gasto guardado: $50.000'), findsOneWidget);
      // La cuenta por defecto (Bancolombia) bajó: el disponible también.
      expect(semanticsLabel('941.000 pesos'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('sin monto pide escribirlo', (tester) async {
      await pumpApp(tester, size: tall);
      await openPlus(tester, 'Registrar gasto');
      await tester.tap(find.text('Guardar gasto'));
      await tester.pump();
      expect(find.text('Escribe cuánto fue.'), findsOneWidget);
    });

    testWidgets('al cerrar con un monto pide confirmar', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: tall);
      await openPlus(tester, 'Registrar gasto');
      await typeAmount(tester, '1000');
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.text('¿Descartar este gasto?'), findsOneWidget);
      await tester.tap(find.text('Seguir editando'));
      await tester.pumpAndSettle();
      expect(find.text('¿Cuánto gastaste?'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('avisa si el gasto supera el saldo, sin bloquear', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: tall);
      await openPlus(tester, 'Registrar gasto');
      await typeAmount(tester, '9000000');
      expect(find.textContaining('Puedes guardarlo igual'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('el gasto nuevo se puede borrar y devuelve el saldo', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: tall, prefs: {'scope': 'personal'});
      await openPlus(tester, 'Registrar gasto');
      await typeAmount(tester, '50000');
      await tester.tap(find.text('Guardar gasto'));
      await tester.pumpAndSettle();
      // El gasto nuevo aparece primero en "Últimos movimientos".
      // Con "Cómo va tu mes" la lista queda más abajo: se centra antes de
      // tocar para que no la tape la barra inferior.
      await scrollIntoView(tester, find.text('Mercado'));
      await tester.tap(find.text('Mercado').first);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Borrar movimiento'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Borrar movimiento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Borrar Mercado'));
      await tester.pumpAndSettle();
      // De vuelta en el Inicio: el disponible regresó a como estaba.
      await tester.scrollUntilVisible(
        semanticsLabel('991.000 pesos'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(semanticsLabel('991.000 pesos'), findsOneWidget);
      handle.dispose();
    });
  });

  group('Mover plata', () {
    Future<void> fillAndReview(WidgetTester tester, String amount) async {
      await openPlus(tester, 'Mover plata');
      await typeAmount(tester, amount);
      await tester.tap(find.text('Revisar'));
      await tester.pumpAndSettle();
    }

    testWidgets('revisar, confirmar con huella y ver el comprobante', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: tall);
      await fillAndReview(tester, '300000');
      expect(find.text('Revisa antes de mover'), findsOneWidget);
      expect(find.text('Desde'), findsOneWidget);
      expect(find.text('Sin costo'), findsOneWidget);
      await tester.tap(find.text(r'Mover $300.000'));
      await tester.pumpAndSettle();
      expect(find.text('Confirma que eres tú'), findsOneWidget);
      await tester.tap(find.text('Usar huella o Face ID'));
      await tester.pumpAndSettle();
      // Bancolombia es un banco tradicional: queda en proceso.
      expect(find.text('Tu banco lo está procesando'), findsOneWidget);
      expect(find.text('Comprobante'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.text('Hola, Camilo'), findsWidgets);
      handle.dispose();
    });

    testWidgets('no deja seguir si no alcanza', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: tall);
      await fillAndReview(tester, '90000000');
      expect(find.text('Revisa antes de mover'), findsNothing);
      expect(find.textContaining('No te alcanza'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('un PIN equivocado avisa los intentos que quedan', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: tall);
      await fillAndReview(tester, '300000');
      await tester.tap(find.text(r'Mover $300.000'));
      await tester.pumpAndSettle();
      await typeAmount(tester, '111111');
      await tester.pumpAndSettle();
      expect(
        find.text('PIN incorrecto. Te quedan 2 intentos.'),
        findsOneWidget,
      );
      await typeAmount(tester, '123456');
      await tester.pumpAndSettle();
      expect(find.text('Tu banco lo está procesando'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('al agotar los intentos de PIN explica la pausa', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: tall);
      await fillAndReview(tester, '300000');
      await tester.tap(find.text(r'Mover $300.000'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        await typeAmount(tester, '000000');
        await tester.pumpAndSettle();
      }
      expect(find.text('Confirma que eres tú'), findsNothing);
      expect(find.textContaining('pausamos los intentos'), findsOneWidget);
      expect(find.text('Revisa antes de mover'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('montos altos solo aceptan PIN', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: tall);
      await fillAndReview(tester, '2500000');
      await tester.tap(find.text(r'Mover $2.500.000'));
      await tester.pumpAndSettle();
      expect(find.text('Usar huella o Face ID'), findsNothing);
      expect(find.textContaining('monto alto'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('si el banco rechaza, se explica y se puede reintentar', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: tall);
      await fillAndReview(tester, '100013');
      await tester.tap(find.text(r'Mover $100.013'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Usar huella o Face ID'));
      await tester.pumpAndSettle();
      expect(find.text('No se movió la plata'), findsOneWidget);
      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(find.text('Revisa antes de mover'), findsOneWidget);
      handle.dispose();
    });
  });

  group('Escanear factura', () {
    testWidgets('lee la factura y abre el gasto para revisarlo', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: tall);
      await openPlus(tester, 'Escanear factura');
      await tester.tap(find.text('Tomar foto'));
      await tester.pumpAndSettle();
      expect(find.text('Registrar gasto'), findsOneWidget);
      expect(semanticsLabel('85.400 pesos'), findsOneWidget);
      expect(find.textContaining('Éxito Calle 80'), findsOneWidget);
      handle.dispose();
    });
  });

  group('Capturas y accesibilidad', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('registrar gasto (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpApp(tester, mode: mode);
        await openPlus(tester, 'Registrar gasto');
        await typeAmount(tester, '85400');
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/add_expense_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });

      testWidgets('mover plata (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpApp(tester, mode: mode);
        await openPlus(tester, 'Mover plata');
        await typeAmount(tester, '300000');
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/move_form_${mode.name}.png'),
        );
        await expectAccessible(tester);
        await tester.tap(find.text('Revisar'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/move_review_${mode.name}.png'),
        );
        await expectAccessible(tester);
        await tester.tap(find.text(r'Mover $300.000'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/move_confirm_${mode.name}.png'),
        );
        await expectAccessible(tester);
        await tester.tap(find.text('Usar huella o Face ID'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/move_result_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });
    }

    testWidgets('pantalla pequeña (320 × 568) sin desbordes', (tester) async {
      await pumpApp(tester, size: const Size(320, 568));
      await openPlus(tester, 'Registrar gasto');
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add_expense_small.png'),
      );
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      await openPlus(tester, 'Mover plata');
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/move_form_small.png'),
      );
    });

    testWidgets('registrar gasto con texto al 200 %', (tester) async {
      await pumpApp(tester, textScale: 2, size: const Size(390, 1400));
      await openPlus(tester, 'Registrar gasto');
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/add_expense_text200.png'),
      );
    });

    testWidgets('escáner', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await openPlus(tester, 'Escanear factura');
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/scan.png'),
      );
      await expectAccessible(tester);
      handle.dispose();
    });
  });
}
