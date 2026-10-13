import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump.dart';

Finder tab(String label) => find.bySemanticsLabel(RegExp('^$label, pestaña'));

/// Abre la pestaña Movimientos.
Future<void> openTransactions(
  WidgetTester tester, {
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
  Size size = phone,
}) async {
  final handle = tester.ensureSemantics();
  await pumpApp(tester, mode: mode, textScale: textScale, size: size);
  await tester.tap(tab('Movimientos'));
  await tester.pumpAndSettle();
  handle.dispose();
}

Future<void> scrollTo(WidgetTester tester, Finder f) => tester
    .scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);

void main() {
  group('Lista', () {
    testWidgets('agrupa por día y resume el mes sin traslados', (tester) async {
      await openTransactions(tester, size: const Size(390, 1600));
      expect(find.text('Este mes · sin traslados'), findsOneWidget);
      expect(semanticsLabel('Ingresos: 5.571.000 pesos'), findsOneWidget);
      expect(find.text('Hoy'), findsWidgets);
      expect(find.text('Ayer'), findsOneWidget);
      expect(find.text('Éxito Chapinero'), findsOneWidget);
    });

    testWidgets('busca sin importar tildes', (tester) async {
      await openTransactions(tester);
      await tester.enterText(find.byType(TextField), 'exito');
      await tester.pumpAndSettle();
      expect(find.text('Éxito Chapinero'), findsOneWidget);
      expect(find.text('Starbucks Torre 72'), findsNothing);
      expect(find.text('1 movimiento'), findsOneWidget);
    });

    testWidgets('sin resultados ofrece limpiar los filtros', (tester) async {
      await openTransactions(tester);
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No encontramos movimientos'), findsOneWidget);
      await tester.tap(find.text('Quitar filtros'));
      await tester.pumpAndSettle();
      expect(find.text('Éxito Chapinero'), findsOneWidget);
    });

    testWidgets('el chip de tipo filtra', (tester) async {
      await openTransactions(tester, size: const Size(390, 1600));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Ingresos'));
      await tester.pumpAndSettle();
      expect(find.text('Anticipo proyecto UX'), findsOneWidget);
      expect(find.text('Éxito Chapinero'), findsNothing);
    });

    testWidgets('la hoja de filtros cambia el período al confirmar', (
      tester,
    ) async {
      await openTransactions(tester);
      await tester.tap(find.widgetWithText(ActionChip, 'Filtros'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Mes pasado'));
      await tester.pumpAndSettle();
      // Nada cambia hasta confirmar.
      await tester.tap(find.text('Ver resultados'));
      await tester.pumpAndSettle();
      expect(find.text('Filtros (1)'), findsOneWidget);
      expect(find.text('Mes pasado · sin traslados'), findsOneWidget);
      expect(find.text('Arriendo septiembre'), findsOneWidget);
    });
  });

  group('Traslados por revisar', () {
    testWidgets('confirmar uno lo saca de la cola y se puede deshacer', (
      tester,
    ) async {
      await openTransactions(tester);
      expect(find.text('2 traslados por revisar'), findsOneWidget);
      await tester.tap(find.text('Revisar'));
      await tester.pumpAndSettle();
      expect(find.text('Es un traslado'), findsNWidgets(2));
      await tester.tap(find.text('Es un traslado').first);
      await tester.pumpAndSettle();
      expect(find.text('Es un traslado'), findsOneWidget);
      expect(find.text('Listo: no lo contamos como gasto'), findsOneWidget);
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(find.text('Es un traslado'), findsNWidgets(2));
    });

    testWidgets('al terminar dice que todo está revisado', (tester) async {
      await openTransactions(tester);
      await tester.tap(find.text('Revisar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Es un gasto').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Es un traslado').first);
      await tester.pumpAndSettle();
      expect(find.text('Todo revisado'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.textContaining('por revisar'), findsNothing);
    });
  });

  group('Detalle', () {
    Future<void> openDetail(WidgetTester tester, String title) async {
      await openTransactions(tester, size: const Size(390, 1600));
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }

    testWidgets('muestra el movimiento y no deja borrar los del banco', (
      tester,
    ) async {
      await openDetail(tester, 'Éxito Chapinero');
      expect(find.text('Movimiento'), findsOneWidget);
      expect(find.text('Sábado, 24 de octubre · 14:32'), findsOneWidget);
      expect(semanticsLabel('Gasto: 85.400 pesos'), findsOneWidget);
      expect(find.textContaining('no borrarlo'), findsOneWidget);
    });

    testWidgets('cambia la categoría y lo refleja en la lista', (tester) async {
      await openDetail(tester, 'Éxito Chapinero');
      await tester.tap(find.text('Categoría'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salud'));
      await tester.pumpAndSettle();
      expect(find.text('Categoría: Salud'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'salud');
      await tester.pumpAndSettle();
      expect(find.text('Éxito Chapinero'), findsOneWidget);
    });

    testWidgets('pasa un movimiento a Negocio', (tester) async {
      await openDetail(tester, 'Éxito Chapinero');
      await scrollTo(tester, find.text('¿De quién es?'));
      await tester.tap(find.text('Negocio').last);
      await tester.pumpAndSettle();
      expect(find.text('Lo pasamos a Negocio'), findsOneWidget);
    });

    testWidgets('guarda una nota', (tester) async {
      await openDetail(tester, 'Éxito Chapinero');
      await scrollTo(tester, find.text('Nota'));
      await tester.enterText(find.byType(TextField), 'Mercado de la semana');
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Guardar nota'));
      await tester.tap(find.text('Guardar nota'));
      await tester.pumpAndSettle();
      expect(find.text('Guardamos tu nota'), findsOneWidget);
      expect(find.text('Guardar nota'), findsNothing);
    });
  });

  group('Capturas y accesibilidad', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('lista (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await openTransactions(tester, mode: mode, size: const Size(390, 1600));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/transactions_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });
    }

    testWidgets('lista con texto al 200 %', (tester) async {
      await openTransactions(tester, textScale: 2, size: const Size(390, 3200));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/transactions_text200.png'),
      );
    });

    testWidgets('lista en pantalla angosta (320 px)', (tester) async {
      await openTransactions(tester, size: const Size(320, 1400));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/transactions_320.png'),
      );
    });

    testWidgets('hoja de filtros', (tester) async {
      final handle = tester.ensureSemantics();
      await openTransactions(tester);
      await tester.tap(find.widgetWithText(ActionChip, 'Filtros'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/transactions_filters.png'),
      );
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('detalle y revisión', (tester) async {
      final handle = tester.ensureSemantics();
      await openTransactions(tester, size: const Size(390, 1600));
      await tester.tap(find.text('Éxito Chapinero'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/transaction_detail.png'),
      );
      await expectAccessible(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Revisar'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/review_transfers.png'),
      );
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('detalle con texto al 200 %', (tester) async {
      await openTransactions(tester, size: const Size(390, 1600));
      await tester.tap(find.text('Éxito Chapinero'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(Container());
      // Se vuelve a montar con texto grande y se abre el mismo detalle.
      await openTransactions(tester, textScale: 2, size: const Size(390, 3200));
      await scrollTo(tester, find.text('Éxito Chapinero'));
      await tester.tap(find.text('Éxito Chapinero'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/transaction_detail_text200.png'),
      );
    });

    testWidgets('hoja de filtros completa y sin resultados', (tester) async {
      await openTransactions(tester, size: const Size(390, 1400));
      await tester.tap(find.widgetWithText(ActionChip, 'Filtros'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/transactions_filters_full.png'),
      );
      await tester.tap(find.text('Ver resultados'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/transactions_no_results.png'),
      );
    });

    testWidgets('revisión con texto al 200 %', (tester) async {
      await openTransactions(tester, textScale: 2, size: const Size(390, 2400));
      await scrollTo(tester, find.text('Revisar'));
      await tester.tap(find.text('Revisar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/review_transfers_text200.png'),
      );
    });

    testWidgets('detalle de un gasto con tarjeta', (tester) async {
      await openTransactions(tester, size: const Size(390, 1600));
      await tester.tap(find.text('Terpel Calle 100'));
      await tester.pumpAndSettle();
      expect(find.text('Tarjeta Visa •• 4521'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/transaction_detail_card.png'),
      );
    });
  });
}
