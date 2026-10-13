import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:qullqi/app/router.dart';
import 'package:qullqi/app/routes.dart';
import 'package:qullqi/features/business/data/invoices_repository.dart';
import 'package:qullqi/features/sales/data/sales_repositories.dart';
import 'package:qullqi/features/sales/domain/sales.dart';

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

  group('Cotizaciones (cálculos)', () {
    final quote = Quote(
      id: 'q',
      client: 'Cliente',
      number: 'C-0001',
      lines: const [
        QuoteLine(description: 'A', amount: 1800000),
        QuoteLine(description: 'B', amount: 600000),
      ],
      chargesIva: true,
      issued: DateTime(2026, 10, 19),
      validUntil: DateTime(2026, 11, 3),
      status: QuoteStatus.sent,
    );

    test('suma renglones e IVA', () {
      expect(quote.base, 2400000);
      expect(quote.iva, 456000);
      expect(quote.total, 2856000);
    });

    test('sin IVA, el total es el valor', () {
      final q = Quote(
        id: 'q',
        client: 'c',
        number: 'C-0002',
        lines: const [QuoteLine(description: 'A', amount: 1000)],
        chargesIva: false,
        issued: DateTime(2026, 10),
        validUntil: DateTime(2026, 11),
        status: QuoteStatus.draft,
      );
      expect(q.iva, 0);
      expect(q.total, 1000);
    });

    test('una enviada que pasó su fecha queda vencida', () {
      expect(quote.statusAt(DateTime(2026, 11)), QuoteStatus.sent);
      expect(quote.statusAt(DateTime(2026, 11, 4)), QuoteStatus.expired);
      // Una aceptada nunca se vence.
      expect(
        quote.copyWith(status: QuoteStatus.accepted).statusAt(DateTime(2027)),
        QuoteStatus.accepted,
      );
    });
  });

  group('Facturas recurrentes (cálculos)', () {
    const base = InvoiceTemplate(
      id: 't',
      client: 'c',
      concept: 'x',
      base: 800000,
      chargesIva: true,
      dayOfMonth: 5,
      termDays: 15,
    );

    test('IVA y total', () {
      expect(base.iva, 152000);
      expect(base.total, 952000);
    });

    test('si el día ya pasó, la próxima es el mes siguiente', () {
      expect(base.nextIssue(now), DateTime(2026, 11, 5));
    });

    test('si el día aún no llega y no se ha emitido, es este mes', () {
      const t = InvoiceTemplate(
        id: 't',
        client: 'c',
        concept: 'x',
        base: 1,
        chargesIva: false,
        dayOfMonth: 28,
        termDays: 15,
      );
      expect(t.nextIssue(now), DateTime(2026, 10, 28));
      // Pero si ya se emitió este mes, pasa al siguiente.
      expect(
        t.copyWith(lastIssued: DateTime(2026, 10, 20)).nextIssue(now),
        DateTime(2026, 11, 28),
      );
    });

    test('un día que el mes no tiene cae en su último día', () {
      const t = InvoiceTemplate(
        id: 't',
        client: 'c',
        concept: 'x',
        base: 1,
        chargesIva: false,
        dayOfMonth: 31,
        termDays: 15,
      );
      expect(t.nextIssue(DateTime(2027, 2, 3)), DateTime(2027, 2, 28));
    });
  });

  group('Enlaces de pago (cálculos)', () {
    final link = PaymentLink(
      id: 'l',
      concept: 'x',
      amount: 1000,
      createdAt: DateTime(2026, 10, 20),
      expiresAt: DateTime(2026, 10, 30),
      status: PaymentLinkStatus.active,
      url: 'https://pago.qullqi.app/l/abc',
    );

    test('vence con la fecha', () {
      expect(link.statusAt(DateTime(2026, 10, 30)), PaymentLinkStatus.active);
      expect(link.statusAt(DateTime(2026, 10, 31)), PaymentLinkStatus.expired);
    });

    test('uno pagado o cancelado no cambia', () {
      expect(
        link.copyWith(status: PaymentLinkStatus.paid).statusAt(DateTime(2027)),
        PaymentLinkStatus.paid,
      );
    });
  });

  group('Repositorios', () {
    test('cotizaciones: numeración, envío y conversión', () async {
      final repo = MockQuotesRepository(now: () => now, latency: Duration.zero);
      final q = await repo.create(
        client: ' Nuevo ',
        lines: const [QuoteLine(description: 'A', amount: 100000)],
        chargesIva: true,
        validDays: 15,
        send: true,
      );
      expect(q.number, 'C-0004');
      expect(q.client, 'Nuevo');
      expect(q.status, QuoteStatus.sent);
      expect(q.validUntil, DateTime(2026, 11, 8));

      await repo.linkInvoice(q.id, 'f-99');
      final saved = (await repo.watch().first).firstWhere((x) => x.id == q.id);
      expect(saved.status, QuoteStatus.accepted);
      expect(saved.invoiceId, 'f-99');
    });

    test('plantillas: emitir marca el mes y pausar la apaga', () async {
      final repo = MockInvoiceTemplatesRepository(
        now: () => now,
        latency: Duration.zero,
      );
      final t = await repo.create(
        client: 'X',
        concept: 'Y',
        base: 500000,
        chargesIva: false,
        dayOfMonth: 10,
        termDays: 30,
      );
      expect(t.issuedThisMonth(now), isFalse);
      await repo.markIssued(t.id);
      await repo.setActive(t.id, active: false);
      final saved = (await repo.watch().first).firstWhere((x) => x.id == t.id);
      expect(saved.issuedThisMonth(now), isTrue);
      expect(saved.active, isFalse);
    });

    test('enlaces: se crean activos y se cancelan', () async {
      final repo = MockPaymentLinksRepository(
        now: () => now,
        latency: Duration.zero,
      );
      final l = await repo.create(
        concept: 'Anticipo',
        amount: 250000,
        validDays: 7,
      );
      expect(l.status, PaymentLinkStatus.active);
      expect(l.url, startsWith('https://pago.qullqi.app/l/'));
      expect(l.expiresAt, DateTime(2026, 10, 31));
      await repo.cancel(l.id);
      final saved = (await repo.watch().first).firstWhere((x) => x.id == l.id);
      expect(saved.status, PaymentLinkStatus.cancelled);
    });
  });

  group('Cotizaciones (pantallas)', () {
    testWidgets('lista agrupada con lo que espera respuesta', (tester) async {
      await openRoute(tester, Routes.quotes);
      expect(find.text('Esperando respuesta'), findsOneWidget);
      expect(semanticsLabel('2.856.000 pesos'), findsWidgets);
      expect(find.text('Por responder'), findsOneWidget);
      expect(find.text('Borradores'), findsOneWidget);
      expect(find.text('Cerradas'), findsOneWidget);
      expect(find.text('C-0003'), findsOneWidget);
    });

    testWidgets('aceptar una cotización crea la factura', (tester) async {
      final container = await openRoute(tester, Routes.quote('q-3'));
      expect(find.text('Estudio Alameda S.A.S.'), findsOneWidget);
      expect(semanticsLabel('2.856.000 pesos'), findsWidgets);
      await tester.tap(find.text('El cliente la aceptó'));
      await tester.pumpAndSettle();
      expect(find.text('Creamos la factura de C-0003'), findsOneWidget);
      expect(find.text('Ver la factura'), findsOneWidget);
      // Con la pantalla de Inicio tapada, el proveedor está en pausa: se lee
      // lo guardado directamente del repositorio.
      final invoices = (await tester.runAsync(
        () => container.read(invoicesRepositoryProvider).watch().first,
      ))!;
      expect(
        invoices.any(
          (i) => i.client == 'Estudio Alameda S.A.S.' && i.base == 2400000,
        ),
        isTrue,
      );
    });

    testWidgets('un borrador se marca como enviado', (tester) async {
      await openRoute(tester, Routes.quote('q-2'));
      await tester.tap(find.text('Marcar como enviada'));
      await tester.pumpAndSettle();
      expect(find.text('C-0002 quedó como enviada'), findsOneWidget);
      expect(find.text('El cliente la aceptó'), findsOneWidget);
    });

    testWidgets('crear una cotización valida y suma', (tester) async {
      await openRoute(tester, Routes.newQuote);
      await tester.tap(find.widgetWithText(FilledButton, 'Crear cotización'));
      await tester.pump();
      expect(find.text('Escribe el nombre del cliente.'), findsOneWidget);
      expect(
        find.text('Agrega al menos un renglón con descripción y valor.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField).at(0), 'Cliente Nuevo');
      await tester.enterText(find.byType(TextField).at(1), 'Logo');
      await tester.enterText(find.byType(TextField).at(2), '1000000');
      await tester.pump();
      expect(find.text(r'$1.190.000'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Crear cotización'));
      await tester.pumpAndSettle();
      expect(find.text('Creamos la cotización C-0004'), findsOneWidget);
      expect(find.text('Borrador'), findsWidgets);
    });

    testWidgets('se pueden agregar y quitar renglones', (tester) async {
      await openRoute(tester, Routes.newQuote);
      expect(find.text('Renglón 2'), findsNothing);
      await tester.tap(find.text('Agregar renglón'));
      await tester.pumpAndSettle();
      expect(find.text('Renglón 2'), findsOneWidget);
      await tester.tap(find.byTooltip('Quitar renglón 2'));
      await tester.pumpAndSettle();
      expect(find.text('Renglón 2'), findsNothing);
    });
  });

  group('Facturas recurrentes (pantallas)', () {
    testWidgets('lista con la próxima emisión', (tester) async {
      await openRoute(tester, Routes.invoiceTemplates);
      expect(find.text('Studio Norte'), findsOneWidget);
      expect(semanticsLabel('952.000 pesos'), findsWidgets);
      expect(
        find.text('Cada mes el 5 · próxima: 5 de noviembre'),
        findsOneWidget,
      );
      expect(find.text('Ya emitida este mes'), findsOneWidget);
    });

    testWidgets('pausar una plantilla', (tester) async {
      await openRoute(tester, Routes.invoiceTemplates);
      await tester.tap(find.text('Studio Norte'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pausar'));
      await tester.pumpAndSettle();
      expect(find.text('Pausamos la plantilla'), findsOneWidget);
      expect(find.text('Pausada'), findsOneWidget);
    });

    testWidgets('crear una plantilla y emitir la de este mes', (tester) async {
      final container = await openRoute(tester, Routes.newInvoiceTemplate);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Crear factura recurrente'),
      );
      await tester.pump();
      expect(find.text('Escribe el nombre del cliente.'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(0), 'Cliente Mensual');
      await tester.enterText(find.byType(TextField).at(1), 'Hosting');
      await tester.enterText(find.byType(TextField).at(2), '500000');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Crear factura recurrente'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Creamos la factura recurrente'), findsOneWidget);
      unawaited(
        container.read(routerProvider).push<void>(Routes.invoiceTemplates),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cliente Mensual'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Emitir la de este mes ahora'));
      await tester.pumpAndSettle();
      expect(find.text('Emitimos la factura de Cliente Mensual'), findsOne);
      // Con la pantalla de Inicio tapada, el proveedor está en pausa: se lee
      // lo guardado directamente del repositorio.
      final invoices = (await tester.runAsync(
        () => container.read(invoicesRepositoryProvider).watch().first,
      ))!;
      expect(invoices.any((i) => i.client == 'Cliente Mensual'), isTrue);
    });
  });

  group('Enlaces de pago (pantallas)', () {
    testWidgets('lista y estado de cada enlace', (tester) async {
      await openRoute(tester, Routes.paymentLinks);
      expect(find.text('Esperando que te paguen'), findsOneWidget);
      expect(semanticsLabel('1.000.000 pesos'), findsWidgets);
      expect(find.text('1 enlace activo'), findsOneWidget);
      expect(find.text('Pagado'), findsOneWidget);
      // El de hace 45 días ya se venció solo.
      expect(find.text('Vencido'), findsOneWidget);
    });

    testWidgets('un enlace se ve, se copia y se cancela', (tester) async {
      await openRoute(tester, Routes.paymentLinks);
      await tester.tap(find.text('Anticipo del sitio web'));
      await tester.pumpAndSettle();
      expect(find.text('https://pago.qullqi.app/l/qa7k2'), findsOneWidget);
      await tester.tap(find.text('Cancelar enlace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar enlace de Anticipo del sitio web'));
      await tester.pumpAndSettle();
      expect(find.text('Cancelamos el enlace'), findsOneWidget);
      expect(find.text('Cancelado'), findsOneWidget);
    });

    testWidgets('desde una factura parte con su valor', (tester) async {
      await openRoute(tester, Routes.newPaymentLinkFor('f-42'));
      expect(
        find.text('Para la factura F-0042 de Estudio Alameda S.A.S.'),
        findsOneWidget,
      );
      expect(find.text(r'$1.785.000'), findsOneWidget);
      await tester.tap(find.text('Crear enlace'));
      await tester.pumpAndSettle();
      expect(find.text('Creamos el enlace y lo copiamos'), findsOneWidget);
    });

    testWidgets('la factura ofrece crear su enlace', (tester) async {
      await openRoute(tester, Routes.invoice('f-42'));
      await tester.tap(find.text('Crear enlace de pago'));
      await tester.pumpAndSettle();
      expect(find.text('Factura F-0042'), findsOneWidget);
    });
  });

  group('Herramientas del negocio', () {
    testWidgets('el centro resume cada herramienta', (tester) async {
      await openRoute(tester, Routes.businessHub);
      expect(find.text('Facturas por cobrar'), findsOneWidget);
      expect(find.text('1 esperando respuesta'), findsOneWidget);
      expect(find.text('1 activa'), findsOneWidget);
      expect(find.text('1 activo'), findsOneWidget);
      await tester.tap(find.text('Cotizaciones'));
      await tester.pumpAndSettle();
      expect(find.text('Esperando respuesta'), findsOneWidget);
    });

    testWidgets('desde Perfil se llega al centro', (tester) async {
      await openRoute(tester, Routes.profile);
      await scrollIntoView(tester, find.text('Herramientas del negocio'));
      await tester.tap(find.text('Herramientas del negocio'));
      await tester.pumpAndSettle();
      expect(find.text('Vender y cobrar'), findsOneWidget);
    });
  });

  group('Capturas y accesibilidad', () {
    final routes = <String, String>{
      'hub': Routes.businessHub,
      'quotes': Routes.quotes,
      'quote_detail': Routes.quote('q-3'),
      'new_quote': Routes.newQuote,
      'templates': Routes.invoiceTemplates,
      'new_template': Routes.newInvoiceTemplate,
      'links': Routes.paymentLinks,
      'new_link': Routes.newPaymentLink,
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
