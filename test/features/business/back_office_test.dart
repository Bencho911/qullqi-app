import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:qullqi/app/router.dart';
import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/features/business/data/business_back_office.dart';
import 'package:qullqi/features/business/data/invoices_repository.dart';
import 'package:qullqi/features/business/domain/accountant.dart';
import 'package:qullqi/features/business/domain/bill.dart';
import 'package:qullqi/features/business/domain/business.dart';
import 'package:qullqi/features/business/domain/reconcile.dart';
import 'package:qullqi/features/commitments/domain/commitment.dart';
import 'package:qullqi/features/notifications/data/notices.dart';
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

Invoice invoice(
  String id,
  String client,
  int base,
  DateTime issued, {
  DateTime? paidOn,
}) => Invoice(
  id: id,
  client: client,
  number: 'F-$id',
  base: base,
  chargesIva: true,
  issued: issued,
  due: issued.add(const Duration(days: 15)),
  paidOn: paidOn,
);

Transaction deposit(
  String id,
  String title,
  int amount,
  DateTime date, {
  Ownership ownership = Ownership.business,
}) => Transaction(
  id: id,
  title: title,
  amount: amount,
  kind: TransactionKind.income,
  accountId: 'davivienda',
  categoryId: 'honorarios',
  ownership: ownership,
  date: date,
);

void main() {
  final now = DateTime(2026, 10, 24, 14, 45);

  group('Conciliación (cálculos)', () {
    final f = invoice('1', 'Café Origen S.A.S.', 900000, DateTime(2026, 10, 3));

    test('el mismo valor es coincidencia exacta', () {
      final s = suggestMatches(
        invoices: [f],
        transactions: [
          deposit('d', 'Transferencia', 1071000, DateTime(2026, 10, 22)),
        ],
        now: now,
      );
      expect(s, hasLength(1));
      expect(s.single.confidence, MatchConfidence.exact);
      expect(s.single.id, '1:d');
    });

    test('un valor parecido con el cliente en el nombre es "parecido"', () {
      final s = suggestMatches(
        invoices: [f],
        transactions: [
          deposit('d', 'Pago Cafe Origen', 1060000, DateTime(2026, 10, 22)),
        ],
        now: now,
      );
      expect(s.single.confidence, MatchConfidence.likely);
    });

    test('un valor distinto y sin el cliente no coincide', () {
      expect(
        suggestMatches(
          invoices: [f],
          transactions: [
            deposit('d', 'Otro cliente', 800000, DateTime(2026, 10, 22)),
          ],
          now: now,
        ),
        isEmpty,
      );
    });

    test('un depósito anterior a la factura no cuenta', () {
      expect(
        suggestMatches(
          invoices: [f],
          transactions: [deposit('d', 'x', 1071000, DateTime(2026, 10, 2))],
          now: now,
        ),
        isEmpty,
      );
    });

    test('lo personal no cuenta y un depósito se usa una sola vez', () {
      final g = invoice('2', 'Otro S.A.S.', 900000, DateTime(2026, 10, 4));
      final s = suggestMatches(
        invoices: [f, g],
        transactions: [
          deposit(
            'p',
            'x',
            1071000,
            DateTime(2026, 10, 22),
            ownership: Ownership.personal,
          ),
          deposit('d', 'x', 1071000, DateTime(2026, 10, 22)),
        ],
        now: now,
      );
      // Solo hay un depósito del negocio con ese valor: gana la factura más
      // antigua.
      expect(s, hasLength(1));
      expect(s.single.invoice.id, '1');
    });

    test('una factura pagada o una sugerencia descartada no vuelve', () {
      final paid = invoice(
        '3',
        'Café Origen',
        900000,
        DateTime(2026, 10, 3),
        paidOn: DateTime(2026, 10, 20),
      );
      final d = deposit('d', 'x', 1071000, DateTime(2026, 10, 22));
      expect(
        suggestMatches(invoices: [paid], transactions: [d], now: now),
        isEmpty,
      );
      expect(
        suggestMatches(
          invoices: [f],
          transactions: [d],
          now: now,
          dismissed: {'1:d'},
        ),
        isEmpty,
      );
    });
  });

  group('Cuentas por pagar (cálculos)', () {
    test('estado según la fecha', () {
      final b = Bill(
        id: 'b',
        supplier: 'P',
        concept: 'C',
        amount: 1,
        due: DateTime(2026, 10, 25),
        categoryId: 'otros',
      );
      expect(b.statusAt(now), BillStatus.pending);
      expect(
        Bill(
          id: 'b',
          supplier: 'P',
          concept: 'C',
          amount: 1,
          due: DateTime(2026, 10, 23),
          categoryId: 'otros',
        ).statusAt(now),
        BillStatus.overdue,
      );
      expect(b.paid(now).statusAt(now), BillStatus.paid);
    });

    test('las abiertas cuentan como pagos del negocio; las pagadas no', () {
      final open = Bill(
        id: 'o',
        supplier: 'Proveedor',
        concept: 'Insumos',
        amount: 100000,
        due: DateTime(2026, 11),
        categoryId: 'otros',
      );
      final commitments = withBillCommitments(const [], [open, open.paid(now)]);
      expect(commitments, hasLength(1));
      expect(commitments.single.title, 'Proveedor: Insumos');
      expect(commitments.single.ownership, Ownership.business);
      expect(commitments.single.kind, CommitmentKind.bill);
    });
  });

  group('Archivo para el contador', () {
    test('arma ventas, compras y movimientos del periodo', () {
      final export = buildAccountantExport(
        invoices: [
          invoice('1', 'Café, Origen', 900000, DateTime(2026, 10, 3)),
          invoice('0', 'Antiguo', 100000, DateTime(2026, 8, 3)),
        ],
        bills: [
          Bill(
            id: 'b',
            supplier: 'Papelería',
            concept: 'Insumos "A"',
            amount: 180000,
            due: DateTime(2026, 10, 21),
            categoryId: 'otros',
          ),
        ],
        transactions: [
          deposit('d', 'Pago', 500000, DateTime(2026, 10, 20)),
          deposit(
            'p',
            'Personal',
            9000,
            DateTime(2026, 10, 20),
            ownership: Ownership.personal,
          ),
        ],
        period: ExportPeriod.thisMonth,
        now: now,
      );
      final lines = export.csv.split('\n');
      expect(lines.first, accountantCsvHeader);
      // Una venta, una compra y un ingreso; lo personal y lo de agosto no.
      expect(export.rows, 3);
      expect(lines, hasLength(4));
      // Las celdas con coma o comillas van entre comillas.
      expect(export.csv, contains('"Café, Origen"'));
      expect(export.csv, contains('"Insumos ""A"""'));
      // Del más antiguo al más reciente.
      expect(lines[1], startsWith('venta,2026-10-03'));
      expect(lines[3], startsWith('compra,2026-10-21'));
    });

    test('el año completo incluye lo de agosto', () {
      final export = buildAccountantExport(
        invoices: [invoice('0', 'Antiguo', 100000, DateTime(2026, 8, 3))],
        bills: const [],
        transactions: const [],
        period: ExportPeriod.thisYear,
        now: now,
      );
      expect(export.rows, 1);
    });

    test('enero ve diciembre como mes pasado', () {
      final jan = DateTime(2027, 1, 10);
      expect(
        ExportPeriod.lastMonth.contains(DateTime(2026, 12, 5), jan),
        isTrue,
      );
      expect(
        ExportPeriod.lastMonth.contains(DateTime(2027, 1, 5), jan),
        isFalse,
      );
    });
  });

  group('Conciliar (pantalla)', () {
    testWidgets('sugiere el depósito de Café Origen', (tester) async {
      await openRoute(tester, Routes.reconcile);
      expect(find.text('Mismo valor'), findsOneWidget);
      expect(find.textContaining('F-0041'), findsOneWidget);
      expect(find.text('Transferencia Café Origen'), findsOneWidget);
    });

    testWidgets('confirmar deja la factura pagada y la sugerencia sale', (
      tester,
    ) async {
      final container = await openRoute(tester, Routes.reconcile);
      await tester.tap(find.text('Sí, es este pago'));
      await tester.pumpAndSettle();
      expect(find.text('Todo cuadra'), findsOneWidget);
      final invoices = (await tester.runAsync(
        () => container.read(invoicesRepositoryProvider).watch().first,
      ))!;
      expect(
        invoices.firstWhere((i) => i.number == 'F-0041').paidOn,
        isNotNull,
      );
    });

    testWidgets('descartar una sugerencia la guarda', (tester) async {
      final container = await openRoute(tester, Routes.reconcile);
      await tester.tap(find.text('No es este pago'));
      await tester.pumpAndSettle();
      expect(find.text('Todo cuadra'), findsOneWidget);
      expect(
        container.read(dismissedReconcileProvider),
        contains(startsWith('f-41:')),
      );
    });

    testWidgets('el detalle de la factura avisa que ya llegó el pago', (
      tester,
    ) async {
      await openRoute(tester, Routes.invoice('f-41'));
      expect(find.text('Parece que ya te pagaron'), findsOneWidget);
      await tester.tap(find.text('Conciliar'));
      await tester.pumpAndSettle();
      expect(find.text('Mismo valor'), findsOneWidget);
    });
  });

  group('Cuentas por pagar (pantallas)', () {
    testWidgets('lista agrupada con lo que debes', (tester) async {
      await openRoute(tester, Routes.bills);
      expect(find.text('Le debes a proveedores'), findsOneWidget);
      expect(semanticsLabel('630.000 pesos'), findsWidgets);
      expect(find.text('Vencidas'), findsOneWidget);
      expect(find.text('Por pagar'), findsOneWidget);
      expect(find.text('Pagadas'), findsOneWidget);
    });

    testWidgets('pagar una cuenta la deja pagada y baja el saldo', (
      tester,
    ) async {
      await openRoute(tester, Routes.bills);
      await tester.tap(find.text('Papelería El Norte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcar como pagada'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Davivienda').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Pagaste'), findsOneWidget);
      expect(semanticsLabel('450.000 pesos'), findsWidgets);
    });

    testWidgets('registrar una cuenta valida y crea', (tester) async {
      await openRoute(tester, Routes.newBill);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Registrar cuenta por pagar'),
      );
      await tester.pump();
      expect(find.text('Escribe a quién le debes.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'Taller Andino');
      await tester.enterText(find.byType(TextField).at(1), 'Mantenimiento');
      await tester.enterText(find.byType(TextField).at(2), '250000');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Registrar cuenta por pagar'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Registramos la cuenta de Taller Andino'), findsOne);
    });

    testWidgets('las cuentas abiertas llegan a los avisos', (tester) async {
      final container = await pumpApp(tester);
      final titles = container
          .read(noticesProvider)
          .requireValue
          .map((n) => n.title);
      expect(titles.any((t) => t.contains('Papelería El Norte')), isTrue);
      expect(titles, contains('Parece que Café Origen S.A.S. ya pagó'));
    });
  });

  group('Tu contador (pantalla)', () {
    testWidgets('muestra quién ve el negocio y cuántos registros hay', (
      tester,
    ) async {
      await openRoute(tester, Routes.accountant);
      expect(find.text('contadora@estudiocontable.co'), findsOneWidget);
      expect(find.textContaining('registros en este mes'), findsOneWidget);
      expect(find.text('Copiar archivo (CSV)'), findsOneWidget);
    });

    testWidgets('invitar valida el correo y lo agrega', (tester) async {
      await openRoute(tester, Routes.accountant);
      await tester.enterText(find.byType(TextField), 'no-es-correo');
      await tester.tap(find.text('Invitar a mi contador'));
      await tester.pump();
      expect(find.text('Escribe un correo válido.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'nuevo@contador.co');
      await tester.tap(find.text('Invitar a mi contador'));
      await tester.pumpAndSettle();
      expect(find.text('nuevo@contador.co'), findsOneWidget);
      expect(find.textContaining('Invitación enviada'), findsOneWidget);
    });

    testWidgets('quitar el acceso pide confirmar', (tester) async {
      await openRoute(tester, Routes.accountant);
      await tester.tap(
        find.byTooltip('Quitar acceso a contadora@estudiocontable.co'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Quitar acceso a contadora@estudiocontable.co').last,
      );
      await tester.pumpAndSettle();
      expect(find.text('Quitamos el acceso'), findsOneWidget);
      expect(find.text('contadora@estudiocontable.co'), findsNothing);
    });

    testWidgets('copiar el archivo avisa cuántos registros', (tester) async {
      await openRoute(tester, Routes.accountant);
      await tester.tap(find.text('Copiar archivo (CSV)'));
      await tester.pump();
      expect(find.textContaining('para tu contador'), findsOneWidget);
    });

    testWidgets('desde el centro se llega a cada herramienta nueva', (
      tester,
    ) async {
      await openRoute(tester, Routes.businessHub);
      expect(find.text('Conciliar cobros'), findsOneWidget);
      expect(find.text('Cuentas por pagar'), findsOneWidget);
      expect(find.text('Tu contador'), findsOneWidget);
    });
  });

  group('Capturas y accesibilidad', () {
    final routes = <String, String>{
      'reconcile': Routes.reconcile,
      'bills': Routes.bills,
      'new_bill': Routes.newBill,
      'accountant': Routes.accountant,
      'hub_full': Routes.businessHub,
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
