import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:inti/app/router.dart';
import 'package:inti/app/routes.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart';
import 'package:inti/features/notifications/domain/notice.dart';
import 'package:inti/features/taxes/domain/tax_calendar.dart';
import 'package:inti/features/transactions/data/transactions_repository.dart';

import '../../helpers/pump.dart';

const _tall = Size(390, 1700);

const _cedula42 = '{"type":"cedula","number":"1032454242"}';

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
  const doc = TaxDocument(type: TaxDocumentType.cedula, number: '1032454242');

  group('Documento', () {
    test('últimos dígitos', () {
      expect(doc.lastDigit, 2);
      expect(doc.order, 42);
      expect(doc.masked, 'Cédula •••• 4242');
      expect(doc.isValid, isTrue);
    });

    test('"00" va de último', () {
      const d = TaxDocument(type: TaxDocumentType.nit, number: '900123400');
      expect(d.order, 100);
      expect(d.lastDigit, 0);
    });

    test('muy corto no es válido', () {
      expect(
        const TaxDocument(type: TaxDocumentType.cedula, number: '123').isValid,
        isFalse,
      );
    });
  });

  group('Días hábiles', () {
    test('el tercer día hábil de octubre de 2026', () {
      // Jue 1, vie 2, lun 5.
      expect(nthBusinessDay(2026, 10, 3), DateTime(2026, 10, 5));
    });

    test('un mes que empieza en fin de semana', () {
      // 1 de agosto de 2026 es sábado: el primer día hábil es el 3.
      expect(nthBusinessDay(2026, 8, 1), DateTime(2026, 8, 3));
    });
  });

  group('Calendario de referencia', () {
    test('una persona sin negocio solo ve su renta, del año siguiente', () {
      final list = buildTaxCalendar(
        document: doc,
        now: now,
        hasBusiness: false,
      );
      expect(list, hasLength(1));
      expect(list.single.kind, ObligationKind.renta);
      // La de este año (9 de septiembre) ya pasó.
      expect(list.single.due, DateTime(2027, 9, 8));
    });

    test('quien tiene negocio ve retención, PILA y fechas de empleados', () {
      final list = buildTaxCalendar(document: doc, now: now, hasBusiness: true);
      final kinds = list.map((o) => o.kind).toSet();
      expect(kinds, containsAll(ObligationKind.values));
      // Del más cercano al más lejano.
      for (var i = 1; i < list.length; i++) {
        expect(list[i].due.isBefore(list[i - 1].due), isFalse);
      }
      final first = list.first;
      expect(first.kind, ObligationKind.pila);
      expect(first.due, DateTime(2026, 11, 9));
      expect(
        list.firstWhere((o) => o.kind == ObligationKind.retencion).due,
        DateTime(2026, 11, 13),
      );
      expect(
        list
            .where((o) => o.kind == ObligationKind.prima)
            .map((o) => o.due)
            .toSet(),
        {DateTime(2026, 12, 20), DateTime(2027, 6, 30)},
      );
      expect(
        list.every((o) => !o.due.isBefore(DateTime(2026, 10, 24))),
        isTrue,
      );
    });

    test('el último dígito mueve la retención', () {
      const d9 = TaxDocument(type: TaxDocumentType.nit, number: '900123459');
      final r = buildTaxCalendar(
        document: d9,
        now: now,
        hasBusiness: true,
      ).firstWhere((o) => o.kind == ObligationKind.retencion);
      // 9 + (9 - 1) = día hábil 17 de noviembre.
      expect(r.due, nthBusinessDay(2026, 11, 17));
      expect(r.due, isNot(DateTime(2026, 11, 13)));
    });
  });

  group('4x1000 y renta', () {
    test('con los datos de prueba', () async {
      final txs = await MockTransactionsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final accounts = await MockAccountsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final gmf = GmfEstimate.of(
        txs,
        debitAccountIds: {
          for (final a in accounts)
            if (!a.isCard) a.id,
        },
        scope: Scope.all,
        now: now,
      );
      // Éxito + Starbucks + Figma + Farmatodo + 2 Rappi; lo de tarjetas no.
      expect(gmf.base, 85400 + 18500 + 142000 + 63200 + 64000);
      expect(gmf.estimated, gmf.base * 4 ~/ 1000);

      final year = YearSummary.of(txs, scope: Scope.all, now: now);
      expect(year.income, 2500000 + 150000 + 1850000 + 2500000 + 1071000);
      expect(year.incomeByCategory.first.$1.id, 'honorarios');
      expect(year.incomeByCategory.first.$2, 6850000 + 1071000);
      expect(year.health, 63200);
    });

    test('en la vista Personal no cuenta lo del negocio', () async {
      final txs = await MockTransactionsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final year = YearSummary.of(txs, scope: Scope.personal, now: now);
      // Sin el anticipo y la asesoría del negocio.
      expect(year.income, 150000 + 2500000);
    });
  });

  group('Avisos', () {
    test('una fecha en 3 días avisa; una lejana no', () {
      final soon = Obligation(
        kind: ObligationKind.pila,
        title: 'Seguridad social (PILA)',
        detail: 'Aportes del mes',
        due: DateTime(2026, 10, 27),
      );
      final far = Obligation(
        kind: ObligationKind.renta,
        title: 'Declaración de renta',
        detail: 'Año gravable 2026',
        due: DateTime(2027, 9, 8),
      );
      final notices = buildNotices(
        now: now,
        accounts: const [],
        commitments: const [],
        transactions: const [],
        budgets: const [],
        invoices: const [],
        hasBusiness: true,
        enabled: NoticeKind.values.toSet(),
        obligations: [soon, far],
      );
      expect(notices, hasLength(1));
      expect(notices.single.title, startsWith('Seguridad social (PILA)'));
      expect(notices.single.route, Routes.taxes);
    });
  });

  group('Pantalla', () {
    testWidgets('sin documento pide el documento y valida', (tester) async {
      await openRoute(tester, Routes.taxes);
      expect(find.text('Fechas de referencia'), findsOneWidget);
      expect(find.text('Agrega tu documento para ver tus fechas.'), findsOne);
      await tester.tap(find.text('Guardar documento'));
      await tester.pump();
      expect(find.text('Escribe al menos 5 dígitos.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '1032454242');
      await tester.tap(find.text('Guardar documento'));
      await tester.pumpAndSettle();
      expect(find.text('Cédula •••• 4242'), findsOneWidget);
      expect(find.text('Declaración de renta'), findsOneWidget);
      expect(find.text('Guardar documento'), findsNothing);
    });

    testWidgets('con documento: fechas, 4x1000 y resumen de renta', (
      tester,
    ) async {
      await openRoute(tester, Routes.taxes, prefs: {'tax_document': _cedula42});
      expect(find.text('Cédula •••• 4242'), findsOneWidget);
      expect(find.text('Seguridad social (PILA)'), findsWidgets);
      expect(find.textContaining('IVA de'), findsOneWidget);
      expect(find.text(r'$373.100'), findsOneWidget);
      expect(find.text(r'$1.492'), findsOneWidget);
      await scrollIntoView(tester, find.text('Resumen para tu renta de 2026'));
      expect(find.text('Resumen para tu renta de 2026'), findsOneWidget);
      expect(find.text(r'$8.071.000'), findsOneWidget);
    });

    testWidgets('cambiar el documento vuelve al formulario', (tester) async {
      await openRoute(tester, Routes.taxes, prefs: {'tax_document': _cedula42});
      await tester.tap(find.text('Cambiar'));
      await tester.pumpAndSettle();
      expect(find.text('Guardar documento'), findsOneWidget);
    });

    testWidgets('un documento dañado se ignora', (tester) async {
      await openRoute(
        tester,
        Routes.taxes,
        prefs: {'tax_document': 'no es json'},
      );
      expect(find.text('Guardar documento'), findsOneWidget);
    });

    testWidgets('sin negocio no hay IVA ni fechas de empleados', (
      tester,
    ) async {
      await openRoute(
        tester,
        Routes.taxes,
        prefs: {
          'tax_document': _cedula42,
          'session_user': jsonEncode({
            'fullName': 'Camilo Restrepo Gómez',
            'email': 'c@q.app',
            'phone': '+57 310 555 0142',
            'hasBusiness': false,
          }),
        },
      );
      expect(find.textContaining('IVA de'), findsNothing);
      expect(find.text('Prima de servicios'), findsNothing);
      expect(find.text('Declaración de renta'), findsOneWidget);
    });

    testWidgets('desde Perfil se llega', (tester) async {
      await openRoute(tester, Routes.profile);
      await scrollIntoView(tester, find.text('Impuestos y obligaciones'));
      await tester.tap(find.text('Impuestos y obligaciones'));
      await tester.pumpAndSettle();
      expect(find.text('Fechas de referencia'), findsOneWidget);
    });
  });

  group('Capturas y accesibilidad', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('impuestos con documento (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await openRoute(
          tester,
          Routes.taxes,
          mode: mode,
          prefs: {'tax_document': _cedula42},
        );
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/taxes_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });
    }

    testWidgets('impuestos sin documento (light)', (tester) async {
      final handle = tester.ensureSemantics();
      await openRoute(tester, Routes.taxes);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/taxes_empty.png'),
      );
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('texto al 200 % no se rompe', (tester) async {
      await openRoute(
        tester,
        Routes.taxes,
        textScale: 2,
        prefs: {'tax_document': _cedula42},
      );
      expect(tester.takeException(), isNull);
    });
  });
}
