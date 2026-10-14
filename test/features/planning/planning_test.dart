import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/planning/data/plans_repository.dart';
import 'package:inti/features/planning/domain/plans.dart';
import 'package:inti/features/transactions/data/transactions_repository.dart';
import 'package:inti/features/transactions/domain/transaction.dart';

import '../../helpers/pump.dart';

Finder tab(String label) => find.bySemanticsLabel(RegExp('^$label, pestaña'));

Future<void> openPlanning(
  WidgetTester tester, {
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
  Size size = const Size(390, 1500),
  String section = 'Presupuestos',
}) async {
  final handle = tester.ensureSemantics();
  await pumpApp(tester, mode: mode, textScale: textScale, size: size);
  await tester.tap(tab('Planes'));
  await tester.pumpAndSettle();
  if (section != 'Presupuestos') {
    await tester.tap(find.text(section));
    await tester.pumpAndSettle();
  }
  handle.dispose();
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
    late List<Transaction> txs;
    late List<Budget> budgets;
    late List<Goal> goals;
    setUpAll(() async {
      txs = await MockTransactionsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final plans = MockPlansRepository(now: () => now, latency: Duration.zero);
      budgets = await plans.watchBudgets().first;
      goals = await plans.watchGoals().first;
    });

    BudgetProgress p(String id) =>
        progressOf(budgets.firstWhere((b) => b.id == id), txs, now);

    test('estado de cada presupuesto según lo gastado', () {
      expect(p('b-transporte').status, BudgetStatus.ok); // 75.000 / 150.000
      expect(p('b-mercado').status, BudgetStatus.warning); // 85.400 / 100.000
      expect(p('b-suscripciones').status, BudgetStatus.over); // 38.900 / 30.000
      expect(p('b-suscripciones').left, -8900);
    });

    test('cuánto queda por día hasta fin de mes', () {
      expect(daysLeftInMonth(now), 8); // 24 al 31 de octubre
      expect(p('b-transporte').perDay, 75000 ~/ 8);
      expect(p('b-suscripciones').perDay, 0);
      expect(daysLeftInMonth(DateTime(2027, 2, 28)), 1);
    });

    test('solo cuentan gastos del mes y del mismo ámbito', () {
      final soft = budgets.firstWhere((b) => b.id == 'b-software');
      expect(spentThisMonth(soft, txs, now), 142000);
      final nextMonth = DateTime(2026, 11, 3);
      expect(spentThisMonth(soft, txs, nextMonth), 0);
    });

    test('metas: ritmo, meses que faltan y aporte necesario', () {
      final e = goals.firstWhere((g) => g.id == 'g-emergencia');
      expect(e.saved, 3720000);
      expect(monthlyPace(e, now), 400000);
      expect(monthsToGoal(e, now), 6); // faltan 2.280.000
      expect(monthlyNeeded(e, now), 380000); // en 6 meses
      final c = goals.firstWhere((g) => g.id == 'g-cartagena');
      expect(monthsToGoal(c, now), 10);
      expect(monthlyNeeded(c, now), isNull); // sin fecha
    });

    test('una meta sin aportes no promete fecha', () {
      const g = Goal(
        id: 'x',
        name: 'Moto',
        target: 1000,
        ownership: Ownership.personal,
        contributions: [],
      );
      expect(monthsToGoal(g, now), isNull);
    });

    test('reporte del mes compara con el anterior', () {
      final r = MonthReport.of(txs, scope: Scope.all, now: now);
      expect(r.income, 5571000);
      expect(r.expense, 511900);
      // Arriendo 1.200.000 + Netflix 34.900 + Spotify 16.900 + Éxito 35.000.
      expect(r.prevExpense, 1286800);
      expect(r.expenseChange, -774900);
      expect(r.byCategory.first.$1.id, 'software'); // la más grande
      expect(r.topExpenses.first.title, 'Figma y Notion');
    });
  });

  group('Presupuestos', () {
    testWidgets('resumen y presupuestos ordenados por urgencia', (
      tester,
    ) async {
      await openPlanning(tester);
      expect(find.text('Te queda en tus presupuestos'), findsOneWidget);
      expect(semanticsLabel('90.200 pesos'), findsOneWidget);
      expect(find.text(r'Te pasaste $8.900'), findsOneWidget);
      expect(find.textContaining('Cerca del límite'), findsWidgets);
    });

    testWidgets('crear un presupuesto nuevo', (tester) async {
      final handle = tester.ensureSemantics();
      await openPlanning(tester);
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Crear presupuesto'));
      await tester.pump();
      expect(find.text('Elige una categoría.'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Salud'));
      await typeAmount(tester, '200000');
      await tester.tap(find.widgetWithText(FilledButton, 'Crear presupuesto'));
      await tester.pumpAndSettle();
      expect(find.text(r'Salud: tope de $200.000 al mes'), findsOneWidget);
      expect(find.text('Salud'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('detalle, cambiar el tope y eliminar', (tester) async {
      final handle = tester.ensureSemantics();
      await openPlanning(tester);
      await tester.tap(find.text('Suscripciones'));
      await tester.pumpAndSettle();
      expect(find.text('Te pasaste'), findsOneWidget);
      expect(find.text('Netflix'), findsOneWidget);
      await tester.tap(find.text('Cambiar el tope'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel(RegExp('^Borrar último dígito')));
      await tester.longPress(
        find.bySemanticsLabel(RegExp('^Borrar último dígito')),
      );
      await tester.pump();
      await typeAmount(tester, '50000');
      await tester.tap(find.text('Guardar tope'));
      await tester.pumpAndSettle();
      expect(find.text('Te queda'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Eliminar presupuesto'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Eliminar presupuesto'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eliminar presupuesto de Suscripciones'));
      await tester.pumpAndSettle();
      expect(find.text('Suscripciones'), findsNothing);
      handle.dispose();
    });
  });

  group('Metas', () {
    testWidgets('lista con avance y ritmo', (tester) async {
      await openPlanning(tester, section: 'Metas');
      expect(find.text('Fondo de emergencia'), findsOneWidget);
      expect(
        find.textContaining('llegas en 6 meses a este ritmo'),
        findsOneWidget,
      );
    });

    testWidgets('separar plata suma a la meta', (tester) async {
      final handle = tester.ensureSemantics();
      await openPlanning(tester, section: 'Metas');
      await tester.tap(find.text('Viaje a Cartagena'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Separar plata'));
      await tester.pumpAndSettle();
      await typeAmount(tester, '100000');
      await tester.tap(find.text(r'Separar $100.000'));
      await tester.pumpAndSettle();
      expect(
        find.text(r'Separaste $100.000 para Viaje a Cartagena'),
        findsOneWidget,
      );
      expect(
        semanticsLabel('Llevas 700.000 pesos de 2.500.000 pesos'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('crear una meta con plazo', (tester) async {
      await openPlanning(tester, section: 'Metas');
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Moto');
      await tester.enterText(find.byType(TextField).at(1), '1200000');
      await tester.tap(find.widgetWithText(ChoiceChip, '1 año'));
      await tester.pumpAndSettle();
      expect(find.textContaining(r'Separa $100.000 al mes'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Crear meta'));
      await tester.pumpAndSettle();
      expect(find.text('Creamos tu meta Moto'), findsOneWidget);
      expect(find.text('Moto'), findsOneWidget);
    });
  });

  group('Reportes', () {
    testWidgets('lo que sobró, comparación y categorías', (tester) async {
      await openPlanning(tester, section: 'Reportes');
      expect(find.text('Te sobró en octubre'), findsOneWidget);
      expect(
        find.text(r'Gastaste $774.900 menos que el mes pasado'),
        findsOneWidget,
      );
      expect(find.text('En qué se fue la plata'), findsOneWidget);
    });
  });

  group('Capturas y accesibilidad', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final section in ['Presupuestos', 'Metas', 'Reportes']) {
        testWidgets('$section (${mode.name})', (tester) async {
          final handle = tester.ensureSemantics();
          await openPlanning(tester, mode: mode, section: section);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              'goldens/planning_${section.toLowerCase()}_${mode.name}.png',
            ),
          );
          await expectAccessible(tester);
          handle.dispose();
        });
      }
    }

    testWidgets('detalles y editores', (tester) async {
      final handle = tester.ensureSemantics();
      await openPlanning(tester, size: phone);
      await tester.tap(find.text('Suscripciones'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/budget_detail.png'),
      );
      await expectAccessible(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/budget_editor.png'),
      );
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('meta: detalle y separar', (tester) async {
      final handle = tester.ensureSemantics();
      await openPlanning(tester, size: phone, section: 'Metas');
      await tester.tap(find.text('Fondo de emergencia'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/goal_detail.png'),
      );
      await expectAccessible(tester);
      await tester.tap(find.text('Separar plata'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/goal_contribute.png'),
      );
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('planes con texto al 200 %', (tester) async {
      await openPlanning(tester, textScale: 2, size: const Size(390, 3000));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/planning_text200.png'),
      );
    });
  });
}
