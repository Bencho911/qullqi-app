import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart';
import 'package:inti/features/accounts/domain/account.dart';
import 'package:inti/features/accounts/domain/institution.dart';

import '../../helpers/pump.dart';

Finder tab(String label) => find.bySemanticsLabel(RegExp('^$label, pestaña'));

Future<void> openAccounts(
  WidgetTester tester, {
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
  Size size = const Size(390, 1700),
}) async {
  final handle = tester.ensureSemantics();
  await pumpApp(tester, mode: mode, textScale: textScale, size: size);
  await tester.tap(tab('Cuentas'));
  await tester.pumpAndSettle();
  handle.dispose();
}

Future<void> scrollTo(WidgetTester tester, Finder f) =>
    scrollIntoView(tester, f);

void main() {
  final now = DateTime(2026, 10, 24, 14, 45);

  group('Repositorio', () {
    late MockAccountsRepository repo;
    setUp(
      () =>
          repo = MockAccountsRepository(now: () => now, latency: Duration.zero),
    );

    test('conectar crea la cuenta con el permiso pedido', () async {
      final a = await repo.connect(Institutions.byId('bbva')!, payments: true);
      expect(a.institution, 'BBVA');
      expect(a.paymentsEnabled, isTrue);
      expect((await repo.watch().first).any((x) => x.id == a.id), isTrue);
    });

    test('si el banco no admite pagos, no se activan', () async {
      final a = await repo.connect(
        Institutions.byId('colpatria')!,
        payments: true,
      );
      expect(a.paymentsEnabled, isFalse);
    });

    test('un banco que no responde da un error explicable', () async {
      expect(
        () => repo.connect(Institutions.byId('lulo')!, payments: false),
        throwsA(isA<ConnectionFailure>()),
      );
    });

    test('reconectar deja la cuenta al día', () async {
      await repo.reconnect('davivienda');
      final d = (await repo.watch().first).firstWhere(
        (a) => a.id == 'davivienda',
      );
      expect(d.status, ConnectionStatus.connected);
      expect(d.lastSync, now);
    });

    test('una cuenta a mano no puede mover plata', () async {
      final a = await repo.addManual(
        name: ' Efectivo ',
        kind: AccountKind.wallet,
        balance: 120000,
        ownership: Ownership.personal,
      );
      expect(a.institution, 'Efectivo');
      expect(a.isManual, isTrue);
      expect(a.paymentsEnabled, isFalse);
    });

    test('desconectar la quita', () async {
      await repo.remove('nequi');
      expect((await repo.watch().first).any((a) => a.id == 'nequi'), isFalse);
    });
  });

  group('Pestaña Cuentas', () {
    testWidgets('patrimonio y cuentas agrupadas por tipo', (tester) async {
      await openAccounts(tester);
      expect(find.text('Patrimonio neto'), findsOneWidget);
      // Cuentas (6.030.000) + inversiones (16.593.800).
      expect(semanticsLabel('22.623.800 pesos'), findsWidgets);
      expect(find.text('Tus inversiones'), findsOneWidget);
      expect(find.text('Cuentas de banco'), findsOneWidget);
      expect(find.text('Billeteras y efectivo'), findsOneWidget);
      expect(find.text('Tarjetas de crédito'), findsOneWidget);
      expect(find.text('Reconecta para ver el saldo de hoy'), findsOneWidget);
    });

    testWidgets('la vista Personal oculta lo del negocio', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(
        tester,
        size: const Size(390, 1700),
        prefs: {'scope': 'personal'},
      );
      await tester.tap(tab('Cuentas'));
      await tester.pumpAndSettle();
      expect(find.text('Davivienda'), findsNothing);
      expect(find.text('Nequi'), findsOneWidget);
      handle.dispose();
    });
  });

  group('Detalle', () {
    testWidgets('una tarjeta muestra cupo, corte y permite pagarla', (
      tester,
    ) async {
      await openAccounts(tester);
      await tester.tap(find.text('Tarjeta Visa •• 4521'));
      await tester.pumpAndSettle();
      expect(find.text('Usas 26 % de tu cupo'), findsOneWidget);
      expect(find.text('Pago del corte'), findsOneWidget);
      await tester.tap(find.text('Pagar tarjeta'));
      await tester.pumpAndSettle();
      expect(find.text('Tarjeta a pagar'), findsOneWidget);
    });

    testWidgets('una cuenta vencida ofrece reconectar', (tester) async {
      await openAccounts(tester);
      await tester.tap(find.text('Davivienda'));
      await tester.pumpAndSettle();
      expect(find.text('Davivienda necesita reconectarse'), findsOneWidget);
      await tester.tap(find.text('Reconectar'));
      await tester.pumpAndSettle();
      expect(find.text('Reconectar Davivienda'), findsOneWidget);
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar a Davivienda'));
      await tester.pumpAndSettle();
      expect(find.text('Davivienda está al día'), findsOneWidget);
      await tester.tap(find.text('Cerrar'));
      await tester.pumpAndSettle();
      expect(find.text('Davivienda necesita reconectarse'), findsNothing);
    });

    testWidgets('activar mover plata pide confirmar identidad', (tester) async {
      await openAccounts(tester);
      // Daviplata (negocio) ya lo tiene; se prueba desactivar y activar.
      await tester.tap(find.text('Daviplata'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ya no se puede mover'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.text('Confirma que eres tú'), findsOneWidget);
      await tester.tap(find.text('Usar huella o Face ID'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ya puedes mover plata'), findsOneWidget);
    });

    testWidgets('desconectar pide confirmar y vuelve a la lista', (
      tester,
    ) async {
      await openAccounts(tester);
      await tester.tap(find.text('Nequi'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Desconectar Nequi'));
      await tester.tap(find.text('Desconectar Nequi'));
      await tester.pumpAndSettle();
      expect(find.text('¿Desconectar Nequi?'), findsOneWidget);
      await tester.tap(find.text('Desconectar Nequi').last);
      await tester.pumpAndSettle();
      expect(find.text('Desconectamos Nequi'), findsOneWidget);
      expect(find.text('Cuentas'), findsWidgets);
    });
  });

  group('Conectar y agregar', () {
    testWidgets('conectar un banco con permiso para mover plata', (
      tester,
    ) async {
      await openAccounts(tester);
      await scrollTo(tester, find.text('Conectar cuenta'));
      await tester.tap(find.text('Conectar cuenta').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bbva');
      await tester.pumpAndSettle();
      await tester.tap(find.text('BBVA'));
      await tester.pumpAndSettle();
      // Sin autorización no se puede seguir.
      await tester.tap(find.text('Continuar a BBVA'));
      await tester.pumpAndSettle();
      expect(
        find.text('Marca la autorización para continuar.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Permitir mover plata (opcional)'));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar a BBVA'));
      await tester.pumpAndSettle();
      expect(find.text('BBVA quedó conectada'), findsOneWidget);
      await tester.tap(find.text('Ver la cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Mover plata desde aquí'), findsOneWidget);
    });

    testWidgets('si el banco falla, se explica y se ofrece reintentar', (
      tester,
    ) async {
      await openAccounts(tester);
      await scrollTo(tester, find.text('Conectar cuenta'));
      await tester.tap(find.text('Conectar cuenta').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'lulo');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lulo Bank'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continuar a Lulo Bank'));
      await tester.pumpAndSettle();
      expect(find.text('No pudimos conectar Lulo Bank'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('agregar una cuenta a mano', (tester) async {
      await openAccounts(tester);
      await scrollTo(tester, find.text('Agregar cuenta a mano'));
      await tester.tap(find.text('Agregar cuenta a mano'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar cuenta'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Escribe cómo se llama'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Efectivo');
      await tester.tap(find.text('Efectivo').last);
      await tester.enterText(find.byType(TextField).at(1), '120000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar cuenta'));
      await tester.pumpAndSettle();
      expect(find.text('Agregamos Efectivo'), findsOneWidget);
      expect(find.text('Saldo'), findsOneWidget);
      expect(semanticsLabel('Saldo: 120.000 pesos'), findsOneWidget);
    });
  });

  group('Capturas y accesibilidad', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('cuentas (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await openAccounts(tester, mode: mode);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/accounts_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });
    }

    testWidgets('detalle de tarjeta y de cuenta', (tester) async {
      final handle = tester.ensureSemantics();
      await openAccounts(tester);
      await tester.tap(find.text('Tarjeta Visa •• 4521'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/account_card_detail.png'),
      );
      await expectAccessible(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Davivienda'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/account_detail_reconnect.png'),
      );
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('conectar: lista y permisos', (tester) async {
      final handle = tester.ensureSemantics();
      await openAccounts(tester, size: phone);
      await scrollTo(tester, find.text('Conectar cuenta'));
      await tester.tap(find.text('Conectar cuenta').last);
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/connect_pick.png'),
      );
      await expectAccessible(tester);
      await tester.tap(find.text('Bancolombia'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/connect_consent.png'),
      );
      await expectAccessible(tester);
      handle.dispose();
    });

    testWidgets('cuentas y permisos con texto al 200 %', (tester) async {
      await openAccounts(tester, textScale: 2, size: const Size(390, 3600));
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/accounts_text200.png'),
      );
    });

    testWidgets('agregar a mano', (tester) async {
      final handle = tester.ensureSemantics();
      await openAccounts(tester, size: phone);
      await scrollTo(tester, find.text('Agregar cuenta a mano'));
      await tester.tap(find.text('Agregar cuenta a mano'));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/manual_account.png'),
      );
      await expectAccessible(tester);
      handle.dispose();
    });
  });
}
