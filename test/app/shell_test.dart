import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/core/scope/scope_provider.dart';
import 'package:inti/core/storage/prefs.dart';
import 'package:inti/core/theme/theme_mode.dart';
import 'package:inti/core/widgets/scope_switcher.dart';

import '../helpers/pump.dart';

Finder scopeOption(String label) =>
    find.descendant(of: find.byType(ScopeSwitcher), matching: find.text(label));

Finder tab(String label) => find.bySemanticsLabel(RegExp('^$label, pestaña'));

void main() {
  group('Navegación principal', () {
    testWidgets('abre en Inicio con saludo, vista y barra', (tester) async {
      await pumpApp(tester);
      expect(find.text('Hola, Camilo'), findsWidgets);
      for (final s in Scope.values) {
        expect(scopeOption(s.label), findsOneWidget);
      }
      for (final t in ['Inicio', 'Movimientos', 'Planes', 'Cuentas']) {
        expect(find.text(t), findsOneWidget);
      }
      expect(find.byTooltip('Registrar o mover plata'), findsOneWidget);
    });

    testWidgets('cambia de pestaña y conserva cada una', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await tester.tap(tab('Movimientos'));
      await tester.pumpAndSettle();
      // Título de la pestaña (más la etiqueta de la barra).
      expect(find.text('Movimientos'), findsAtLeastNWidgets(2));
      await tester.tap(tab('Cuentas'));
      await tester.pumpAndSettle();
      expect(find.text('Cuentas'), findsAtLeastNWidgets(2));
      handle.dispose();
    });

    testWidgets('atrás desde otra pestaña vuelve a Inicio', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await tester.tap(tab('Planes'));
      await tester.pumpAndSettle();
      expect(find.text('Planes'), findsAtLeastNWidgets(2));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('Hola, Camilo'), findsWidgets);
      handle.dispose();
    });
  });

  group('Vista Todo / Personal / Negocio', () {
    testWidgets('la vista elegida se guarda', (tester) async {
      final container = await pumpApp(tester);
      expect(container.read(scopeProvider), Scope.all);
      await tester.tap(scopeOption('Negocio'));
      await tester.pumpAndSettle();
      expect(container.read(scopeProvider), Scope.business);
      expect(
        container.read(sharedPreferencesProvider).getString('scope'),
        'business',
      );
    });

    testWidgets('al abrir recuerda la última vista', (tester) async {
      final container = await pumpApp(tester, prefs: {'scope': 'personal'});
      expect(container.read(scopeProvider), Scope.personal);
    });
  });

  group('Botón +', () {
    testWidgets('muestra las cuatro acciones y abre Mover plata', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Registrar o mover plata'));
      await tester.pumpAndSettle();
      expect(find.text('¿Qué quieres hacer?'), findsOneWidget);
      for (final a in [
        'Mover plata',
        'Registrar gasto',
        'Registrar ingreso',
        'Escanear factura',
      ]) {
        expect(find.text(a), findsOneWidget);
      }
      await tester.tap(find.text('Mover plata'));
      await tester.pumpAndSettle();
      expect(find.text('¿Cuánto quieres mover?'), findsOneWidget);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      expect(find.text('Hola, Camilo'), findsWidgets);
    });
  });

  group('Encabezado', () {
    testWidgets('el avatar abre el perfil y el tema se guarda', (tester) async {
      final container = await pumpApp(tester);
      await tester.tap(find.byTooltip('Tu perfil'));
      await tester.pumpAndSettle();
      expect(find.text('Tu perfil'), findsOneWidget);
      await scrollIntoView(tester, find.text('Oscuro'));
      await tester.tap(find.text('Oscuro'));
      await tester.pumpAndSettle();
      expect(container.read(themeModeProvider), ThemeMode.dark);
      expect(
        container.read(sharedPreferencesProvider).getString('theme_mode'),
        'dark',
      );
    });

    testWidgets('la campana abre las notificaciones', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byTooltip(RegExp('^Notificaciones')));
      await tester.pumpAndSettle();
      expect(find.text('Notificaciones'), findsOneWidget);
    });
  });

  group('Capturas y accesibilidad', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('inicio (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpApp(tester, mode: mode);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/shell_home_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });

      testWidgets('hoja del + (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpApp(tester, mode: mode);
        await tester.tap(find.byTooltip('Registrar o mover plata'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/shell_add_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });
    }

    testWidgets('inicio con texto al 200 %', (tester) async {
      await pumpApp(tester, textScale: 2);
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/shell_home_text200.png'),
      );
    });

    testWidgets('pantalla angosta (320 px) sin desbordes', (tester) async {
      await pumpApp(tester, size: const Size(320, 640));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/shell_home_320.png'),
      );
    });

    testWidgets('perfil', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Tu perfil'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/profile_light.png'),
      );
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('perfil (oscuro)', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, mode: ThemeMode.dark);
      await tester.tap(find.byTooltip('Tu perfil'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/profile_dark.png'),
      );
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('pantallas provisionales con texto al 200 %', (tester) async {
      await pumpApp(tester, textScale: 2);
      await tester.tap(find.byTooltip(RegExp('^Notificaciones')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/notifications_text200.png'),
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Registrar o mover plata'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mover plata'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/move_money_text200.png'),
      );
    });
  });
}
