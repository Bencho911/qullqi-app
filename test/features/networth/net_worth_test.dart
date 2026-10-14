import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:inti/app/router.dart';
import 'package:inti/app/routes.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/debts/domain/debt_plan.dart';
import 'package:inti/features/networth/domain/net_worth_history.dart';
import 'package:inti/features/networth/presentation/widgets/net_worth_chart.dart';

import '../../helpers/pump.dart';

const _tall = Size(390, 1700);

Future<ProviderContainer> openRoute(
  WidgetTester tester,
  String route, {
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
  Map<String, Object> prefs = const {},
}) async {
  final container = await pumpApp(
    tester,
    mode: mode,
    textScale: textScale,
    size: _tall,
    prefs: prefs,
  );
  unawaited(container.read(routerProvider).push<void>(route));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  final now = DateTime(2026, 10, 24, 14, 45);

  group('Historial de patrimonio', () {
    final history = buildDemoHistory(
      personalNow: 13753800,
      businessNow: 8870000,
      now: now,
    );

    test('termina exactamente en el valor de hoy', () {
      expect(history.personal.last.value, 13753800);
      expect(history.business.last.value, 8870000);
      expect(history.personal.last.date, DateTime(2026, 10, 24));
      expect(history.personal, hasLength(366));
    });

    test('las fechas van de la más antigua a hoy, sin saltos', () {
      for (var i = 1; i < history.personal.length; i++) {
        expect(
          history.personal[i].date.difference(history.personal[i - 1].date),
          const Duration(days: 1),
        );
      }
    });

    test('crece con el tiempo', () {
      expect(
        history.personal.first.value,
        lessThan(history.personal.last.value),
      );
      expect(changeOf(history.personal), greaterThan(0));
      expect(changeRatio(history.personal), closeTo(0.35, 0.05));
    });

    test('en Todo suma personal y negocio día a día', () {
      final all = history.forScope(Scope.all);
      expect(all.last.value, 13753800 + 8870000);
      expect(
        all[100].value,
        history.personal[100].value + history.business[100].value,
      );
      expect(history.forScope(Scope.business), same(history.business));
    });

    test('los últimos días incluyen el día de partida', () {
      expect(lastDays(history.personal, 30), hasLength(31));
      expect(lastDays(history.personal, 90).last, history.personal.last);
      expect(lastDays(history.personal, 9999), hasLength(366));
    });

    test('un patrimonio en cero no da porcentajes raros', () {
      final zero = buildDemoHistory(
        personalNow: 0,
        businessNow: 0,
        now: now,
        days: 10,
      );
      expect(changeRatio(zero.personal), 0);
      expect(changeOf(const []), 0);
    });
  });

  group('Plan de deudas', () {
    const visa = DebtInput(
      id: 'visa',
      name: 'Visa',
      balance: 1320000,
      annualRate: 0.27,
      minimum: 180000,
    );
    const nu = DebtInput(
      id: 'nu',
      name: 'Nu',
      balance: 450000,
      annualRate: 0.24,
      minimum: 45000,
    );

    test('sin interés: meses exactos y nada de intereses', () {
      const d = DebtInput(
        id: 'a',
        name: 'A',
        balance: 1000000,
        annualRate: 0,
        minimum: 100000,
      );
      final r = simulateDebtPlan(
        debts: const [d],
        monthlyPayment: 100000,
        strategy: DebtStrategy.avalanche,
      );
      expect(r.completed, isTrue);
      expect(r.months, 10);
      expect(r.totalInterest, 0);
      expect(r.totalPaid, 1000000);
    });

    test('el interés alarga el plazo', () {
      const d = DebtInput(
        id: 'a',
        name: 'A',
        balance: 1000000,
        annualRate: 0.27,
        minimum: 100000,
      );
      final r = simulateDebtPlan(
        debts: const [d],
        monthlyPayment: 100000,
        strategy: DebtStrategy.avalanche,
      );
      expect(r.months, greaterThan(10));
      expect(r.totalInterest, greaterThan(0));
      expect(r.totalPaid, 1000000 + r.totalInterest);
    });

    test(
      'avalancha paga primero la de mayor tasa; bola de nieve, la menor',
      () {
        final a = simulateDebtPlan(
          debts: const [visa, nu],
          monthlyPayment: 425000,
          strategy: DebtStrategy.avalanche,
        );
        final s = simulateDebtPlan(
          debts: const [visa, nu],
          monthlyPayment: 425000,
          strategy: DebtStrategy.snowball,
        );
        expect(a.payoffs.first.id, 'visa');
        expect(s.payoffs.first.id, 'nu');
        expect(a.completed && s.completed, isTrue);
        // La avalancha nunca paga más intereses que la bola de nieve.
        expect(a.totalInterest, lessThanOrEqualTo(s.totalInterest));
      },
    );

    test('el plan gana al mínimo en meses e intereses', () {
      final plan = simulateDebtPlan(
        debts: const [visa, nu],
        monthlyPayment: 425000,
        strategy: DebtStrategy.avalanche,
      );
      final minimum = simulateDebtPlan(
        debts: const [visa, nu],
        monthlyPayment: 225000,
        strategy: DebtStrategy.avalanche,
        redirectFreed: false,
      );
      expect(plan.months, lessThan(minimum.months));
      expect(plan.totalInterest, lessThan(minimum.totalInterest));
    });

    test('un pago menor a los mínimos se sube a los mínimos', () {
      final low = simulateDebtPlan(
        debts: const [visa, nu],
        monthlyPayment: 1,
        strategy: DebtStrategy.avalanche,
      );
      final min = simulateDebtPlan(
        debts: const [visa, nu],
        monthlyPayment: 225000,
        strategy: DebtStrategy.avalanche,
      );
      expect(low.months, min.months);
      expect(low.totalInterest, min.totalInterest);
    });

    test('si el mínimo no cubre los intereses, nunca termina', () {
      const d = DebtInput(
        id: 'a',
        name: 'A',
        balance: 10000000,
        annualRate: 0.5,
        minimum: 10000,
      );
      final r = simulateDebtPlan(
        debts: const [d],
        monthlyPayment: 10000,
        strategy: DebtStrategy.avalanche,
        redirectFreed: false,
      );
      expect(r.completed, isFalse);
      expect(r.months, debtMaxMonths);
    });

    test('sin deudas no hay nada que simular', () {
      final r = simulateDebtPlan(
        debts: const [],
        monthlyPayment: 100000,
        strategy: DebtStrategy.snowball,
      );
      expect(r.months, 0);
      expect(r.completed, isTrue);
    });
  });

  group('Pantalla de patrimonio', () {
    testWidgets('valor, rango y de qué está hecho', (tester) async {
      await openRoute(tester, Routes.netWorth);
      expect(find.text('Tu patrimonio vale'), findsOneWidget);
      expect(semanticsLabel('22.623.800 pesos'), findsWidgets);
      expect(find.textContaining('En 3 meses:'), findsOneWidget);
      expect(find.text(r'$7.800.000'), findsOneWidget);
      expect(find.text(r'$16.593.800'), findsWidgets);
      expect(find.text(r'-$1.770.000'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '1 año'));
      await tester.pumpAndSettle();
      expect(find.textContaining('En 1 año:'), findsOneWidget);
    });

    testWidgets('la vista Personal usa solo lo personal', (tester) async {
      await openRoute(tester, Routes.netWorth, prefs: {'scope': 'personal'});
      // 3.200.000 + 850.000 − 1.320.000 − 450.000 + 11.473.800.
      expect(semanticsLabel('13.753.800 pesos'), findsWidgets);
    });

    testWidgets('tocar la gráfica muestra un día y "Ver hoy" vuelve', (
      tester,
    ) async {
      await openRoute(tester, Routes.netWorth);
      expect(find.text('Ver hoy'), findsNothing);
      await tester.tapAt(tester.getCenter(find.byType(NetWorthChart)));
      await tester.pump();
      expect(find.text('Ver hoy'), findsOneWidget);
      await tester.tap(find.text('Ver hoy'));
      await tester.pump();
      expect(find.text('Ver hoy'), findsNothing);
    });

    testWidgets('desde Cuentas se llega al patrimonio y al plan', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: _tall);
      await tester.tap(find.bySemanticsLabel(RegExp('^Cuentas, pestaña')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cómo ha crecido tu patrimonio'));
      await tester.pumpAndSettle();
      expect(find.text('Tu patrimonio vale'), findsOneWidget);
      handle.dispose();
    });
  });

  group('Pantalla del plan de deudas', () {
    testWidgets('arranca con los mínimos más un extra', (tester) async {
      await openRoute(tester, Routes.debtPlan);
      expect(find.text('Debes en tarjetas'), findsOneWidget);
      expect(semanticsLabel('1.770.000 pesos'), findsWidgets);
      expect(find.text('425000'), findsOneWidget);
      expect(find.text('Con tu plan: tardas'), findsOneWidget);
      expect(find.text('Te ahorras en intereses'), findsOneWidget);
      // Avalancha: la Visa (27 %) va primero.
      expect(find.textContaining('1. Tarjeta Visa'), findsOneWidget);
    });

    testWidgets('cambiar la estrategia cambia el orden', (tester) async {
      await openRoute(tester, Routes.debtPlan);
      await tester.tap(find.text('Bola de nieve'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1. Tarjeta Mastercard'), findsOneWidget);
    });

    testWidgets('un pago menor a los mínimos se explica', (tester) async {
      await openRoute(tester, Routes.debtPlan);
      await tester.enterText(find.byType(TextField), '100000');
      await tester.pumpAndSettle();
      expect(
        find.text(r'Para no caer en mora necesitas al menos $225.000.'),
        findsOneWidget,
      );
    });

    testWidgets('sin tarjetas con deuda se felicita', (tester) async {
      await openRoute(tester, Routes.debtPlan, prefs: {'scope': 'business'});
      expect(find.text('No debes nada en tarjetas'), findsOneWidget);
    });
  });

  group('Capturas y accesibilidad', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('patrimonio (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await openRoute(tester, Routes.netWorth, mode: mode);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/net_worth_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });

      testWidgets('plan de deudas (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await openRoute(tester, Routes.debtPlan, mode: mode);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/debt_plan_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });
    }

    for (final route in [Routes.netWorth, Routes.debtPlan]) {
      testWidgets('texto al 200 % no se rompe: $route', (tester) async {
        await openRoute(tester, route, textScale: 2);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
