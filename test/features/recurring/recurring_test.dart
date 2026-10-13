import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qullqi/app/router.dart';
import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/commitments/data/commitments_repository.dart';
import 'package:qullqi/features/home/domain/forecast.dart';
import 'package:qullqi/features/home/domain/money_summary.dart';
import 'package:qullqi/features/notifications/data/notices.dart';
import 'package:qullqi/features/recurring/domain/recurring.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';

import '../../helpers/pump.dart';

const _tall = Size(390, 1700);

Future<void> openRoute(
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
}

Transaction spend(
  String id,
  String title,
  int amount,
  DateTime date, {
  Ownership ownership = Ownership.personal,
  TransactionKind kind = TransactionKind.expense,
}) => Transaction(
  id: id,
  title: title,
  amount: amount,
  kind: kind,
  accountId: 'nequi',
  categoryId: Categories.subscriptions.id,
  ownership: ownership,
  date: date,
);

void main() {
  final now = DateTime(2026, 10, 24, 14, 45);

  group('Nombre de un cobro', () {
    test('sin meses, números ni tildes', () {
      expect(recurringKey('Arriendo septiembre'), 'arriendo');
      expect(recurringKey('Arriendo AGOSTO'), 'arriendo');
      expect(recurringKey('Éxito Chapinero #3'), 'exito chapinero');
      // "mayo" dentro de otra palabra no se toca.
      expect(recurringKey('Mayorista Norte'), 'mayorista norte');
    });
  });

  group('Detección', () {
    test('en los datos de prueba: Netflix y Spotify', () async {
      final txs = await MockTransactionsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final found = detectRecurring(txs, now);
      expect(found.map((c) => c.key), ['spotify', 'netflix']);

      final netflix = found.firstWhere((c) => c.key == 'netflix');
      expect(netflix.amount, 38900);
      expect(netflix.previousAmount, 34900);
      expect(netflix.change, 4000);
      expect(netflix.priceUp, isTrue);
      expect(netflix.nextDate, DateTime(2026, 11, 20));
      expect(netflix.history, hasLength(3));

      final spotify = found.firstWhere((c) => c.key == 'spotify');
      expect(spotify.priceUp, isFalse);
      expect(spotify.nextDate, DateTime(2026, 10, 28));
      expect(monthlyTotal(found), 55800);
    });

    test('un solo cobro no es recurrente', () {
      expect(
        detectRecurring([spend('a', 'Gym', 90000, DateTime(2026, 10, 3))], now),
        isEmpty,
      );
    });

    test('dos cobros el mismo día son un duplicado, no un recurrente', () {
      final d = DateTime(2026, 10, 20, 9);
      expect(
        detectRecurring([
          spend('a', 'Rappi', 32000, d),
          spend('b', 'Rappi', 32000, d.add(const Duration(hours: 1))),
        ], now),
        isEmpty,
      );
    });

    test('cada semana tampoco es mensual', () {
      expect(
        detectRecurring([
          for (var i = 0; i < 4; i++)
            spend('w$i', 'Lavandería', 20000, DateTime(2026, 10, 3 + 7 * i)),
        ], now),
        isEmpty,
      );
    });

    test('si dejó de cobrarse hace más de 45 días, ya no aparece', () {
      expect(
        detectRecurring([
          spend('a', 'Gym', 90000, DateTime(2026, 7, 5)),
          spend('b', 'Gym', 90000, DateTime(2026, 8, 5)),
        ], now),
        isEmpty,
      );
    });

    test('un ingreso o un traslado no cuentan', () {
      expect(
        detectRecurring([
          for (final k in [TransactionKind.income, TransactionKind.transfer])
            for (final m in [9, 10])
              spend('$k$m', 'Nómina', 2000000, DateTime(2026, m, 25), kind: k),
        ], now),
        isEmpty,
      );
    });

    test('el 31 pasa al último día del mes siguiente', () {
      final found = detectRecurring([
        spend('a', 'Seguro', 50000, DateTime(2026, 12, 31)),
        spend('b', 'Seguro', 50000, DateTime(2027, 1, 31)),
      ], DateTime(2027, 2, 3));
      expect(found.single.nextDate, DateTime(2027, 2, 28));
    });

    test('el mismo nombre en personal y en negocio son cobros distintos', () {
      final found = detectRecurring([
        spend('a', 'Google', 10000, DateTime(2026, 9, 10)),
        spend('b', 'Google', 10000, DateTime(2026, 10, 10)),
        spend(
          'c',
          'Google',
          25000,
          DateTime(2026, 9, 12),
          ownership: Ownership.business,
        ),
        spend(
          'd',
          'Google',
          25000,
          DateTime(2026, 10, 12),
          ownership: Ownership.business,
        ),
      ], now);
      expect(found, hasLength(2));
      expect(found.map((c) => c.amount).toSet(), {10000, 25000});
    });
  });

  group('Cómo va tu mes', () {
    test('con los datos de prueba', () async {
      final txs = await MockTransactionsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final accounts = await MockAccountsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final commitments = await MockCommitmentsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final summary = MoneySummary.compute(
        accounts: accounts,
        commitments: commitments,
        scope: Scope.all,
        now: now,
      );
      final fixed = {
        for (final c in detectRecurring(txs, now)) c.key,
        for (final c in commitments) recurringKey(c.title),
      };
      final f = MonthForecast.compute(
        summary: summary,
        transactions: txs,
        fixedKeys: fixed,
        now: now,
      );
      expect(f.daysLeft, 8);
      // Visa 1.320.000 + internet 89.000 + Claro 89.000 vencen este mes; el
      // arriendo vence el 1 de noviembre.
      expect(f.dueThisMonth, 1498000);
      expect(f.free, 7800000 - 1498000);
      expect(f.perDay, (7800000 - 1498000) ~/ 8);
      // Éxito + Starbucks + Figma + Terpel + Farmatodo + 2 Rappi + cuota de
      // manejo en 30 días; Netflix, Spotify y el arriendo van aparte.
      expect(f.typicalDaily, 473000 ~/ 30);
      expect(f.projectedEnd, f.free - f.typicalDaily * 7);
      expect(f.runsShort, isFalse);
    });

    test('si el ritmo supera lo que hay, avisa que se queda corto', () {
      const summary = MoneySummary(
        liquid: 100000,
        committed: 0,
        netWorth: 100000,
        payments: [],
      );
      final f = MonthForecast.compute(
        summary: summary,
        transactions: [spend('a', 'Fiesta', 600000, now)],
        fixedKeys: const {},
        now: now,
      );
      expect(f.typicalDaily, 20000);
      expect(f.projectedEnd, 100000 - 20000 * 7);
      expect(f.runsShort, isTrue);
    });

    test('sin plata libre, la cifra diaria es cero', () {
      final f = MonthForecast.compute(
        summary: const MoneySummary(
          liquid: 0,
          committed: 0,
          netWorth: 0,
          payments: [],
        ),
        transactions: const [],
        fixedKeys: const {},
        now: now,
      );
      expect(f.perDay, 0);
      expect(f.projectedEnd, 0);
    });
  });

  group('Pantallas', () {
    testWidgets('lo que se repite cada mes y lo que subió', (tester) async {
      await openRoute(tester, Routes.recurring);
      expect(find.text('Pagas cada mes'), findsOneWidget);
      expect(semanticsLabel('55.800 pesos'), findsWidgets);
      expect(find.text('2 cobros que se repiten'), findsOneWidget);
      expect(find.text('Un cobro subió de precio'), findsOneWidget);
      expect(find.text('Netflix'), findsOneWidget);
      expect(find.text('Spotify'), findsOneWidget);
      expect(find.text(r'Subió $4.000'), findsOneWidget);
      expect(find.text('Cada mes · se cobra el 28 de octubre'), findsOneWidget);
    });

    testWidgets('tocar un cobro muestra su historial', (tester) async {
      await openRoute(tester, Routes.recurring);
      await tester.tap(find.text('Netflix'));
      await tester.pumpAndSettle();
      expect(find.text('Ver el último movimiento'), findsOneWidget);
      expect(find.text(r'$34.900'), findsNWidgets(2));
      await tester.tap(find.text('Ver el último movimiento'));
      await tester.pumpAndSettle();
      expect(find.text('Netflix'), findsWidgets);
    });

    testWidgets('el Inicio muestra cómo va el mes', (tester) async {
      await pumpApp(tester, size: _tall);
      expect(find.text('Cómo va tu mes'), findsOneWidget);
      expect(find.text('Puedes gastar por día'), findsOneWidget);
      expect(find.text('A fin de mes tendrías'), findsOneWidget);
    });

    testWidgets('desde Planes se llega a los pagos recurrentes', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: _tall);
      await tester.tap(find.bySemanticsLabel(RegExp('^Planes, pestaña')));
      await tester.pumpAndSettle();
      expect(find.text(r'2 cobros · $55.800 al mes'), findsOneWidget);
      await tester.tap(find.text('Pagos recurrentes'));
      await tester.pumpAndSettle();
      expect(find.text('Pagas cada mes'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('sin cobros que se repitan se explica qué hacer', (
      tester,
    ) async {
      // En la vista Negocio no hay ninguno.
      await openRoute(tester, Routes.recurring, prefs: {'scope': 'business'});
      expect(find.text('Aún no vemos cobros que se repitan'), findsOneWidget);
    });
  });

  group('Avisos', () {
    testWidgets('una suscripción que sube de precio avisa', (tester) async {
      final container = await pumpApp(tester);
      final titles = container
          .read(noticesProvider)
          .requireValue
          .map((n) => n.title);
      expect(titles, contains('Netflix subió de precio'));
    });
  });

  group('Accesibilidad', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('pagos recurrentes (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await openRoute(tester, Routes.recurring, mode: mode);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/recurring_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });
    }

    testWidgets('texto al 200 % no se rompe', (tester) async {
      await openRoute(tester, Routes.recurring, textScale: 2);
      expect(tester.takeException(), isNull);
    });
  });
}
