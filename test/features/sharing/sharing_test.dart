import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:qullqi/app/router.dart';
import 'package:qullqi/app/routes.dart';
import 'package:qullqi/features/sharing/data/sharing_repositories.dart';
import 'package:qullqi/features/sharing/domain/sharing.dart';

import '../../helpers/pump.dart';

const _tall = Size(390, 1700);

Future<ProviderContainer> openRoute(
  WidgetTester tester,
  String route, {
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
}) async {
  final container = await pumpApp(
    tester,
    mode: mode,
    textScale: textScale,
    size: _tall,
  );
  unawaited(container.read(routerProvider).push<void>(route));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  final now = DateTime(2026, 10, 24, 14, 45);

  group('Reparto de un gasto', () {
    test('en partes iguales, lo que sobra va a los primeros', () {
      final e = SharedExpense.equal(
        id: 'e',
        groupId: 'g',
        title: 'Cena',
        amount: 100000,
        paidBy: 'a',
        participants: const ['a', 'b', 'c'],
        date: now,
      );
      expect(e.shares, {'a': 33334, 'b': 33333, 'c': 33333});
      expect(e.shares.values.fold(0, (s, v) => s + v), 100000);
    });

    test('entre dos, sin sobrantes', () {
      final e = SharedExpense.equal(
        id: 'e',
        groupId: 'g',
        title: 'Mercado',
        amount: 240000,
        paidBy: 'a',
        participants: const ['a', 'b'],
        date: now,
      );
      expect(e.shares, {'a': 120000, 'b': 120000});
    });
  });

  group('Saldos del grupo', () {
    late MockGroupsRepository repo;
    late List<SharedGroup> groups;
    late List<SharedExpense> expenses;
    setUp(() async {
      repo = MockGroupsRepository(now: () => now, latency: Duration.zero);
      groups = await repo.watchGroups().first;
      expenses = await repo.watchExpenses().first;
    });

    SharedGroup g(String id) => groups.firstWhere((x) => x.id == id);

    test('la casa: Laura te debe lo que cuadra', () {
      final b = balancesOf(g('g-casa'), expenses, const []);
      expect(b[meId], 30000);
      expect(b['casa-laura'], -30000);
    });

    test('el viaje: todos suman cero', () {
      final b = balancesOf(g('g-viaje'), expenses, const []);
      expect(b[meId], -160000);
      expect(b['viaje-laura'], 530000);
      expect(b['viaje-andres'], -370000);
      expect(b.values.fold(0, (s, v) => s + v), 0);
    });

    test('los pagos mínimos para quedar a mano', () {
      final t = simplifyDebts(balancesOf(g('g-viaje'), expenses, const []));
      expect(t, hasLength(2));
      expect(t[0].from, 'viaje-andres');
      expect(t[0].to, 'viaje-laura');
      expect(t[0].amount, 370000);
      expect(t[1].from, meId);
      expect(t[1].amount, 160000);
    });

    test('un pago ya hecho baja lo que se debe', () {
      final paid = Settlement(
        id: 's',
        groupId: 'g-viaje',
        from: meId,
        to: 'viaje-laura',
        amount: 160000,
        date: now,
      );
      final b = balancesOf(g('g-viaje'), expenses, [paid]);
      expect(b[meId], 0);
      expect(b['viaje-laura'], 370000);
      expect(simplifyDebts(b), hasLength(1));
    });

    test('un grupo a mano no tiene pagos', () {
      expect(simplifyDebts({'a': 0, 'b': 0}), isEmpty);
    });
  });

  group('Dividir una cuenta', () {
    test('con propina', () {
      final s = BillSplit.of(bill: 300000, people: 4, tipPercent: 10);
      expect(s.tip, 30000);
      expect(s.total, 330000);
      expect(s.perPerson, 82500);
    });

    test('lo que no cuadra se sube al peso siguiente', () {
      final s = BillSplit.of(bill: 100000, people: 3);
      expect(s.perPerson, 33334);
      expect(s.perPerson * 3, greaterThanOrEqualTo(100000));
    });

    test('con menos de una persona, paga uno solo', () {
      expect(BillSplit.of(bill: 50000, people: 0).perPerson, 50000);
    });
  });

  group('Deudas y metas (cálculos)', () {
    test('totales de deudas abiertas', () async {
      final debts = await MockDebtsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final t = DebtTotals.of(debts);
      // Andrés te debe 45.000; tú le debes 30.000 a Laura; lo saldado no
      // cuenta.
      expect(t.owedToMe, 45000);
      expect(t.iOwe, 30000);
      expect(t.net, 15000);
    });

    test('una meta compartida', () async {
      final goals = await MockSharedGoalsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final g = goals.single;
      expect(g.saved, 2100000);
      expect(g.missing, 3900000);
      expect(g.ratio, closeTo(0.35, 1e-9));
      expect(g.byMember[meId], 1200000);
      expect(g.byMember['sg-sai-laura'], 900000);
      expect(g.fairShare, 3000000);
      expect(g.done, isFalse);
    });
  });

  group('Pantallas: grupos', () {
    testWidgets('el centro de compartir resume cada cosa', (tester) async {
      await openRoute(tester, Routes.sharingHub);
      expect(find.text('Grupos'), findsOneWidget);
      expect(find.text(r'2 grupos · Debes $130.000'), findsOneWidget);
      expect(find.text(r'Te deben $15.000'), findsOneWidget);
      expect(find.text(r'1 meta · $2.100.000 ahorrados'), findsOneWidget);
    });

    testWidgets('la lista de grupos muestra tu saldo en cada uno', (
      tester,
    ) async {
      await openRoute(tester, Routes.groups);
      expect(find.text('En total debes'), findsOneWidget);
      expect(find.text('Casa'), findsOneWidget);
      expect(find.text(r'Te deben $30.000'), findsOneWidget);
      expect(find.text(r'Debes $160.000'), findsOneWidget);
    });

    testWidgets('el detalle dice quién debe qué', (tester) async {
      await openRoute(tester, Routes.group('g-viaje'));
      expect(find.text(r'Debes $160.000'), findsOneWidget);
      expect(find.text(r'Le deben $530.000'), findsOneWidget);
      expect(find.text(r'Debe $370.000'), findsOneWidget);
      expect(find.text('Hotel'), findsOneWidget);
    });

    testWidgets('saldar cuentas anota el pago', (tester) async {
      await openRoute(tester, Routes.group('g-viaje'));
      await tester.tap(find.text('Saldar cuentas'));
      await tester.pumpAndSettle();
      expect(find.text('Tú le pagas a Laura'), findsOneWidget);
      expect(find.text('Andrés le paga a Laura'), findsOneWidget);
      await tester.tap(find.text(r'Ya pagó $160.000'));
      await tester.pumpAndSettle();
      expect(find.text('Anotamos tu pago a Laura'), findsOneWidget);
      // Ya no debes nada en el viaje.
      expect(find.text('Estás a mano'), findsOneWidget);
    });

    testWidgets('un grupo a mano muestra que todos están al día', (
      tester,
    ) async {
      final container = await openRoute(tester, Routes.group('g-casa'));
      expect(find.text('Saldar cuentas'), findsOneWidget);
      await tester.tap(find.text('Saldar cuentas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(r'Ya pagó $30.000'));
      await tester.pumpAndSettle();
      expect(find.text('Todos están a mano.'), findsOneWidget);
      expect(container, isNotNull);
    });

    testWidgets('agregar un gasto lo reparte entre todos', (tester) async {
      final container = await openRoute(
        tester,
        Routes.addSharedExpense('g-casa'),
      );
      await tester.tap(find.text('Guardar gasto'));
      await tester.pump();
      expect(find.text('Escribe qué fue el gasto.'), findsOneWidget);
      expect(find.text('Escribe cuánto fue.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'Gas');
      await tester.enterText(find.byType(TextField).at(1), '60000');
      await tester.pump();
      expect(find.text(r'Le toca $30.000 a cada una.'), findsOneWidget);
      await tester.tap(find.text('Guardar gasto'));
      await tester.pumpAndSettle();
      expect(find.text('Anotamos Gas'), findsOneWidget);
      // Casa: ahora Laura te debe 30.000 + 30.000.
      unawaited(
        container.read(routerProvider).push<void>(Routes.group('g-casa')),
      );
      await tester.pumpAndSettle();
      expect(find.text(r'Te deben $60.000'), findsOneWidget);
    });

    testWidgets('crear un grupo pide nombre y una persona', (tester) async {
      await openRoute(tester, Routes.newGroup);
      await tester.tap(find.widgetWithText(FilledButton, 'Crear grupo'));
      await tester.pump();
      expect(find.text('Ponle un nombre al grupo.'), findsOneWidget);
      expect(find.text('Agrega al menos a una persona.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'Oficina');
      await tester.enterText(find.byType(TextField).at(1), 'Marta');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Crear grupo'));
      await tester.pumpAndSettle();
      expect(find.text('Creamos el grupo Oficina'), findsOneWidget);
      expect(find.text('Aún no hay gastos.'), findsOneWidget);
    });
  });

  group('Pantallas: dividir y deudas', () {
    testWidgets('dividir una cuenta y anotar lo que te deben', (tester) async {
      await openRoute(tester, Routes.splitBill);
      await tester.enterText(find.byType(TextField).first, '300000');
      await tester.pump();
      await tester.tap(find.byTooltip('Una persona más'));
      await tester.tap(find.byTooltip('Una persona más'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, '10 %'));
      await tester.pumpAndSettle();
      expect(find.text('4 personas'), findsOneWidget);
      expect(semanticsLabel('82.500 pesos'), findsWidgets);
      // Sin nombres no se puede anotar.
      final record = find.widgetWithText(
        FilledButton,
        'Anotar lo que me deben',
      );
      await tester.ensureVisible(record);
      expect(tester.widget<FilledButton>(record).onPressed, isNull);
      await tester.enterText(
        find.widgetWithText(TextField, 'Persona 1'),
        'Sara',
      );
      await tester.pump();
      await tester.ensureVisible(record);
      await tester.tap(record);
      await tester.pumpAndSettle();
      expect(find.text('Anotamos lo que te debe Sara'), findsOneWidget);
      expect(find.text('Sara'), findsOneWidget);
      expect(find.text(r'$82.500'), findsWidgets);
    });

    testWidgets('las deudas se separan en te deben, debes y saldadas', (
      tester,
    ) async {
      await openRoute(tester, Routes.personDebts);
      expect(find.text('En total te deben'), findsOneWidget);
      expect(find.text('Te deben'), findsOneWidget);
      expect(find.text('Debes'), findsOneWidget);
      expect(find.text('Saldadas'), findsOneWidget);
      expect(find.text('Almuerzo del viernes · 20 de octubre'), findsOneWidget);
    });

    testWidgets('marcar una deuda como pagada', (tester) async {
      await openRoute(tester, Routes.personDebts);
      await tester.tap(find.text('Andrés'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ya me pagó'));
      await tester.pumpAndSettle();
      expect(find.text('Quedó saldada la deuda con Andrés'), findsOneWidget);
    });

    testWidgets('anotar una deuda valida y crea', (tester) async {
      await openRoute(tester, Routes.newDebt);
      await tester.tap(find.widgetWithText(FilledButton, 'Anotar deuda'));
      await tester.pump();
      expect(find.text('Escribe el nombre de la persona.'), findsOneWidget);
      await tester.tap(find.text('Debes'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).at(0), 'Mamá');
      await tester.enterText(find.byType(TextField).at(1), '80000');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Anotar deuda'));
      await tester.pumpAndSettle();
      expect(find.text('Anotamos la deuda con Mamá'), findsOneWidget);
    });
  });

  group('Pantallas: metas compartidas', () {
    testWidgets('lista y detalle', (tester) async {
      await openRoute(tester, Routes.sharedGoals);
      expect(find.text('Han ahorrado juntos'), findsOneWidget);
      expect(find.text(r'$2.100.000 de $6.000.000'), findsOneWidget);
      await tester.tap(find.text('Viaje a San Andrés'));
      await tester.pumpAndSettle();
      expect(find.text(r'$3.900.000'), findsOneWidget);
      expect(find.text('Cuánto ha puesto cada uno'), findsOneWidget);
      expect(find.text(r'$3.000.000'), findsOneWidget);
    });

    testWidgets('aportar suma a quien aportó', (tester) async {
      await openRoute(tester, Routes.sharedGoal('sg-sai'));
      await tester.tap(find.text('Aportar a esta meta'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Laura'));
      await tester.enterText(find.byType(TextField), '500000');
      await tester.pump();
      await tester.tap(find.text(r'Aportar $500.000'));
      await tester.pumpAndSettle();
      expect(find.text(r'Laura aportó $500.000'), findsOneWidget);
      expect(find.text(r'$1.400.000'), findsOneWidget);
    });

    testWidgets('crear una meta compartida', (tester) async {
      await openRoute(tester, Routes.newSharedGoal);
      await tester.tap(find.widgetWithText(FilledButton, 'Crear meta'));
      await tester.pump();
      expect(find.text('Ponle un nombre a la meta.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'Regalo de bodas');
      await tester.enterText(find.byType(TextField).at(1), '900000');
      await tester.enterText(find.byType(TextField).at(2), 'Ana');
      await tester.pump();
      expect(find.textContaining(r'$450.000 por persona'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Crear meta'));
      await tester.pumpAndSettle();
      expect(find.text('Creamos la meta Regalo de bodas'), findsOneWidget);
    });

    testWidgets('desde Perfil se llega a Compartir', (tester) async {
      await openRoute(tester, Routes.profile);
      await scrollIntoView(tester, find.text('Compartir con otros'));
      await tester.tap(find.text('Compartir con otros'));
      await tester.pumpAndSettle();
      expect(find.text('Dividir una cuenta'), findsOneWidget);
    });
  });

  group('Capturas y accesibilidad', () {
    final routes = <String, String>{
      'hub': Routes.sharingHub,
      'groups': Routes.groups,
      'group_detail': Routes.group('g-viaje'),
      'add_expense': Routes.addSharedExpense('g-casa'),
      'new_group': Routes.newGroup,
      'split_bill': Routes.splitBill,
      'debts': Routes.personDebts,
      'new_debt': Routes.newDebt,
      'shared_goals': Routes.sharedGoals,
      'shared_goal_detail': Routes.sharedGoal('sg-sai'),
      'new_shared_goal': Routes.newSharedGoal,
    };
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final e in routes.entries) {
        testWidgets('${e.key} (${mode.name})', (tester) async {
          final handle = tester.ensureSemantics();
          await openRoute(tester, e.value, mode: mode);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/${e.key}_${mode.name}.png'),
          );
          await expectAccessible(tester);
          handle.dispose();
        });
      }
    }

    for (final e in routes.entries) {
      testWidgets('${e.key}: texto al 200 % no se rompe', (tester) async {
        await openRoute(tester, e.value, textScale: 2);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
