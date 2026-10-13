import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderContainer;
import 'package:flutter_test/flutter_test.dart';
import 'package:qullqi/app/router.dart';
import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/money/currency.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/accounts/domain/account.dart';
import 'package:qullqi/features/privacy/domain/data_export.dart';
import 'package:qullqi/features/profile/data/push_prefs.dart';
import 'package:qullqi/features/reports/domain/summaries.dart';
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

void main() {
  final now = DateTime(2026, 10, 24, 14, 45);

  group('Monedas', () {
    test('conversión y formato', () {
      expect(ExchangeRates.toCop(250, Currency.usd), 1025000);
      expect(ExchangeRates.toCop(10, Currency.cop), 10);
      expect(formatForeign(1200, Currency.eur), 'EUR 1.200');
      expect(Currency.cop.isHome, isTrue);
      expect(Currency.usd.isHome, isFalse);
    });

    test('una cuenta en dólares muestra su saldo y suma en pesos', () async {
      final repo = MockAccountsRepository(
        now: () => now,
        latency: Duration.zero,
      );
      final a = await repo.addManual(
        name: 'Ahorros EE. UU.',
        kind: AccountKind.savings,
        balance: ExchangeRates.toCop(250, Currency.usd),
        ownership: Ownership.personal,
        currency: Currency.usd,
      );
      expect(a.balance, 1025000);
      expect(a.isForeign, isTrue);
      expect(a.foreignBalance, 250);
      expect(a.secondaryLine, 'Ahorros •• 0000 · USD 250');
      // Gastar en pesos baja el saldo en dólares al mismo cambio.
      expect(a.applyDelta(-410000).foreignBalance, 150);
    });

    test('una cuenta en pesos no muestra moneda extranjera', () {
      final a = Account(
        id: 'a',
        institution: 'Nequi',
        kind: AccountKind.wallet,
        last4: '1234',
        ownership: Ownership.personal,
        balance: 500000,
        status: ConnectionStatus.manual,
        lastSync: now,
      );
      expect(a.isForeign, isFalse);
      expect(a.foreignBalance, isNull);
      expect(a.secondaryLine, 'Billetera •• 1234');
    });

    testWidgets('agregar una cuenta en dólares', (tester) async {
      final container = await openRoute(tester, Routes.manualAccount);
      await tester.enterText(find.byType(TextField).at(0), 'Ahorros EE. UU.');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Dólares'));
      await tester.pump();
      expect(find.text('Saldo de hoy en USD'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(1), '250');
      await tester.pump();
      expect(
        find.text(r'≈ $1.025.000 al cambio de referencia'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Agregar cuenta'));
      await tester.pumpAndSettle();
      final accounts = (await tester.runAsync(
        () => container.read(accountsRepositoryProvider).watch().first,
      ))!;
      final usd = accounts.firstWhere(
        (a) => a.institution == 'Ahorros EE. UU.',
      );
      expect(usd.currency, Currency.usd);
      expect(usd.balance, 1025000);
    });
  });

  group('Resúmenes (cálculos)', () {
    late List<Transaction> txs;
    setUpAll(() async {
      txs = await MockTransactionsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
    });

    test('últimos 7 días', () {
      final s = lastSevenDays(txs, now, Scope.all);
      expect(s.start, DateTime(2026, 10, 18));
      expect(s.end, DateTime(2026, 10, 24));
      expect(s.income, 5571000);
      expect(s.expense, 511900);
      expect(s.saved, 5059100);
      // En los 7 días anteriores no hubo movimientos.
      expect(s.previousExpense, 0);
      expect(s.count, 13);
      expect(s.byCategory.first.$1.id, 'software');
      expect(s.byCategory.first.$2, 142000);
      expect(s.biggest.map((t) => t.title), [
        'Figma y Notion',
        'Éxito Chapinero',
        'Terpel Calle 100',
      ]);
      expect(s.range, '18 al 24 de octubre');
    });

    test('el cierre de septiembre compara con agosto', () {
      final s = monthSummary(txs, DateTime(2026, 9), now, Scope.all);
      expect(s.title, 'Cierre de septiembre');
      expect(s.range, '1 al 30 de septiembre');
      // Arriendo + Netflix + Spotify + Éxito.
      expect(s.expense, 1286800);
      expect(s.income, 2500000);
      expect(s.previousExpense, 86800);
      expect(s.expenseChange, 1200000);
    });

    test('el mes en curso llega hasta hoy', () {
      final s = monthSummary(txs, now, now, Scope.all);
      expect(s.title, 'Este mes');
      expect(s.range, '1 al 24 de octubre');
    });

    test('en la vista Personal no cuenta lo del negocio', () {
      final s = lastSevenDays(txs, now, Scope.personal);
      expect(s.income, 150000);
      expect(s.expense, 511900 - 142000);
    });

    test('el texto para mandar', () {
      final text = summaryText(lastSevenDays(txs, now, Scope.all));
      expect(text, contains('Últimos 7 días (18 al 24 de octubre)'));
      expect(text, contains(r'Ingresos: $5.571.000'));
      expect(text, contains(r'Te sobró: $5.059.100'));
      expect(text, contains(r'- Software: $142.000'));
      expect(text, isNot(contains('periodo anterior')));
    });
  });

  group('Resúmenes (pantalla)', () {
    testWidgets('semana, mes y cierre', (tester) async {
      await openRoute(tester, Routes.summaries);
      expect(find.text('Te sobró'), findsOneWidget);
      expect(find.text('Últimos 7 días · 18 al 24 de octubre'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Mes pasado'));
      await tester.pumpAndSettle();
      expect(
        find.text('Cierre de septiembre · 1 al 30 de septiembre'),
        findsOneWidget,
      );
      expect(
        find.text(r'Gastaste $1.200.000 más que el periodo anterior.'),
        findsOneWidget,
      );
    });

    testWidgets('copiar el resumen avisa', (tester) async {
      await openRoute(tester, Routes.summaries);
      await tester.tap(find.text('Copiar resumen'));
      await tester.pump();
      expect(
        find.text('Copiamos el resumen para que lo envíes'),
        findsOneWidget,
      );
    });

    testWidgets('desde Planes > Reportes se llega', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: _tall);
      await tester.tap(find.bySemanticsLabel(RegExp('^Planes, pestaña')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reportes'));
      await tester.pumpAndSettle();
      await scrollIntoView(
        tester,
        find.text('Resumen semanal y cierre mensual'),
      );
      await tester.tap(find.text('Resumen semanal y cierre mensual'));
      await tester.pumpAndSettle();
      expect(find.text('Resúmenes'), findsOneWidget);
      handle.dispose();
    });
  });

  group('Mis datos', () {
    test('la copia lleva lo tuyo y nada de claves', () async {
      final txs = await MockTransactionsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final accounts = await MockAccountsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final export = buildDataExport(
        user: testUser,
        now: now,
        accounts: accounts,
        transactions: txs,
        budgets: const [],
        goals: const [],
        rules: const [],
        investments: const [],
        invoices: const [],
        bills: const [],
      );
      final doc = jsonDecode(export.json) as Map<String, dynamic>;
      expect(doc['version'], 1);
      expect(doc['generado'], '2026-10-24');
      final persona = doc['persona'] as Map<String, dynamic>;
      expect(persona['correo'], testUser.email);
      expect(doc['movimientos'] as List<dynamic>, hasLength(txs.length));
      expect(export.counts['cuentas'], 6);
      // Nunca salen claves ni permisos: ni como sección ni en la persona.
      for (final secret in ['pin', 'contrasena', 'password', 'permisos']) {
        expect(doc.containsKey(secret), isFalse);
        expect(persona.containsKey(secret), isFalse);
      }
      // Las secciones vacías no se cuentan.
      expect(export.counts.containsKey('metas'), isFalse);
      expect(export.total, accounts.length + txs.length);
    });

    test('el CSV de movimientos escapa y ordena', () {
      final csv = transactionsCsv([
        Transaction(
          id: 'a',
          title: 'Café, "El Sol"',
          amount: 12000,
          kind: TransactionKind.expense,
          accountId: 'n',
          categoryId: 'salidas',
          ownership: Ownership.personal,
          date: DateTime(2026, 10),
        ),
        Transaction(
          id: 'b',
          title: 'Pago',
          amount: 500000,
          kind: TransactionKind.income,
          accountId: 'n',
          categoryId: 'honorarios',
          ownership: Ownership.business,
          date: DateTime(2026, 10, 20),
          note: 'Factura F-1',
        ),
      ], (id) => 'Nequi');
      final lines = csv.split('\n');
      expect(lines.first, transactionsCsvHeader);
      expect(lines[1], startsWith('2026-10-20,Pago,Nequi'));
      expect(lines[2], contains('"Café, ""El Sol"""'));
    });

    testWidgets('qué guardamos y copiar con confirmación', (tester) async {
      await openRoute(tester, Routes.myData);
      expect(find.text('Qué guardamos de ti'), findsOneWidget);
      expect(find.text('Movimientos'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      await tester.tap(find.text('Copiar todo (JSON)'));
      await tester.pumpAndSettle();
      expect(find.text('Confirma que eres tú'), findsOneWidget);
      await tester.tap(find.text('Usar huella o Face ID'));
      await tester.pumpAndSettle();
      expect(find.text('Copiamos tus datos (51 registros)'), findsOneWidget);
    });

    testWidgets('eliminar la cuenta pide confirmar', (tester) async {
      await openRoute(tester, Routes.myData);
      await scrollIntoView(tester, find.text('Eliminar mi cuenta'));
      await tester.tap(find.text('Eliminar mi cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('¿Eliminar tu cuenta de Qullqi?'), findsOneWidget);
      await tester.tap(find.text('Conservar mi cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Mis datos'), findsWidgets);
    });

    testWidgets('desde Perfil se llega', (tester) async {
      await openRoute(tester, Routes.profile);
      await scrollIntoView(tester, find.text('Mis datos'));
      await tester.tap(find.text('Mis datos'));
      await tester.pumpAndSettle();
      expect(find.text('Llévate una copia'), findsOneWidget);
    });
  });

  group('Avisos en el teléfono', () {
    test('el horario de silencio cruza la medianoche', () {
      DateTime at(int h, [int m = 0]) => DateTime(2026, 10, 24, h, m);
      expect(QuietHours.night.contains(at(23)), isTrue);
      expect(QuietHours.night.contains(at(6, 59)), isTrue);
      expect(QuietHours.night.contains(at(7)), isFalse);
      expect(QuietHours.night.contains(at(12)), isFalse);
      expect(QuietHours.early.contains(at(20, 59)), isFalse);
      expect(QuietHours.early.contains(at(21)), isTrue);
      expect(QuietHours.early.contains(at(8)), isFalse);
      expect(QuietHours.off.contains(at(3)), isFalse);
    });

    test('suena solo si está activo y fuera del silencio', () {
      final night = DateTime(2026, 10, 24, 23);
      final noon = DateTime(2026, 10, 24, 12);
      expect(const PushPrefs().shouldRing(noon), isFalse);
      const on = PushPrefs(enabled: true, quiet: QuietHours.night);
      expect(on.shouldRing(night), isFalse);
      expect(on.shouldRing(noon), isTrue);
    });

    testWidgets('activar pide permiso y elegir un horario se recuerda', (
      tester,
    ) async {
      final container = await openRoute(tester, Routes.notificationSettings);
      expect(find.text('No molestar'), findsNothing);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(find.text('¿Recibir avisos en tu teléfono?'), findsOneWidget);
      await tester.tap(find.text('Permitir avisos'));
      await tester.pumpAndSettle();
      expect(find.text('No molestar'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, '10 p. m. a 7 a. m.'));
      await tester.pumpAndSettle();
      final prefs = container.read(pushPrefsProvider);
      expect(prefs.enabled, isTrue);
      expect(prefs.quiet, QuietHours.night);
      await tester.tap(find.text('Enviarme una notificación de prueba'));
      await tester.pump();
      expect(find.textContaining('Así te llegaría'), findsOneWidget);
    });

    testWidgets('"Ahora no" deja los avisos apagados', (tester) async {
      final container = await openRoute(tester, Routes.notificationSettings);
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();
      expect(container.read(pushPrefsProvider).enabled, isFalse);
      expect(find.text('No molestar'), findsNothing);
    });
  });

  group('Capturas y accesibilidad', () {
    final routes = <String, String>{
      'summaries': Routes.summaries,
      'my_data': Routes.myData,
      'push_settings': Routes.notificationSettings,
    };
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final e in routes.entries) {
        testWidgets('${e.key} (${mode.name})', (tester) async {
          final handle = tester.ensureSemantics();
          await openRoute(
            tester,
            e.value,
            mode: mode,
            prefs: e.key == 'push_settings'
                ? {'push_enabled': true, 'push_quiet': 'night'}
                : const {},
          );
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

    testWidgets('mi cuenta en dólares se ve en la lista', (tester) async {
      final handle = tester.ensureSemantics();
      final container = await pumpApp(tester, size: _tall);
      await tester.runAsync(
        () => container
            .read(accountsRepositoryProvider)
            .addManual(
              name: 'Ahorros EE. UU.',
              kind: AccountKind.savings,
              balance: ExchangeRates.toCop(250, Currency.usd),
              ownership: Ownership.personal,
              currency: Currency.usd,
            ),
      );
      await tester.tap(find.bySemanticsLabel(RegExp('^Cuentas, pestaña')));
      await tester.pumpAndSettle();
      expect(find.textContaining('USD 250'), findsOneWidget);
      handle.dispose();
    });
  });
}
