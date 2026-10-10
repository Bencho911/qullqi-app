import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/features/auth/presentation/validators.dart';

import '../../helpers/pump.dart';

Future<void> typePin(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.bySemanticsLabel(d).last);
    await tester.pump();
  }
  await tester.pumpAndSettle();
}

Finder button(String label) => find.widgetWithText(FilledButton, label);

void main() {
  group('Validaciones', () {
    test('correo, nombre, contraseña y celular', () {
      expect(Validate.email('ana@correo.co'), isNull);
      expect(Validate.email('ana@correo'), isNotNull);
      expect(Validate.name('Ana'), isNotNull);
      expect(Validate.name('Ana Gómez'), isNull);
      expect(Validate.password('1234567'), isNotNull);
      expect(Validate.phone('3105550142'), isNull);
      expect(Validate.phone('6015550142'), isNotNull);
      expect(Validate.formatPhone('3105550142'), '310 555 0142');
    });

    test('fuerza de la contraseña', () {
      expect(PasswordStrength.of('abcdefgh'), PasswordStrength.weak);
      expect(PasswordStrength.of('abcdefgh12'), PasswordStrength.fair);
      expect(PasswordStrength.of('Abcdefgh12!'), PasswordStrength.strong);
    });
  });

  group('Sin sesión', () {
    testWidgets('abre en la bienvenida', (tester) async {
      await pumpApp(tester, signedIn: false);
      expect(find.text('Todas tus cuentas en un solo lugar'), findsOneWidget);
      expect(find.text('Crear cuenta'), findsOneWidget);
    });

    testWidgets('registro completo hasta entrar a la app', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, signedIn: false, size: const Size(390, 1000));
      await tester.tap(find.text('Crear cuenta'));
      await tester.pumpAndSettle();
      // Sin datos no avanza y explica qué falta.
      await tester.tap(button('Continuar'));
      await tester.pumpAndSettle();
      expect(find.text('Escribe tu nombre y tu apellido.'), findsOneWidget);
      expect(find.text('Acepta los términos para continuar.'), findsOneWidget);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Ana Gómez');
      await tester.enterText(fields.at(1), 'ana@correo.co');
      await tester.enterText(fields.at(2), 'Clave2026!');
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      expect(find.text('Seguridad: Fuerte'), findsOneWidget);
      await tester.tap(button('Continuar'));
      await tester.pumpAndSettle();
      // Celular.
      await tester.enterText(find.byType(TextField), '3105550142');
      await tester.tap(button('Enviar código'));
      await tester.pumpAndSettle();
      expect(find.textContaining('+57 310 555 0142'), findsOneWidget);
      // Código equivocado y luego el correcto.
      await tester.enterText(find.byType(TextField), '111111');
      await tester.pumpAndSettle();
      expect(
        find.text('El código no coincide. Revisa el SMS.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pumpAndSettle();
      // PIN: crear y confirmar.
      expect(find.text('Crea tu PIN'), findsOneWidget);
      await typePin(tester, '482915');
      expect(find.text('Escríbelo otra vez para confirmar.'), findsOneWidget);
      await typePin(tester, '482915');
      expect(find.text('¿Entras con tu huella o Face ID?'), findsOneWidget);
      await tester.tap(find.text('Activar huella o Face ID'));
      await tester.pumpAndSettle();
      expect(find.text('Hola, Ana'), findsWidgets);
      handle.dispose();
    });

    testWidgets('ingresar en un teléfono que ya tiene PIN entra directo', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, signedIn: false, size: const Size(390, 1000));
      await tester.tap(find.text('Ya tengo cuenta'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'ana@correo.co');
      await tester.enterText(find.byType(TextField).at(1), 'Clave2026!');
      await tester.tap(button('Ingresar'));
      await tester.pumpAndSettle();
      // El mock ya tiene PIN: entra directo.
      expect(find.text('Hola, Camilo'), findsWidgets);
      handle.dispose();
    });

    testWidgets('una contraseña equivocada se explica', (tester) async {
      await pumpApp(tester, signedIn: false);
      await tester.tap(find.text('Ya tengo cuenta'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), 'ana@correo.co');
      await tester.enterText(find.byType(TextField).at(1), 'error1234');
      await tester.tap(button('Ingresar'));
      await tester.pumpAndSettle();
      expect(
        find.text('El correo o la contraseña no coinciden.'),
        findsOneWidget,
      );
    });

    testWidgets('recuperar la contraseña', (tester) async {
      await pumpApp(tester, signedIn: false);
      await tester.tap(find.text('Ya tengo cuenta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('¿Olvidaste tu contraseña?'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ana@correo.co');
      await tester.tap(button('Enviar enlace'));
      await tester.pumpAndSettle();
      expect(find.text('Revisa tu correo'), findsOneWidget);
    });

    testWidgets('no se puede entrar a la app sin sesión', (tester) async {
      final container = await pumpApp(tester, signedIn: false);
      expect(find.text('Hola, Camilo'), findsNothing);
      expect(container.read(sessionProvider).status, SessionStatus.signedOut);
    });
  });

  group('Con sesión', () {
    testWidgets('al abrir pide el PIN y lo acepta', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, lockOnStart: true, size: const Size(390, 1000));
      expect(find.text('Escribe tu PIN para entrar.'), findsOneWidget);
      await typePin(tester, '123456');
      expect(find.text('Hola, Camilo'), findsWidgets);
      handle.dispose();
    });

    testWidgets('tres PIN equivocados cierran la sesión', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, lockOnStart: true, size: const Size(390, 1000));
      await typePin(tester, '000000');
      expect(
        find.text('PIN incorrecto. Te quedan 2 intentos.'),
        findsOneWidget,
      );
      await typePin(tester, '000000');
      await typePin(tester, '000000');
      expect(find.text('Crear cuenta'), findsOneWidget); // bienvenida
      handle.dispose();
    });

    testWidgets('cerrar sesión vuelve a la bienvenida', (tester) async {
      await pumpApp(tester, size: const Size(390, 1000));
      await tester.tap(find.byTooltip('Tu perfil'));
      await tester.pumpAndSettle();
      await scrollIntoView(tester, find.text('Cerrar sesión'));
      await tester.tap(find.text('Cerrar sesión'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cerrar sesión'));
      await tester.pumpAndSettle();
      expect(find.text('Ya tengo cuenta'), findsOneWidget);
    });
  });

  group('Capturas y accesibilidad', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('bienvenida y desbloqueo (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpApp(tester, mode: mode, signedIn: false);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/welcome_${mode.name}.png'),
        );
        await expectAccessible(tester);
        await tester.pumpWidget(const SizedBox());
        await pumpApp(tester, mode: mode, lockOnStart: true);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/lock_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });
    }

    testWidgets('registro, código e ingreso', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, signedIn: false);
      await tester.tap(find.text('Crear cuenta'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sign_up.png'),
      );
      await expectAccessible(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ya tengo cuenta'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sign_in.png'),
      );
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('acceso con texto al 200 %', (tester) async {
      await pumpApp(
        tester,
        signedIn: false,
        textScale: 2,
        size: const Size(390, 1400),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Crear cuenta'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/sign_up_text200.png'),
      );
    });
  });
}
