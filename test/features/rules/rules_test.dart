import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:qullqi/app/router.dart';
import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/storage/prefs.dart';
import 'package:qullqi/features/anomalies/domain/anomalies.dart';
import 'package:qullqi/features/notifications/data/notices.dart';
import 'package:qullqi/features/rules/data/rules_provider.dart';
import 'package:qullqi/features/rules/domain/category_rule.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';

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

Transaction expense(
  String id,
  String title,
  int amount,
  DateTime date, {
  String account = 'nequi',
  String category = 'otros',
}) => Transaction(
  id: id,
  title: title,
  amount: amount,
  kind: TransactionKind.expense,
  accountId: account,
  categoryId: category,
  ownership: Ownership.personal,
  date: date,
);

void main() {
  final now = DateTime(2026, 10, 24, 14, 45);

  group('Reglas', () {
    test('coincide sin importar mayúsculas ni tildes', () {
      const r = CategoryRule(keyword: 'exito', categoryId: 'mercado');
      expect(r.matches('Éxito Chapinero'), isTrue);
      expect(r.matches('ÉXITO'), isTrue);
      expect(r.matches('Carulla'), isFalse);
      expect(
        const CategoryRule(keyword: ' ', categoryId: 'x').matches('a'),
        isFalse,
      );
    });

    test('gana la palabra más específica', () {
      const rules = [
        CategoryRule(keyword: 'Uber', categoryId: 'transporte'),
        CategoryRule(keyword: 'Uber Eats', categoryId: 'salidas'),
      ];
      expect(ruleFor('Uber Eats Colombia', rules)?.categoryId, 'salidas');
      expect(ruleFor('Uber viaje', rules)?.categoryId, 'transporte');
      expect(ruleFor('Rappi', rules), isNull);
    });

    test('a qué movimientos cambia: no a traslados ni a los ya iguales', () {
      const rule = CategoryRule(keyword: 'rappi', categoryId: 'salidas');
      final txs = [
        expense('a', 'Rappi pedido', 30000, now),
        expense('b', 'Rappi pedido', 30000, now, category: 'salidas'),
        Transaction(
          id: 'c',
          title: 'Rappi',
          amount: 1,
          kind: TransactionKind.transfer,
          accountId: 'nequi',
          categoryId: 'traslado',
          ownership: Ownership.personal,
          date: now,
        ),
      ];
      expect(affectedBy(rule, txs).map((t) => t.id), ['a']);
    });

    testWidgets('la misma palabra reemplaza a la regla anterior', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      final rules = container.read(categoryRulesProvider.notifier);
      await rules.add(keyword: 'Rappi', categoryId: 'salidas');
      await rules.add(keyword: 'rappi', categoryId: 'mercado');
      final all = container.read(categoryRulesProvider);
      expect(all, hasLength(1));
      expect(all.single.categoryId, 'mercado');
      await rules.remove(all.single.id);
      expect(container.read(categoryRulesProvider), isEmpty);
    });

    testWidgets('las reglas se guardan en el teléfono', (tester) async {
      final container = await pumpApp(tester);
      await container
          .read(categoryRulesProvider.notifier)
          .add(keyword: 'Rappi', categoryId: 'salidas');
      final saved = container
          .read(sharedPreferencesProvider)
          .getStringList('category_rules');
      expect(saved, ['{"keyword":"Rappi","categoryId":"salidas"}']);
    });

    testWidgets('una regla dañada no rompe las demás', (tester) async {
      final c = await pumpApp(
        tester,
        prefs: {
          'category_rules': [
            'no es json',
            '{"keyword":"Uber","categoryId":"transporte"}',
          ],
        },
      );
      expect(c.read(categoryRulesProvider).map((r) => r.keyword), ['Uber']);
    });
  });

  group('Pantallas de reglas', () {
    testWidgets('sin reglas se explica y ofrece crear una', (tester) async {
      await openRoute(tester, Routes.rules);
      expect(find.text('Enséñale a clasificar'), findsOneWidget);
      await tester.tap(find.text('Crear regla'));
      await tester.pumpAndSettle();
      expect(find.text('Cuando el comercio diga…'), findsOneWidget);
    });

    testWidgets('crear una regla y aplicarla a lo anterior', (tester) async {
      final handle = tester.ensureSemantics();
      final container = await openRoute(tester, Routes.newRule);
      await tester.tap(find.widgetWithText(FilledButton, 'Crear regla'));
      await tester.pump();
      expect(
        find.text('Escribe al menos 2 letras del comercio.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).first, 'Rappi');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Cafés y salidas'));
      await tester.pumpAndSettle();
      // Los dos pedidos de Rappi pasan de "Otros" a "Cafés y salidas".
      expect(find.text('Cambia 2 movimientos.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Crear regla'));
      await tester.pumpAndSettle();
      expect(
        find.text('Creamos la regla y cambiamos 2 movimientos'),
        findsOneWidget,
      );
      final txs = container.read(transactionsProvider).requireValue;
      expect(
        txs
            .where((t) => t.title == 'Rappi pedido')
            .every((t) => t.categoryId == 'salidas'),
        isTrue,
      );
      handle.dispose();
    });

    testWidgets('no aplicar a lo anterior deja los movimientos como están', (
      tester,
    ) async {
      final container = await openRoute(tester, Routes.newRule);
      await tester.enterText(find.byType(TextField).first, 'Rappi');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Cafés y salidas'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Crear regla'));
      await tester.pumpAndSettle();
      expect(find.text('Creamos la regla de Rappi'), findsOneWidget);
      final txs = container.read(transactionsProvider).requireValue;
      expect(
        txs
            .where((t) => t.title == 'Rappi pedido')
            .every((t) => t.categoryId == 'otros'),
        isTrue,
      );
    });

    testWidgets('la lista muestra las reglas y permite quitarlas', (
      tester,
    ) async {
      await openRoute(
        tester,
        Routes.rules,
        prefs: {
          'category_rules': ['{"keyword":"Rappi","categoryId":"salidas"}'],
        },
      );
      expect(find.text('Si dice «Rappi»'), findsOneWidget);
      expect(find.textContaining('2 movimientos'), findsOneWidget);
      await tester.tap(find.byTooltip('Quitar la regla de Rappi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Quitar regla de Rappi'));
      await tester.pumpAndSettle();
      expect(find.text('Enséñale a clasificar'), findsOneWidget);
    });

    testWidgets('desde el detalle de un movimiento se crea con su comercio', (
      tester,
    ) async {
      await openRoute(tester, Routes.transaction('t19'));
      await tester.tap(find.text('Crear regla con este comercio'));
      await tester.pumpAndSettle();
      expect(find.text('Cuando el comercio diga…'), findsOneWidget);
      expect(find.text('Rappi pedido'), findsOneWidget);
    });

    testWidgets('desde Perfil se llega a las reglas', (tester) async {
      await openRoute(tester, Routes.profile);
      await scrollIntoView(tester, find.text('Reglas de categorías'));
      await tester.tap(find.text('Reglas de categorías'));
      await tester.pumpAndSettle();
      expect(find.text('Enséñale a clasificar'), findsOneWidget);
    });
  });

  group('Cobros raros', () {
    test('en los datos de prueba', () async {
      final txs = await MockTransactionsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final found = detectAnomalies(txs, now);
      final byKind = {for (final a in found) a.kind: a};
      expect(byKind.keys, {
        AnomalyKind.duplicate,
        AnomalyKind.unusual,
        AnomalyKind.bankFee,
      });
      expect(byKind[AnomalyKind.duplicate]!.transaction.id, 't20');
      expect(byKind[AnomalyKind.unusual]!.transaction.id, 't1');
      expect(byKind[AnomalyKind.unusual]!.reference, 35000);
      expect(byKind[AnomalyKind.bankFee]!.transaction.id, 't21');
      // Netflix subió de precio, pero eso no es un cobro raro.
      expect(found.any((a) => a.transaction.title == 'Netflix'), isFalse);
    });

    test('dos cobros iguales en cuentas distintas no son duplicado', () {
      final d = DateTime(2026, 10, 23, 10);
      expect(
        detectAnomalies([
          expense('a', 'Uber', 20000, d),
          expense(
            'b',
            'Uber',
            20000,
            d.add(const Duration(hours: 1)),
            account: 'visa',
          ),
        ], now),
        isEmpty,
      );
    });

    test('con menos de 3 compras previas no hay "lo normal"', () {
      expect(
        detectAnomalies([
          expense('a', 'Mercado', 30000, DateTime(2026, 9)),
          expense('b', 'Mercado', 30000, DateTime(2026, 9, 15)),
          expense('c', 'Mercado', 200000, DateTime(2026, 10, 23)),
        ], now),
        isEmpty,
      );
    });

    test('un cobro alto pero poco más que lo normal no es raro', () {
      expect(
        detectAnomalies([
          for (var i = 0; i < 3; i++)
            expense('p$i', 'Droguería', 10000, DateTime(2026, 8 + i, 5)),
          // 2 veces lo normal, pero solo $10.000 de diferencia.
          expense('n', 'Droguería', 20000, DateTime(2026, 10, 23)),
        ], now),
        isEmpty,
      );
    });

    test('un cobro viejo ya no avisa', () {
      expect(
        detectAnomalies([
          for (var i = 0; i < 3; i++)
            expense('p$i', 'Taller', 100000, DateTime(2026, 5 + i, 5)),
          expense('n', 'Taller', 500000, DateTime(2026, 10)),
        ], now),
        isEmpty,
      );
    });
  });

  group('Avisos y detalle', () {
    testWidgets('los cobros raros llegan a los avisos', (tester) async {
      final container = await pumpApp(tester);
      final titles = container
          .read(noticesProvider)
          .requireValue
          .map((n) => n.title);
      expect(titles, contains('Posible cobro duplicado: Rappi pedido'));
      expect(titles, contains('Cobro más alto de lo normal: Éxito Chapinero'));
      expect(titles, contains('Cobro del banco: Cuota de manejo tarjeta'));
    });

    testWidgets('el detalle avisa cuando el cobro es raro', (tester) async {
      await openRoute(tester, Routes.transaction('t20'));
      expect(find.text('Posible cobro duplicado'), findsOneWidget);
    });

    testWidgets('un cobro normal no muestra aviso', (tester) async {
      await openRoute(tester, Routes.transaction('t4'));
      expect(find.text('Posible cobro duplicado'), findsNothing);
      expect(find.text('Más alto de lo normal'), findsNothing);
    });
  });

  group('Accesibilidad', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('reglas (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await openRoute(
          tester,
          Routes.rules,
          mode: mode,
          prefs: {
            'category_rules': [
              '{"keyword":"Rappi","categoryId":"salidas"}',
              '{"keyword":"Uber","categoryId":"transporte"}',
            ],
          },
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/rules_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });

      testWidgets('crear regla (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await openRoute(
          tester,
          Routes.newRuleFor(keyword: 'Rappi pedido', categoryId: 'salidas'),
          mode: mode,
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/rule_editor_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });
    }

    for (final route in [Routes.rules, Routes.newRule]) {
      testWidgets('texto al 200 % no se rompe: $route', (tester) async {
        await openRoute(tester, route, textScale: 2);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
