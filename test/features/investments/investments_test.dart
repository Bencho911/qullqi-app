import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inti/app/router.dart';
import 'package:inti/app/routes.dart';
import 'package:inti/core/money/money.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart'
    show ConnectionFailure;
import 'package:inti/features/accounts/domain/account.dart';
import 'package:inti/features/investments/data/investments_repository.dart';
import 'package:inti/features/investments/domain/investment.dart';
import 'package:inti/features/investments/domain/investment_source.dart';

import '../../helpers/pump.dart';

const _tall = Size(390, 1700);

/// Abre la app y va directo a [route] (las pantallas de Inversiones viven
/// encima de las pestañas).
Future<void> openRoute(
  WidgetTester tester,
  String route, {
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
  Size size = _tall,
  Map<String, Object> prefs = const {},
}) async {
  final container = await pumpApp(
    tester,
    mode: mode,
    textScale: textScale,
    size: size,
    prefs: prefs,
  );
  // Se apila encima del Inicio, como en la app: "atrás" tiene a dónde volver.
  unawaited(container.read(routerProvider).push<void>(route));
  await tester.pumpAndSettle();
}

Future<void> typeAmount(WidgetTester tester, String digits) async {
  for (final d in digits.split('')) {
    await tester.tap(find.bySemanticsLabel(d).last);
    await tester.pump();
  }
}

void main() {
  final now = DateTime(2026, 10, 24, 14, 45);

  group('Cálculos', () {
    late List<Investment> all;
    setUpAll(() async {
      all = await MockInvestmentsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
    });

    Investment byId(String id) => all.firstWhere((i) => i.id == id);

    test('el portafolio suma valor, lo puesto y la ganancia', () {
      final p = Portfolio.of(all);
      expect(p.value, 16593800);
      expect(p.invested, 16000000);
      expect(p.gain, 593800);
      expect(signedPercent(p.returnRatio), '+3,7 %');
    });

    test('el reparto va de mayor a menor', () {
      final p = Portfolio.of(all);
      expect(p.byKind.map((s) => s.kind).toList(), [
        InvestmentKind.cdt,
        InvestmentKind.pension,
        InvestmentKind.stock,
        InvestmentKind.fund,
        InvestmentKind.crypto,
      ]);
      expect(p.byKind.first.value, 8207500);
      expect(p.byKind.fold<double>(0, (s, k) => s + k.ratio), closeTo(1, 1e-9));
    });

    test('solo lo personal', () {
      final p = Portfolio.of(
        all.where((i) => i.ownership == Ownership.personal),
      );
      expect(p.value, 11473800);
      expect(signedPercent(p.returnRatio), '+4,3 %');
    });

    test('una pérdida y una ganancia por inversión', () {
      final loss = byId('acciones-trii');
      expect(loss.gain, -126000);
      expect(signedPercent(loss.returnRatio), '-6,3 %');
      expect(signedPercent(byId('cripto-bitcoin').returnRatio), '+28,0 %');
      expect(signedPercent(0), '0,0 %');
    });

    test('días para el vencimiento', () {
      expect(byId('cdt-confiar').daysToMaturity(now), 6);
      expect(byId('cdt-bancolombia').daysToMaturity(now), 60);
      expect(byId('cripto-bitcoin').daysToMaturity(now), isNull);
    });

    test('proyección sin y con rendimiento', () {
      final plain = projectGrowth(
        initial: 0,
        monthly: 100000,
        months: 12,
        annualRate: 0,
      );
      expect(plain.finalValue, 1200000);
      expect(plain.earned, 0);
      final grown = projectGrowth(
        initial: 1000000,
        monthly: 0,
        months: 12,
        annualRate: 0.10,
      );
      expect(grown.finalValue, 1100000);
      expect(grown.earned, 100000);
    });

    test('meses para llegar a una meta', () {
      expect(
        monthsToReach(
          target: 1200000,
          initial: 0,
          monthly: 100000,
          annualRate: 0,
        ),
        12,
      );
      expect(
        monthsToReach(target: 100, initial: 100, monthly: 0, annualRate: 0),
        0,
      );
      // Sin aportes ni rendimiento nunca llega.
      expect(
        monthsToReach(target: 1000, initial: 0, monthly: 0, annualRate: 0.1),
        isNull,
      );
    });

    test('el aporte mensual calculado alcanza la meta justo', () {
      final x = monthlyForTarget(
        target: 12000000,
        initial: 0,
        months: 24,
        annualRate: 0.10,
      );
      expect(
        projectGrowth(
          initial: 0,
          monthly: x,
          months: 24,
          annualRate: 0.10,
        ).finalValue,
        greaterThanOrEqualTo(12000000),
      );
      expect(
        projectGrowth(
          initial: 0,
          monthly: x - 1,
          months: 24,
          annualRate: 0.10,
        ).finalValue,
        lessThan(12000000),
      );
      expect(
        monthlyForTarget(
          target: 1200000,
          initial: 0,
          months: 12,
          annualRate: 0,
        ),
        100000,
      );
    });

    test('valor al final de cada año', () {
      expect(
        yearlyValues(initial: 0, monthly: 100000, years: 3, annualRate: 0),
        [1200000, 2400000, 3600000],
      );
    });
  });

  group('Repositorio', () {
    late MockInvestmentsRepository repo;
    setUp(
      () => repo = MockInvestmentsRepository(
        now: () => now,
        latency: Duration.zero,
      ),
    );

    test('conectar trae las inversiones de la entidad', () async {
      final created = await repo.connect(InvestmentSources.byId('davivienda')!);
      expect(created, hasLength(1));
      expect(created.single.kind, InvestmentKind.cdt);
      expect(created.single.status, ConnectionStatus.connected);
      expect(
        (await repo.watch().first).any((i) => i.id == created.single.id),
        isTrue,
      );
    });

    test('una entidad que no responde da un error explicable', () {
      expect(
        () => repo.connect(InvestmentSources.byId('porvenir')!),
        throwsA(isA<ConnectionFailure>()),
      );
      expect(
        () => repo.connect(InvestmentSources.byId('skandia')!),
        throwsA(isA<ConnectionFailure>()),
      );
    });

    test('agregar a mano parte del valor que pusiste', () async {
      final i = await repo.addManual(
        name: ' Mi CDT ',
        kind: InvestmentKind.cdt,
        invested: 1000000,
        value: 1000000,
        ownership: Ownership.personal,
      );
      expect(i.name, 'Mi CDT');
      expect(i.isManual, isTrue);
      expect(i.institution, isNull);
    });

    test('actualizar el valor y quitar', () async {
      await repo.updateValue('cripto-bitcoin', 700000);
      var items = await repo.watch().first;
      expect(items.firstWhere((i) => i.id == 'cripto-bitcoin').value, 700000);
      await repo.remove('cripto-bitcoin');
      items = await repo.watch().first;
      expect(items.any((i) => i.id == 'cripto-bitcoin'), isFalse);
    });

    test('reconectar deja la inversión al día', () async {
      await repo.reconnect('pension-proteccion');
      final p = (await repo.watch().first).firstWhere(
        (i) => i.id == 'pension-proteccion',
      );
      expect(p.status, ConnectionStatus.connected);
      expect(p.lastSync, now);
    });
  });

  group('Resumen', () {
    testWidgets('valor, ganancia, reparto y lista', (tester) async {
      await openRoute(tester, Routes.investments);
      expect(find.text('Tus inversiones valen'), findsOneWidget);
      expect(semanticsLabel('16.593.800 pesos'), findsWidgets);
      expect(
        find.text('Pusiste \$16.000.000\nGanaste \$593.800 (+3,7 %)'),
        findsOneWidget,
      );
      expect(find.text('CDT · 49 %'), findsOneWidget);
      expect(find.text('CDT a 180 días'), findsOneWidget);
      expect(find.text('Bitcoin'), findsOneWidget);
      expect(find.text('Reconecta para ver el valor de hoy'), findsOneWidget);
      // El CDT del negocio vence en 6 días: se destaca arriba.
      expect(
        find.text('Se acerca el vencimiento de CDT Confiar'),
        findsOneWidget,
      );
    });

    testWidgets('la vista Personal deja fuera lo del negocio', (tester) async {
      await openRoute(tester, Routes.investments, prefs: {'scope': 'personal'});
      expect(find.text('CDT Confiar'), findsNothing);
      expect(semanticsLabel('11.473.800 pesos'), findsWidgets);
    });

    testWidgets('desde Cuentas se llega a las inversiones', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: _tall);
      await tester.tap(find.bySemanticsLabel(RegExp('^Cuentas, pestaña')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tus inversiones'));
      await tester.pumpAndSettle();
      expect(find.text('Tus inversiones valen'), findsOneWidget);
      handle.dispose();
    });
  });

  group('Detalle', () {
    testWidgets('una inversión con ganancia', (tester) async {
      await openRoute(tester, Routes.investment('cdt-bancolombia'));
      expect(find.text('CDT a 180 días'), findsOneWidget);
      expect(find.text(r'Ganaste $87.500 (+2,9 %)'), findsOneWidget);
      expect(find.text('9,8 % e. a.'), findsOneWidget);
      expect(find.textContaining('vence en 60 días'), findsOneWidget);
      // Viene de la entidad: el valor no se edita a mano.
      expect(find.text('Actualizar valor'), findsNothing);
    });

    testWidgets('una pérdida se dice sin alarma', (tester) async {
      await openRoute(tester, Routes.investment('acciones-trii'));
      expect(find.text(r'Perdiste $126.000 (-6,3 %)'), findsOneWidget);
    });

    testWidgets('reconectar una inversión con el permiso vencido', (
      tester,
    ) async {
      await openRoute(tester, Routes.investment('pension-proteccion'));
      expect(find.text('Reconecta Protección'), findsOneWidget);
      await tester.tap(find.text('Reconectar'));
      await tester.pumpAndSettle();
      expect(find.text('Reconectamos Protección'), findsOneWidget);
      expect(find.text('Reconecta Protección'), findsNothing);
    });

    testWidgets('actualizar el valor de una inversión a mano', (tester) async {
      final handle = tester.ensureSemantics();
      await openRoute(tester, Routes.investment('cripto-bitcoin'));
      await tester.tap(find.text('Actualizar valor'));
      await tester.pumpAndSettle();
      // Parte del valor actual: se borra y se escribe el nuevo.
      await tester.tap(find.bySemanticsLabel(RegExp('^Borrar último dígito')));
      await tester.longPress(
        find.bySemanticsLabel(RegExp('^Borrar último dígito')),
      );
      await tester.pump();
      await typeAmount(tester, '700000');
      await tester.tap(find.text('Guardar valor'));
      await tester.pumpAndSettle();
      expect(find.text('Actualizamos Bitcoin'), findsOneWidget);
      expect(find.text(r'Ganaste $200.000 (+40,0 %)'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('quitar una inversión pide confirmar', (tester) async {
      await openRoute(tester, Routes.investment('cripto-bitcoin'));
      await scrollIntoView(tester, find.text('Quitar inversión'));
      await tester.tap(find.text('Quitar inversión'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quitar Bitcoin'));
      await tester.pumpAndSettle();
      expect(find.text('Quitamos Bitcoin'), findsOneWidget);
    });

    testWidgets('una inversión que no existe', (tester) async {
      await openRoute(tester, Routes.investment('no-existe'));
      expect(find.text('Esta inversión ya no existe'), findsOneWidget);
    });
  });

  group('Agregar y conectar', () {
    testWidgets('agregar a mano valida y crea', (tester) async {
      await openRoute(tester, Routes.addInvestment);
      await tester.tap(find.widgetWithText(FilledButton, 'Agregar inversión'));
      await tester.pump();
      expect(find.textContaining('Ponle un nombre'), findsOneWidget);
      expect(find.text('Escribe cuánto pusiste.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'Mi CDT');
      await tester.enterText(find.byType(TextField).at(2), '1000000');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Agregar inversión'));
      await tester.pumpAndSettle();
      expect(find.text('Agregamos Mi CDT'), findsOneWidget);
      expect(find.text('Sin ganancia ni pérdida (0,0 %)'), findsOneWidget);
    });

    testWidgets('conectar una entidad trae sus inversiones', (tester) async {
      await openRoute(tester, Routes.connectInvestment);
      // Lo que ya está conectado y lo que viene después, a la vista.
      expect(find.text('Conectada'), findsWidgets);
      expect(find.text('Muy pronto'), findsOneWidget);
      await tester.tap(find.text('Davivienda'));
      await tester.pumpAndSettle();
      expect(find.text('Solo lectura, nunca tus claves'), findsOneWidget);
      // Sin autorización no se continúa.
      final next = find.widgetWithText(FilledButton, 'Continuar a Davivienda');
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      await tester.tap(find.textContaining('Autorizo a Inti'));
      await tester.pump();
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('Davivienda quedó conectada'), findsOneWidget);
      expect(
        find.text('Trajimos 1 inversión. Ya cuentan en tu patrimonio.'),
        findsOneWidget,
      );
    });

    testWidgets('una entidad que no responde ofrece reintentar', (
      tester,
    ) async {
      await openRoute(tester, Routes.connectInvestment);
      await tester.tap(find.text('Porvenir'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Autorizo a Inti'));
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Continuar a Porvenir'),
      );
      await tester.pumpAndSettle();
      expect(find.text('No pudimos conectar Porvenir'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Agregar a mano'), findsOneWidget);
    });
  });

  group('Simulador', () {
    testWidgets('lo que aportas, a su plazo y su tasa', (tester) async {
      await openRoute(tester, Routes.simulator);
      expect(
        find.text('Escribe cuánto aportas para ver el resultado'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).at(1), '100000');
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, '1 año'));
      await tester.pumpAndSettle();
      final p = projectGrowth(
        initial: 0,
        monthly: 100000,
        months: 12,
        annualRate: 0.08,
      );
      expect(find.text('En 1 año tendrías'), findsOneWidget);
      expect(
        find.text(
          'Pondrías ${Cop.format(p.contributed)} y rendiría unos '
          '${Cop.format(p.earned)}',
        ),
        findsOneWidget,
      );
      // Siempre aclara que es una estimación.
      await scrollIntoView(tester, find.text('Es una estimación'));
      expect(find.text('Es una estimación'), findsOneWidget);
    });

    testWidgets('con una meta compara llegar guardando o invirtiendo', (
      tester,
    ) async {
      await openRoute(tester, Routes.simulatorForGoal('g-emergencia'));
      expect(find.text('Tu meta: Fondo de emergencia'), findsOneWidget);
      expect(find.text('Guardando, sin invertir'), findsOneWidget);
      expect(find.textContaining('Invirtiendo a 8 %'), findsOneWidget);
      expect(find.text('Para llegar a tiempo aporta'), findsOneWidget);
    });

    testWidgets('desde una meta se abre el simulador', (tester) async {
      await openRoute(tester, Routes.goal('g-emergencia'));
      await tester.tap(find.text('Simular invirtiéndola'));
      await tester.pumpAndSettle();
      expect(find.text('Tu meta: Fondo de emergencia'), findsOneWidget);
    });

    testWidgets('desde una inversión parte de su valor y su tasa', (
      tester,
    ) async {
      await openRoute(
        tester,
        Routes.simulatorFrom(initial: 3087500, rate: 0.098),
      );
      expect(find.text('9,8 % e. a.'), findsOneWidget);
      expect(find.text(r'$3.087.500'), findsWidgets);
    });
  });

  group('Accesibilidad', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('resumen (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await openRoute(tester, Routes.investments, mode: mode);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/investments_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });

      testWidgets('detalle (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await openRoute(
          tester,
          Routes.investment('cripto-bitcoin'),
          mode: mode,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/investment_detail_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });

      testWidgets('simulador (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await openRoute(
          tester,
          Routes.simulatorFrom(initial: 1000000),
          mode: mode,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/investment_simulator_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });
    }

    for (final route in [
      Routes.investments,
      Routes.investment('cdt-bancolombia'),
      Routes.addInvestment,
      Routes.connectInvestment,
      Routes.simulatorForGoal('g-emergencia'),
    ]) {
      testWidgets('texto al 200 % no se rompe: $route', (tester) async {
        await openRoute(tester, route, textScale: 2);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
