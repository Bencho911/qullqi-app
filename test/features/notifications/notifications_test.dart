import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qullqi/features/notifications/data/notices.dart';
import 'package:qullqi/features/profile/data/notification_prefs.dart';

import '../../helpers/pump.dart';

final Finder bell = find.byTooltip(RegExp('^Notificaciones'));

Future<void> openNotifications(WidgetTester tester) async {
  await tester.tap(bell);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('los avisos salen de los datos, lo urgente primero', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    final notices = container.read(noticesProvider).requireValue;
    final titles = notices.map((n) => n.title).toList();
    expect(titles.first, 'Reconecta Davivienda');
    expect(titles, contains('Paga tu Tarjeta Visa •• 4521'));
    expect(titles, contains('Cobro vencido: Café Origen S.A.S.'));
    expect(titles, contains('Te pasaste en Suscripciones'));
    expect(titles, contains('Vas en el 85 % de Mercado'));
    expect(titles, contains('2 movimientos parecen traslados'));
    expect(titles, contains(r'Entraron $2.500.000'));
    // Del más urgente al menos urgente.
    final tones = notices.map((n) => n.tone.index).toList();
    expect(tones, [...tones]..sort((a, b) => b.compareTo(a)));
  });

  testWidgets('la campana cuenta lo nuevo y queda en cero al abrir', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    final total = container.read(noticesProvider).requireValue.length;
    expect(find.byTooltip('Notificaciones, $total sin leer'), findsOneWidget);
    await openNotifications(tester);
    expect(find.text('Nuevos'), findsOneWidget);
    expect(container.read(unreadNotificationsProvider), 0);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notificaciones'), findsOneWidget);
    // Al volver, lo que ya viste queda en "Pendientes".
    await openNotifications(tester);
    expect(find.text('Nuevos'), findsNothing);
    expect(find.text('Pendientes'), findsOneWidget);
  });

  testWidgets('tocar un aviso lleva a su causa', (tester) async {
    await pumpApp(tester, size: const Size(390, 1800));
    await openNotifications(tester);
    await tester.tap(find.text('Cobro vencido: Café Origen S.A.S.'));
    await tester.pumpAndSettle();
    expect(find.text('F-0041'), findsWidgets);
  });

  testWidgets('apagar un tipo de aviso lo quita', (tester) async {
    final container = await pumpApp(tester);
    await container
        .read(noticePrefsProvider.notifier)
        .toggle(NoticeKind.budgets, on: false);
    await tester.pump();
    final notices = container.read(noticesProvider).requireValue;
    expect(notices.where((n) => n.kind == NoticeKind.budgets), isEmpty);
    // Los de conexión no se pueden apagar.
    expect(notices.where((n) => n.kind == null), isNotEmpty);
  });

  testWidgets('sin negocio no hay avisos del negocio', (tester) async {
    final container = await pumpApp(
      tester,
      prefs: {
        'session_user': jsonEncode(
          testUser.copyWith(hasBusiness: false).toJson(),
        ),
      },
    );
    final notices = container.read(noticesProvider).requireValue;
    expect(notices.where((n) => n.kind == NoticeKind.invoices), isEmpty);
    expect(notices.where((n) => n.title.contains('Software')), isEmpty);
    expect(notices.where((n) => n.title.contains('Entraron')), isEmpty);
  });

  group('Capturas y accesibilidad', () {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('notificaciones (${mode.name})', (tester) async {
        final handle = tester.ensureSemantics();
        await pumpApp(tester, mode: mode, size: const Size(390, 1500));
        await openNotifications(tester);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/notifications_${mode.name}.png'),
        );
        await expectAccessible(tester);
        handle.dispose();
      });
    }
  });
}
