import 'dart:async';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inti/app/router.dart';
import 'package:inti/app/routes.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart';
import 'package:inti/features/accounts/domain/account.dart';
import 'package:inti/features/statements/data/statement_repository.dart';
import 'package:inti/features/statements/domain/statement.dart';
import 'package:inti/features/transactions/data/transactions_repository.dart';
import 'package:inti/features/transactions/domain/transaction.dart';

import '../../helpers/pump.dart';

/// Extracto de Nequi como lo exporta el banco: unas líneas de datos antes
/// del encabezado, `;` como separador y un renglón de saldo al final.
const nequiCsv = '''
Extracto de movimientos;;
Cuenta de ahorros Nequi;;
Fecha;Descripción;Valor
24/10/2026;COMPRA EN EXITO CHAPINERO;-85.400
23/10/2026;PAGO TARJETA VISA;-200.000
22/10/2026;UBER   TRIP;-18.900,00
20/10/2026;ABONO NOMINA;3.200.000
;SALDO FINAL;4.000.000
''';

StatementFile file(String name, String text) =>
    StatementFile(name: name, bytes: Uint8List.fromList(utf8.encode(text)));

class FakePicker implements StatementPicker {
  FakePicker(this.next);

  final StatementFile? next;

  @override
  Future<StatementFile?> pick() async => next;
}

Future<ProviderContainer> openImport(
  WidgetTester tester,
  StatementFile? picked, {
  ThemeMode mode = ThemeMode.light,
  Size size = const Size(390, 1400),
  double textScale = 1,
}) async {
  final container = await pumpApp(
    tester,
    mode: mode,
    size: size,
    textScale: textScale,
    overrides: [statementPickerProvider.overrideWithValue(FakePicker(picked))],
  );
  await tester.tap(find.byTooltip('Registrar o mover plata'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Importar extracto'));
  await tester.pumpAndSettle();
  return container;
}

Future<void> chooseNequi(WidgetTester tester) async {
  await tester.tap(find.text('Elige una cuenta'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Nequi').last);
  await tester.pumpAndSettle();
}

Account nequiOf(ProviderContainer c) =>
    c.read(accountsProvider).requireValue.firstWhere((a) => a.id == 'nequi');

void main() {
  group('Lectura', () {
    test('montos en formato colombiano y de otros bancos', () {
      expect(parseStatementAmount('-85.400'), -85400);
      expect(parseStatementAmount(r'$ 1.234.567,89'), 1234568);
      expect(parseStatementAmount('1,234.50'), 1235);
      expect(parseStatementAmount('85400,5'), 85401);
      expect(parseStatementAmount('(3.500)'), -3500);
      expect(parseStatementAmount('3.500-'), -3500);
      expect(parseStatementAmount('1.234.567'), 1234567);
      expect(parseStatementAmount('SALDO'), isNull);
      expect(parseStatementAmount(''), isNull);
    });

    test('fechas', () {
      expect(parseStatementDate('24/10/2026'), DateTime(2026, 10, 24));
      expect(parseStatementDate('2026-10-24'), DateTime(2026, 10, 24));
      expect(parseStatementDate('24-10-26'), DateTime(2026, 10, 24));
      expect(parseStatementDate('20261024'), DateTime(2026, 10, 24));
      expect(parseStatementDate('24/10/2026 14:32'), DateTime(2026, 10, 24));
      expect(parseStatementDate('31/02/2026'), isNull);
      expect(parseStatementDate('Fecha'), isNull);
    });

    test('CSV con líneas previas y renglón de saldo', () {
      final lines = parseCsvStatement(nequiCsv);
      expect(lines, hasLength(4));
      expect(lines.first.description, 'Compra en Exito Chapinero');
      expect(lines[2].description, 'Uber Trip');
      expect(lines[2].amount, -18900);
      expect(lines.last.amount, 3200000);
    });

    test('CSV con columnas de débito y crédito, en Latin-1', () {
      const text =
          'fecha,concepto,débito,crédito\n'
          '2026-10-01,"Droguería, Cruz Verde","42.700",\n'
          '2026-10-02,Transferencia recibida,,"150.000"\n';
      final lines = parseCsvStatement(
        decodeStatementText(Uint8List.fromList(latin1.encode(text))),
      );
      expect(lines.map((l) => l.amount), [-42700, 150000]);
      expect(lines.first.description, 'Droguería, Cruz Verde');
    });

    test('un archivo sin movimientos se explica', () {
      expect(
        () => parseCsvStatement('Certificado bancario\nTitular;Camilo\n'),
        throwsA(
          isA<StatementException>().having(
            (e) => e.problem,
            'problem',
            StatementProblem.noMovements,
          ),
        ),
      );
    });

    test('categoría sugerida y traslados', () {
      StatementLine l(String d, int a) =>
          StatementLine(date: DateTime(2026), description: d, amount: a);
      expect(guessCategory(l('Compra en Exito Chapinero', -1)), 'mercado');
      expect(guessCategory(l('Uber Trip', -1)), 'transporte');
      expect(guessCategory(l('Netflix.com', -1)), 'suscripciones');
      expect(guessCategory(l('Abono nómina', 1)), 'entre-personas');
      expect(guessCategory(l('Ferretería', -1)), 'otros');
      expect(looksLikeTransfer(l('Pago tarjeta Visa', -1)), isTrue);
      expect(looksLikeTransfer(l('Uber Trip', -1)), isFalse);
    });

    test('lo que ya estaba no se trae dos veces', () {
      final existing = [
        Transaction(
          id: 'a',
          title: 'Éxito',
          amount: 85400,
          kind: TransactionKind.expense,
          accountId: 'nequi',
          categoryId: 'mercado',
          ownership: Ownership.personal,
          date: DateTime(2026, 10, 24, 14, 32),
        ),
      ];
      final lines = [
        ...parseCsvStatement(nequiCsv),
        // La misma compra dos veces el mismo día: solo una ya estaba.
        StatementLine(
          date: DateTime(2026, 10, 24),
          description: 'Compra en Exito Chapinero',
          amount: -85400,
        ),
      ];
      final matched = matchStatement(lines, existing, 'nequi');
      expect(matched.where((m) => m.duplicate), hasLength(1));
      // En otra cuenta no es duplicado.
      final other = matchStatement(lines, existing, 'bancolombia');
      expect(other.where((m) => m.duplicate), isEmpty);
    });

    test('formatos, tamaños y PDF con clave', () async {
      final reader = DefaultStatementReader(
        server: MockServerStatementReader(
          now: () => testNow,
          latency: Duration.zero,
        ),
      );
      Future<StatementProblem?> problemOf(StatementFile f) async {
        try {
          await reader.read(f);
          return null;
        } on StatementException catch (e) {
          return e.problem;
        }
      }

      expect(
        await problemOf(file('foto.jpg', 'x')),
        StatementProblem.unsupported,
      );
      expect(
        await problemOf(
          StatementFile(
            name: 'enorme.csv',
            bytes: Uint8List(maxStatementBytes + 1),
          ),
        ),
        StatementProblem.tooLarge,
      );
      expect(
        await problemOf(file('extracto.pdf', '%PDF-1.7 /Encrypt 3 0 R')),
        StatementProblem.protected,
      );
      expect(await problemOf(file('extracto.xlsx', 'PK')), isNull);
    });
  });

  group('Importar', () {
    testWidgets('elige la cuenta, revisa y trae solo lo nuevo', (tester) async {
      await openImport(tester, file('nequi_octubre.csv', nequiCsv));
      // Sin cuenta no sigue.
      await tester.tap(find.text('Elegir archivo'));
      await tester.pumpAndSettle();
      expect(
        find.text('Elige a qué cuenta pertenece el extracto.'),
        findsOneWidget,
      );
      await chooseNequi(tester);
      await tester.tap(find.text('Elegir archivo'));
      await tester.pumpAndSettle();
      expect(
        find.text('Encontramos 4 movimientos para Nequi.'),
        findsOneWidget,
      );
      expect(find.text('Ya está en Inti'), findsOneWidget);
      expect(find.text('Importar 3 movimientos'), findsOneWidget);
      // Quitar uno.
      await tester.tap(find.text('Uber Trip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Importar 2 movimientos'));
      await tester.pumpAndSettle();
      expect(find.text('Importamos 2 movimientos'), findsOneWidget);
      expect(find.textContaining('Uno parece un traslado'), findsOneWidget);
      await tester.tap(find.text('Ver movimientos'));
      await tester.pumpAndSettle();
      expect(find.text('Abono Nomina'), findsOneWidget);
      expect(find.text('Uber Trip'), findsNothing);
    });

    testWidgets('lo importado no cambia el saldo y se puede borrar', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      final before = nequiOf(container);
      // Las demoras simuladas avanzan con el reloj de la prueba.
      final saving = container.read(statementImporterProvider).import(before, [
        StatementLine(
          date: DateTime(2026, 9, 3),
          description: 'Ferretería',
          amount: -50000,
        ),
      ]);
      await tester.pumpAndSettle();
      await saving;
      final imported = container
          .read(transactionsProvider)
          .requireValue
          .firstWhere((t) => t.title == 'Ferretería');
      expect(imported.source, TransactionSource.imported);
      expect(imported.canDelete, isTrue);
      expect(imported.categoryId, 'otros');
      expect(nequiOf(container).balance, before.balance);
    });

    testWidgets('un formato que no leemos se explica', (tester) async {
      await openImport(tester, file('recibo.jpg', 'x'));
      await chooseNequi(tester);
      await tester.tap(find.text('Elegir archivo'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ese archivo no es un extracto que podamos leer'),
        findsOneWidget,
      );
    });

    testWidgets('desde una cuenta manual llega con la cuenta elegida', (
      tester,
    ) async {
      final container = await pumpApp(tester, size: const Size(390, 1400));
      final adding = container
          .read(accountsRepositoryProvider)
          .addManual(
            name: 'Efectivo',
            kind: AccountKind.cash,
            balance: 200000,
            ownership: Ownership.personal,
          );
      await tester.pumpAndSettle();
      final cash = await adding;
      unawaited(container.read(routerProvider).push(Routes.account(cash.id)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Importar extracto'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Efectivo ·'), findsOneWidget);
    });
  });

  group('Capturas y accesibilidad', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('importar (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await openImport(tester, file('nequi.csv', nequiCsv), mode: mode);
        await chooseNequi(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/import_choose_${mode.name}.png'),
        );
        await expectAccessible(tester);
        await tester.tap(find.text('Elegir archivo'));
        await tester.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/import_review_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });
    }

    testWidgets('importar con texto al 200 %', (tester) async {
      await openImport(
        tester,
        file('nequi.csv', nequiCsv),
        textScale: 2,
        size: const Size(390, 3000),
      );
      await chooseNequi(tester);
      await tester.tap(find.text('Elegir archivo'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/import_review_text200.png'),
      );
    });
  });
}
