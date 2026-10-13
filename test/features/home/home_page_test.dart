import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/accounts/domain/account.dart';

import '../../helpers/pump.dart';

Finder scopeOption(String label) =>
    find.descendant(of: find.byType(ScopeSwitcher), matching: find.text(label));

/// Repositorio que falla, para probar el estado de error.
class _FailingAccounts implements AccountsRepository {
  @override
  Stream<List<Account>> watch() => Stream.error(Exception('sin conexión'));

  @override
  Future<void> sync() async {}

  @override
  Future<void> applyDelta(String accountId, int delta) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Persona sin cuentas conectadas.
class _NoAccounts implements AccountsRepository {
  @override
  Stream<List<Account>> watch() => Stream.value(const []);

  @override
  Future<void> sync() async {}

  @override
  Future<void> applyDelta(String accountId, int delta) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Repositorio que nunca responde, para ver la carga.
class _SlowAccounts implements AccountsRepository {
  @override
  Stream<List<Account>> watch() => const Stream.empty();

  @override
  Future<void> sync() async {}

  @override
  Future<void> applyDelta(String accountId, int delta) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> scrollTo(WidgetTester tester, Finder f) => tester
    .scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);

void main() {
  group('Disponible según la vista', () {
    testWidgets('Todo suma personal y negocio, y muestra el reparto', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('Disponible para gastar'), findsOneWidget);
      expect(semanticsLabel('3.208.672 pesos'), findsOneWidget);
      expect(semanticsLabel('Personal: 991.000 pesos'), findsOneWidget);
      expect(semanticsLabel('Negocio: 2.217.672 pesos'), findsOneWidget);
    });

    testWidgets('Personal y Negocio cambian el número', (tester) async {
      await pumpApp(tester);
      await tester.tap(scopeOption('Personal'));
      await tester.pumpAndSettle();
      expect(semanticsLabel('991.000 pesos'), findsOneWidget);
      await tester.tap(scopeOption('Negocio'));
      await tester.pumpAndSettle();
      expect(semanticsLabel('2.217.672 pesos'), findsOneWidget);
    });

    testWidgets('explica el cálculo en una hoja', (tester) async {
      await pumpApp(tester, prefs: {'scope': 'personal'});
      await tester.tap(find.byTooltip('Cómo lo calculamos'));
      await tester.pumpAndSettle();
      expect(find.text('Cómo calculamos tu disponible'), findsOneWidget);
      expect(find.text(r'$4.050.000'), findsOneWidget);
      expect(find.text(r'-$3.059.000'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.text('Cómo calculamos tu disponible'), findsNothing);
    });
  });

  group('Avisos y secciones', () {
    testWidgets('con una hoja abierta la barra inferior no responde', (
      tester,
    ) async {
      await pumpApp(tester);
      final cuentas = tester.getCenter(find.text('Cuentas'));
      await tester.tap(find.byTooltip('Cómo lo calculamos'));
      await tester.pumpAndSettle();
      await tester.tapAt(cuentas);
      await tester.pumpAndSettle();
      // La hoja tapa la barra: el toque no cambia de pestaña.
      if (find.text('Cerrar').evaluate().isNotEmpty) {
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Cómo calculamos tu disponible'), findsNothing);
      expect(find.text('Hola, Camilo'), findsWidgets);
      expect(find.text('Cuentas'), findsOneWidget);
    });

    testWidgets('avisa de la cuenta por reconectar solo donde aplica', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(find.text('Davivienda necesita reconectarse'), findsOneWidget);
      await tester.tap(scopeOption('Personal'));
      await tester.pumpAndSettle();
      expect(find.text('Davivienda necesita reconectarse'), findsNothing);
    });

    testWidgets('muestra 3 pagos y el resto en "Ver todos"', (tester) async {
      await pumpApp(tester);
      await scrollTo(tester, find.text('Próximos pagos'));
      expect(find.text('Ver todos (8)'), findsOneWidget);
      expect(find.text('Vence en 3 días'), findsOneWidget);
      await tester.tap(find.text('Ver todos (8)'));
      await tester.pumpAndSettle();
      expect(find.text('IVA de septiembre y octubre'), findsWidgets);
      expect(find.text('Vence en 27 días'), findsOneWidget);
    });

    testWidgets('lista los últimos movimientos de la vista', (tester) async {
      await pumpApp(tester, prefs: {'scope': 'business'});
      await scrollTo(tester, find.text('Últimos movimientos'));
      await scrollTo(tester, find.text('Asesoría digital'));
      expect(find.text('Anticipo proyecto UX'), findsOneWidget);
      expect(find.text('Éxito Chapinero'), findsNothing);
    });

    testWidgets('"Ver todas" lleva a la pestaña Cuentas', (tester) async {
      await pumpApp(tester);
      await scrollTo(tester, find.text('Ver todas'));
      await tester.tap(find.text('Ver todas'));
      await tester.pumpAndSettle();
      expect(find.text('Cuentas'), findsAtLeastNWidgets(2));
    });

    testWidgets('deslizar hacia abajo sincroniza y avisa', (tester) async {
      await pumpApp(tester);
      await tester.fling(
        find.byType(Scrollable).first,
        const Offset(0, 400),
        1200,
      );
      await tester.pumpAndSettle();
      expect(find.text('Tus cuentas están al día'), findsOneWidget);
    });
  });

  group('Estados', () {
    testWidgets('mientras carga muestra la forma del Inicio', (tester) async {
      await pumpApp(
        tester,
        settle: false,
        overrides: [
          accountsRepositoryProvider.overrideWithValue(_SlowAccounts()),
        ],
      );
      await tester.pump();
      expect(find.byType(SkeletonBlock), findsWidgets);
      expect(find.text('Disponible para gastar'), findsNothing);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_loading.png'),
      );
      // Deja correr los temporizadores de los demás repositorios.
      await tester.pumpAndSettle();
    });

    testWidgets('si falla, explica y deja reintentar', (tester) async {
      await pumpApp(
        tester,
        overrides: [
          accountsRepositoryProvider.overrideWithValue(_FailingAccounts()),
        ],
      );
      expect(find.text('No pudimos cargar tus cuentas'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_error.png'),
      );
    });

    testWidgets('sin cuentas invita a conectar la primera', (tester) async {
      await pumpApp(
        tester,
        overrides: [
          accountsRepositoryProvider.overrideWithValue(_NoAccounts()),
        ],
      );
      expect(find.text('Conecta tu primer banco'), findsOneWidget);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_empty.png'),
      );
      await tester.tap(find.text('Conectar cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Busca tu banco o billetera'), findsOneWidget);
    });
  });

  group('Capturas y accesibilidad', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('inicio completo (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpApp(tester, mode: mode, size: const Size(390, 1500));
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/home_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });
    }

    testWidgets('inicio personal', (tester) async {
      await pumpApp(
        tester,
        prefs: {'scope': 'personal'},
        size: const Size(390, 1500),
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_personal.png'),
      );
    });

    testWidgets('inicio con texto al 200 %', (tester) async {
      await pumpApp(tester, textScale: 2, size: const Size(390, 3000));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_text200.png'),
      );
    });

    testWidgets('inicio en pantalla angosta (320 px)', (tester) async {
      await pumpApp(tester, size: const Size(320, 1500));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_320.png'),
      );
    });

    testWidgets('hoja de explicación accesible', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await tester.tap(find.byTooltip('Cómo lo calculamos'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/home_explain.png'),
      );
      await expectAccessible(tester);
      handle.dispose();
    });
  });
}
