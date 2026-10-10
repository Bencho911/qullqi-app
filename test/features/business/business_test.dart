import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qullqi/features/business/data/invoices_repository.dart';
import 'package:qullqi/features/business/domain/business.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';

import '../../helpers/pump.dart';

Future<void> openBusinessHome(
  WidgetTester tester, {
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(390, 1500),
  double textScale = 1,
}) => pumpApp(
  tester,
  mode: mode,
  size: size,
  textScale: textScale,
  prefs: {'scope': 'business'},
);

void main() {
  final now = DateTime(2026, 10, 24, 14, 45);

  group('Cálculos', () {
    late List<Invoice> invoices;
    late List<Transaction> txs;
    setUpAll(() async {
      invoices = await MockInvoicesRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      txs = await MockTransactionsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
    });

    test('bimestre de IVA y su vencimiento', () {
      final p = ivaPeriod(now);
      expect(p.label, 'septiembre y octubre');
      expect(p.due, DateTime(2026, 11, ivaDueDay));
      expect(ivaPeriod(DateTime(2027, 1, 10)).label, 'enero y febrero');
      expect(ivaPeriod(DateTime(2026, 12, 3)).due, DateTime(2027, 1, 12));
    });

    test('estado de cada factura', () {
      Invoice f(String id) => invoices.firstWhere((i) => i.id == id);
      expect(f('f-42').statusAt(now), InvoiceStatus.pending);
      expect(f('f-41').statusAt(now), InvoiceStatus.overdue);
      expect(f('f-40').statusAt(now), InvoiceStatus.paid);
      expect(f('f-42').total, 1500000 + 285000);
    });

    test('IVA = cobrado en facturas − IVA de gastos del negocio', () {
      final iva = IvaEstimate.of(invoices, txs, now);
      expect(iva.generated, 285000 + 171000 + 380000);
      expect(iva.deductible, (142000 * 0.19 / 1.19).round()); // Figma
      expect(iva.toPay, iva.generated - iva.deductible);
    });

    test('un saldo a favor no se paga', () {
      final iva = IvaEstimate.of(const [], txs, now);
      expect(iva.toPay, 0);
    });

    test('resumen del negocio en el mes', () {
      final m = BusinessMonth.of(invoices, txs, now);
      expect(m.income, 2500000 + 1850000);
      expect(m.expense, 142000);
      expect(m.profit, 4208000);
      expect(m.receivable, 1785000 + 1071000);
      expect(m.overdueCount, 1);
    });
  });

  group('Pantallas', () {
    testWidgets('el Inicio del negocio muestra utilidad, cobros e IVA', (
      tester,
    ) async {
      await openBusinessHome(tester);
      expect(find.text('Utilidad de octubre'), findsOneWidget);
      expect(find.text(r'$4.208.000'), findsOneWidget);
      expect(find.text(r'$2.856.000 · 1 vencida'), findsOneWidget);
      expect(find.text('IVA de septiembre y octubre'), findsWidgets);
    });

    testWidgets('en Todo hay un acceso que lleva a la vista Negocio', (
      tester,
    ) async {
      await pumpApp(tester, size: const Size(390, 1500));
      await tester.tap(find.text('Tu negocio'));
      await tester.pumpAndSettle();
      expect(find.text('Utilidad de octubre'), findsOneWidget);
    });

    testWidgets('marcar una factura como pagada crea el ingreso', (
      tester,
    ) async {
      await openBusinessHome(tester);
      await tester.tap(find.text('Facturas por cobrar'));
      await tester.pumpAndSettle();
      expect(find.text('Vencidas'), findsOneWidget);
      await tester.tap(find.text('Café Origen S.A.S.'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Marcar como pagada'));
      await tester.pumpAndSettle();
      expect(find.text('¿A qué cuenta llegó la plata?'), findsOneWidget);
      await tester.tap(find.text('Daviplata'));
      await tester.pumpAndSettle();
      expect(find.text(r'F-0041 pagada: $1.071.000'), findsOneWidget);
      expect(find.text('Pagada'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Vencidas'), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      // El ingreso llegó: subió la utilidad del mes.
      expect(find.text(r'$5.279.000'), findsOneWidget);
    });

    testWidgets('registrar un cobro con IVA', (tester) async {
      await openBusinessHome(tester);
      await tester.tap(find.text('Facturas por cobrar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar cobro'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Tienda Ruda');
      await tester.enterText(find.byType(TextField).at(1), '1000000');
      await tester.pumpAndSettle();
      expect(find.text(r'$1.190.000'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Registrar cobro'));
      await tester.pumpAndSettle();
      expect(find.text(r'Registramos F-0043 por $1.190.000'), findsOneWidget);
      expect(find.text('Tienda Ruda'), findsOneWidget);
    });

    testWidgets('el IVA se explica con su cálculo', (tester) async {
      await openBusinessHome(tester);
      await tester.tap(find.text('IVA de septiembre y octubre').first);
      await tester.pumpAndSettle();
      expect(find.text('Bimestre de septiembre y octubre'), findsOneWidget);
      expect(find.text('IVA que cobraste'), findsOneWidget);
      expect(
        find.textContaining('Declaras hasta el 12 de noviembre'),
        findsOneWidget,
      );
    });
  });

  group('Capturas y accesibilidad', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('inicio del negocio (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await openBusinessHome(tester, mode: mode);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/business_home_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });
    }

    testWidgets('facturas, detalle, nuevo cobro e IVA', (tester) async {
      final handle = tester.ensureSemantics();
      await openBusinessHome(tester, size: phone);
      await tester.scrollUntilVisible(
        find.text('Facturas por cobrar'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Facturas por cobrar'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/invoices.png'),
      );
      await expectAccessible(tester);
      await tester.tap(find.text('Estudio Alameda S.A.S.'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/invoice_detail.png'),
      );
      await expectAccessible(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Registrar cobro'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/new_invoice.png'),
      );
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('IVA', (tester) async {
      final handle = tester.ensureSemantics();
      await openBusinessHome(tester);
      await tester.tap(find.text('IVA de septiembre y octubre').first);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/iva.png'),
      );
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('negocio con texto al 200 %', (tester) async {
      await openBusinessHome(tester, textScale: 2, size: const Size(390, 3600));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/business_home_text200.png'),
      );
    });
  });
}
