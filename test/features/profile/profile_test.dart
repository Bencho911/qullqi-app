import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qullqi/core/security/biometrics_pref.dart';
import 'package:qullqi/core/security/identity.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/core/storage/prefs.dart';
import 'package:qullqi/core/widgets/scope_switcher.dart';

import '../../helpers/pump.dart';

const tall = Size(390, 1800);

Future<void> openProfile(
  WidgetTester tester, {
  ThemeMode mode = ThemeMode.light,
  Size size = tall,
  double textScale = 1,
}) async {
  await pumpApp(tester, mode: mode, size: size, textScale: textScale);
  await tester.tap(find.byTooltip('Tu perfil'));
  await tester.pumpAndSettle();
}

Future<void> typePin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.bySemanticsLabel(d).last);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('editar nombre y celular', (tester) async {
    final container = await pumpApp(tester, size: tall);
    await tester.tap(find.byTooltip('Tu perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camilo Restrepo Gómez'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Camila Restrepo');
    await tester.enterText(find.byType(TextField).at(1), '3001112233');
    await tester.tap(find.text('Guardar datos'));
    await tester.pumpAndSettle();
    expect(find.text('Guardamos tus datos'), findsOneWidget);
    expect(find.text('Camila Restrepo'), findsOneWidget);
    expect(container.read(currentUserProvider).phone, '+57 300 111 2233');
  });

  testWidgets('cerrar con cambios sin guardar pregunta', (tester) async {
    await pumpApp(tester, size: tall);
    await tester.tap(find.byTooltip('Tu perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Camilo Restrepo Gómez'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Camila Restrepo');
    await tester.pump();
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    expect(find.text('¿Descartar los cambios?'), findsOneWidget);
    await tester.tap(find.text('Seguir editando'));
    await tester.pumpAndSettle();
    expect(find.text('Tus datos'), findsOneWidget);
    await tester.tap(find.byType(CloseButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descartar cambios'));
    await tester.pumpAndSettle();
    expect(find.text('Tu perfil'), findsOneWidget);
    expect(find.text('Camilo Restrepo Gómez'), findsOneWidget);
  });

  testWidgets('cambiar el PIN pide el actual', (tester) async {
    final handle = tester.ensureSemantics();
    final container = await pumpApp(tester, size: tall);
    await tester.tap(find.byTooltip('Tu perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cambiar PIN'));
    await tester.pumpAndSettle();
    await typePin(tester, '000000');
    expect(find.text('PIN incorrecto. Te quedan 2 intentos.'), findsOneWidget);
    await typePin(tester, '123456');
    expect(find.text('Escribe tu PIN nuevo.'), findsOneWidget);
    await typePin(tester, '482915');
    await typePin(tester, '482915');
    expect(find.text('Cambiamos tu PIN'), findsOneWidget);
    // checkPin espera una demora: corre fuera del reloj simulado.
    final ok = await tester.runAsync(
      () => container.read(identityVerifierProvider).checkPin('482915'),
    );
    expect(ok, isTrue);
    handle.dispose();
  });

  testWidgets('activar la huella pide reconocerla y se recuerda', (
    tester,
  ) async {
    final container = await pumpApp(tester, size: tall);
    await tester.tap(find.byTooltip('Tu perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar con huella o Face ID'));
    await tester.pumpAndSettle();
    expect(container.read(biometricsEnabledProvider), isTrue);
    expect(
      container.read(sharedPreferencesProvider).getBool('biometrics_enabled'),
      isTrue,
    );
  });

  testWidgets('apagar el negocio quita el selector de vista', (tester) async {
    await openProfile(tester);
    await tester.tap(find.text('Tengo negocio o soy independiente'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ScopeSwitcher), findsNothing);
  });

  testWidgets('apagar un aviso se refleja en el perfil', (tester) async {
    await openProfile(tester);
    expect(find.text('9 de 9 encendidos'), findsOneWidget);
    await tester.tap(find.text('Avisos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Movimientos grandes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('8 de 9 encendidos'), findsOneWidget);
  });

  testWidgets('cerrar la sesión en otros dispositivos', (tester) async {
    await openProfile(tester);
    await tester.tap(find.text('Dispositivos con tu cuenta'));
    await tester.pumpAndSettle();
    expect(find.text('iPad'), findsOneWidget);
    await tester.tap(find.text('Cerrar sesión en los demás'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(FilledButton, 'Cerrar sesión en los demás'),
    );
    await tester.pumpAndSettle();
    expect(find.text('iPad'), findsNothing);
  });

  testWidgets('eliminar la cuenta pide confirmar y el PIN', (tester) async {
    final handle = tester.ensureSemantics();
    final container = await pumpApp(tester, size: tall);
    await tester.tap(find.byTooltip('Tu perfil'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar mi cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Eliminar mi cuenta'));
    await tester.pumpAndSettle();
    expect(find.textContaining('monto alto'), findsNothing);
    expect(
      find.text('Por seguridad, escribe tu PIN de Qullqi.'),
      findsOneWidget,
    );
    await typePin(tester, '123456');
    expect(container.read(sessionProvider).status, SessionStatus.signedOut);
    expect(find.text('Ya tengo cuenta'), findsOneWidget);
    handle.dispose();
  });

  group('Capturas y accesibilidad', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('perfil (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await openProfile(tester, mode: mode);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/profile_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });
    }

    testWidgets('subpáginas', (tester) async {
      final handle = tester.ensureSemantics();
      await openProfile(tester, size: phone);
      for (final (label, name) in [
        ('Camilo Restrepo Gómez', 'edit'),
        ('Avisos', 'notices'),
      ]) {
        await scrollIntoView(tester, find.text(label));
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/profile_$name.png'),
        );
        await expectAccessible(tester);
        // "Tus datos" es un formulario (cierra); "Avisos" vuelve atrás.
        await tester.tap(
          find.byWidgetPredicate((w) => w is BackButton || w is CloseButton),
        );
        await tester.pumpAndSettle();
      }
      handle.dispose();
    });

    testWidgets('perfil con texto al 200 %', (tester) async {
      await openProfile(tester, textScale: 2, size: const Size(390, 4000));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/profile_text200.png'),
      );
    });
  });
}
