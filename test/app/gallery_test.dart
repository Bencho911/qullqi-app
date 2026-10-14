import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inti/app/dev/gallery_page.dart';
import 'package:inti/core/widgets/widgets.dart';

import '../helpers/pump.dart';

Future<void> pumpGallery(
  WidgetTester tester, {
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
  double height = 4600,
}) => pumpScreen(
  tester,
  const GalleryPage(),
  mode: mode,
  textScale: textScale,
  size: Size(390, height),
);

void main() {
  testWidgets('galería en tema claro', (tester) async {
    await pumpGallery(tester);
    expect(find.byType(GalleryPage), findsOneWidget);
    await expectLater(
      find.byType(GalleryPage),
      matchesGoldenFile('goldens/gallery_light.png'),
    );
  });

  testWidgets('galería en tema oscuro', (tester) async {
    await pumpGallery(tester, mode: ThemeMode.dark);
    await expectLater(
      find.byType(GalleryPage),
      matchesGoldenFile('goldens/gallery_dark.png'),
    );
  });

  testWidgets('galería con texto al 200 % no se rompe', (tester) async {
    await pumpGallery(tester, textScale: 2, height: 9000);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(GalleryPage),
      matchesGoldenFile('goldens/gallery_text200.png'),
    );
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('cumple las guías de accesibilidad (${mode.name})', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpGallery(tester, mode: mode);
      await expectAccessible(tester);
      handle.dispose();
    });
  }

  testWidgets('el selector de vista cambia el disponible', (tester) async {
    await pumpGallery(tester);
    expect(semanticsLabel('3.240.000 pesos'), findsOneWidget);
    await tester.tap(find.text('Negocio').first);
    await tester.pumpAndSettle();
    expect(semanticsLabel('1.330.000 pesos'), findsOneWidget);
  });

  testWidgets('el teclado escribe y borra', (tester) async {
    await pumpGallery(tester);
    expect(find.text(r'$85.400'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('^Borrar último dígito')));
    await tester.pump();
    expect(find.text(r'$8.540'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Tres ceros'));
    await tester.pump();
    expect(find.text(r'$8.540.000'), findsOneWidget);
  });

  testWidgets('la hoja de selección devuelve la opción elegida', (
    tester,
  ) async {
    await pumpGallery(tester);
    await tester.tap(find.text('Elegir cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('Desde qué cuenta'), findsOneWidget);
    await tester.tap(find.text('Nequi'));
    await tester.pumpAndSettle();
    expect(find.text('Desde qué cuenta'), findsNothing);
  });

  testWidgets('el botón muestra la carga y luego el aviso', (tester) async {
    await pumpGallery(tester);
    await tester.tap(find.text('Mover plata'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(find.text(r'Listo: moviste $300.000 a Nequi'), findsOneWidget);
    expect(find.byType(QButton), findsWidgets);
  });
}
