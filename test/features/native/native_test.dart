import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qullqi/app/quick_actions_service.dart';
import 'package:qullqi/app/router.dart';
import 'package:qullqi/app/routes.dart';
import 'package:qullqi/app/shortcuts.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/storage/prefs.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/business/data/invoices_repository.dart';
import 'package:qullqi/features/commitments/data/commitments_repository.dart';
import 'package:qullqi/features/home/domain/money_summary.dart';
import 'package:qullqi/features/investments/data/investments_repository.dart';
import 'package:qullqi/features/notifications/domain/notice.dart';
import 'package:qullqi/features/profile/data/push_prefs.dart';
import 'package:qullqi/features/recurring/domain/recurring.dart';
import 'package:qullqi/features/reminders/data/local_notifier.dart';
import 'package:qullqi/features/reminders/domain/reminders.dart';
import 'package:qullqi/features/taxes/domain/tax_calendar.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:qullqi/features/widgets/data/widget_bridge.dart';
import 'package:qullqi/features/widgets/domain/widget_snapshot.dart';

import '../../helpers/pump.dart';

const _tall = Size(390, 1700);

/// Recuerda lo que se le pidió, en vez de hablar con el teléfono.
class FakeBridge implements WidgetBridge {
  final published = <WidgetSnapshot>[];
  int cleared = 0;

  @override
  Future<void> publish(WidgetSnapshot snapshot) async =>
      published.add(snapshot);

  @override
  Future<void> clear() async => cleared++;
}

class FakeNotifier implements LocalNotifier {
  FakeNotifier({this.grant = true});

  final bool grant;
  final plans = <List<Reminder>>[];
  int permissionRequests = 0;
  void Function(String route)? onOpen;

  @override
  Future<void> init({required void Function(String route) onOpen}) async {
    this.onOpen = onOpen;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grant;
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async =>
      plans.add(reminders);
}

class FakeQuickActions implements QuickActionsService {
  void Function(String id)? onAction;

  @override
  Future<void> init(void Function(String id) onAction) async {
    this.onAction = onAction;
  }
}

void main() {
  final now = DateTime(2026, 10, 24, 14, 45);

  group('Identificadores', () {
    test('son estables y distintos', () {
      expect(stableId('pago:visa:0'), stableId('pago:visa:0'));
      expect(stableId('pago:visa:0'), isNot(stableId('pago:visa:3')));
      expect(stableId('x'), greaterThanOrEqualTo(0));
      expect(stableId('un identificador largo' * 20), lessThan(1 << 31));
    });
  });

  group('Recordatorios', () {
    late List<UpcomingPayment> payments;
    late List<Reminder> all;

    setUpAll(() async {
      final accounts = await MockAccountsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final commitments = await MockCommitmentsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final txs = await MockTransactionsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final invoices = await MockInvoicesRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      final investments = await MockInvestmentsRepository(
        now: () => now,
        latency: Duration.zero,
      ).watch().first;
      payments = upcomingPayments(
        accounts: accounts,
        commitments: commitments,
        scope: Scope.all,
      );
      all = buildReminders(
        now: now,
        payments: payments,
        invoices: invoices,
        investments: investments,
        recurring: detectRecurring(txs, now),
        obligations: buildTaxCalendar(
          document: const TaxDocument(
            type: TaxDocumentType.cedula,
            number: '1032454242',
          ),
          now: now,
          hasBusiness: true,
        ),
        enabled: NoticeKind.values.toSet(),
        hasBusiness: true,
      );
    });

    test('solo hay recordatorios en el futuro, en orden', () {
      expect(all, isNotEmpty);
      expect(all.length, lessThanOrEqualTo(maxReminders));
      for (final r in all) {
        expect(r.when.isAfter(now), isTrue);
      }
      for (var i = 1; i < all.length; i++) {
        expect(all[i].when.isBefore(all[i - 1].when), isFalse);
      }
      // Sin repetidos: cada uno tiene su propio identificador.
      expect({for (final r in all) r.id}, hasLength(all.length));
    });

    test('la tarjeta Visa avisa el día del pago, con su mínimo', () {
      final visa = all.firstWhere((r) => r.route == '/cuenta/visa');
      expect(visa.title, 'Paga tu Tarjeta Visa •• 4521');
      expect(visa.subtitle, 'Vence hoy');
      expect(visa.body, r'$1.320.000 · mínimo $180.000');
      expect(visa.when, DateTime(2026, 10, 27, dueDayHour));
      expect(visa.kind, NoticeKind.payments);
    });

    test('un pago lejano avisa 3 días antes y el mismo día', () {
      final nu = all.where((r) => r.route == '/cuenta/nu').toList();
      expect(nu.map((r) => r.subtitle), ['Vence en 3 días', 'Vence hoy']);
      expect(nu.first.when, DateTime(2026, 11, 17, reminderHour));
      expect(nu.last.when, DateTime(2026, 11, 20, dueDayHour));
    });

    test('apagar un tipo de aviso quita sus recordatorios', () {
      final without = buildReminders(
        now: now,
        payments: payments,
        invoices: const [],
        investments: const [],
        recurring: const [],
        obligations: const [],
        enabled: NoticeKind.values.toSet()..remove(NoticeKind.payments),
        hasBusiness: true,
      );
      expect(without, isEmpty);
    });

    test('sin negocio no hay recordatorios del negocio', () {
      final personal = buildReminders(
        now: now,
        payments: payments,
        invoices: const [],
        investments: const [],
        recurring: const [],
        obligations: const [],
        enabled: NoticeKind.values.toSet(),
        hasBusiness: false,
      );
      expect(personal.any((r) => r.title.contains('Claro')), isFalse);
      expect(personal.any((r) => r.title.contains('IVA')), isFalse);
      expect(personal.any((r) => r.route == '/cuenta/visa'), isTrue);
    });

    test('lo que guarda cada notificación se puede leer', () {
      final r = all.first;
      final data = decodePayload(r.payload)!;
      expect(data['route'], r.route);
      expect(data['title'], r.title);
      expect(decodePayload('no es json'), isNull);
      expect(decodePayload(null), isNull);
      expect(decodePayload('[1,2]'), isNull);
    });
  });

  group('No molestar', () {
    Reminder at(int h) => Reminder(
      id: h,
      when: DateTime(2026, 10, 28, h),
      title: 't',
      subtitle: 's',
      body: 'b',
      route: Routes.home,
      kind: NoticeKind.payments,
    );

    test('lo de la noche pasa a la mañana siguiente', () {
      final r = applyQuietHours([at(23)], QuietHours.night).single;
      expect(r.when, DateTime(2026, 10, 29, 7));
    });

    test('lo de la madrugada espera a que termine el silencio', () {
      final r = applyQuietHours([at(5)], QuietHours.night).single;
      expect(r.when, DateTime(2026, 10, 28, 7));
    });

    test('lo del día no se toca', () {
      final r = applyQuietHours([at(9), at(8)], QuietHours.night);
      expect(r.map((x) => x.when.hour), [9, 8]);
      expect(applyQuietHours([at(23)], QuietHours.off).single.when.hour, 23);
    });
  });

  group('Atajos', () {
    test('cada atajo lleva a una pantalla real', () {
      for (final q in AppShortcuts.quickActions) {
        expect(AppShortcuts.routeFor(q.id), isNotNull, reason: q.id);
      }
      expect(AppShortcuts.routeFor(AppShortcuts.addExpense), Routes.addExpense);
      expect(AppShortcuts.routeFor('no-existe'), isNull);
      expect(
        AppShortcuts.linkFor(AppShortcuts.moveMoney),
        'qullqi:///atajo/mover-plata',
      );
    });

    testWidgets('el enlace del atajo abre la pantalla', (tester) async {
      final container = await pumpApp(tester, size: _tall);
      unawaited(
        container
            .read(routerProvider)
            .push<void>('/atajo/${AppShortcuts.addExpense}'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Registrar gasto'), findsWidgets);
    });

    testWidgets('lo que dejó Siri se abre al arrancar y se borra', (
      tester,
    ) async {
      final container = await pumpApp(
        tester,
        size: _tall,
        prefs: {pendingShortcutKey: AppShortcuts.moveMoney},
      );
      await tester.pumpAndSettle();
      expect(find.text('Mover plata'), findsWidgets);
      // La nota se borra: no vuelve a abrirse la próxima vez.
      expect(
        container.read(sharedPreferencesProvider).getString(pendingShortcutKey),
        isNull,
      );
    });

    testWidgets('un atajo del ícono abre su pantalla', (tester) async {
      final quick = FakeQuickActions();
      await pumpApp(
        tester,
        size: _tall,
        overrides: [quickActionsProvider.overrideWithValue(quick)],
      );
      expect(quick.onAction, isNotNull);
      quick.onAction!(AppShortcuts.scanReceipt);
      await tester.pumpAndSettle();
      expect(find.textContaining('factura'), findsWidgets);
    });

    testWidgets('tocar una notificación abre su pantalla', (tester) async {
      final notifier = FakeNotifier();
      await pumpApp(
        tester,
        size: _tall,
        overrides: [localNotifierProvider.overrideWithValue(notifier)],
      );
      expect(notifier.onOpen, isNotNull);
      notifier.onOpen!(Routes.notifications);
      await tester.pumpAndSettle();
      expect(find.text('Notificaciones'), findsWidgets);
    });
  });

  group('Lo que ven los widgets', () {
    testWidgets('la foto resume el Inicio', (tester) async {
      final bridge = FakeBridge();
      final container = await pumpApp(
        tester,
        size: _tall,
        overrides: [widgetBridgeProvider.overrideWithValue(bridge)],
      );
      final s = container.read(widgetSnapshotProvider)!;
      expect(s.scopeLabel, 'Todo');
      expect(s.firstName, 'Camilo');
      expect(s.amountsHidden, isFalse);
      expect(s.available, 3208672);
      expect(s.payments, hasLength(widgetPaymentCount));
      expect(s.payments.first.daysLeft, lessThanOrEqualTo(3));
      // Se publicó en cuanto hubo datos.
      expect(bridge.published, isNotEmpty);
      expect(bridge.published.last.available, 3208672);
    });

    testWidgets('el JSON lleva lo que el widget necesita', (tester) async {
      final container = await pumpApp(tester, size: _tall);
      final json = jsonDecode(
        container.read(widgetSnapshotProvider)!.encode(),
      ) as Map<String, dynamic>;
      expect(json['version'], WidgetSnapshot.version);
      expect(json['available'], 3208672);
      expect(json['scopeLabel'], 'Todo');
      final payments = json['payments'] as List<dynamic>;
      expect(payments, hasLength(3));
      expect((payments.first as Map<String, dynamic>).keys, {
        'title',
        'amount',
        'daysLeft',
      });
    });

    testWidgets('si la persona oculta los montos, no salen', (tester) async {
      final container = await pumpApp(
        tester,
        size: _tall,
        prefs: {'widget_amounts': false},
      );
      final s = container.read(widgetSnapshotProvider)!;
      expect(s.amountsHidden, isTrue);
      expect(s.available, isNull);
      expect(s.perDay, isNull);
      expect(s.netWorth, isNull);
      expect(s.payments.every((p) => p.amount == null), isTrue);
      // Los títulos y los días sí: ayudan sin revelar cifras.
      expect(s.payments.first.title, isNotEmpty);
    });

    testWidgets('con la sesión bloqueada no hay nada que mostrar', (
      tester,
    ) async {
      final container = await pumpApp(tester, size: _tall, lockOnStart: true);
      expect(container.read(widgetSnapshotProvider), isNull);
    });
  });

  group('Avisos del teléfono (programación)', () {
    testWidgets('activados, se programa lo que viene', (tester) async {
      final notifier = FakeNotifier();
      await pumpApp(
        tester,
        size: _tall,
        prefs: {'push_enabled': true},
        overrides: [localNotifierProvider.overrideWithValue(notifier)],
      );
      expect(notifier.plans, isNotEmpty);
      expect(notifier.plans.last, isNotEmpty);
    });

    testWidgets('apagados, no queda nada programado', (tester) async {
      final notifier = FakeNotifier();
      await pumpApp(
        tester,
        size: _tall,
        overrides: [localNotifierProvider.overrideWithValue(notifier)],
      );
      expect(notifier.plans.last, isEmpty);
    });

    testWidgets('al activar se pide el permiso del teléfono', (tester) async {
      final notifier = FakeNotifier(grant: false);
      final container = await pumpApp(
        tester,
        size: _tall,
        overrides: [localNotifierProvider.overrideWithValue(notifier)],
      );
      unawaited(
        container.read(routerProvider).push<void>(Routes.notificationSettings),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Permitir avisos'));
      await tester.pumpAndSettle();
      expect(notifier.permissionRequests, 1);
      // El teléfono lo negó: queda apagado y se explica qué hacer.
      expect(container.read(pushPrefsProvider).enabled, isFalse);
      expect(
        find.text('Activa los avisos de Qullqi en los ajustes del teléfono.'),
        findsOneWidget,
      );
    });

    testWidgets('con permiso concedido queda activo', (tester) async {
      final notifier = FakeNotifier();
      final container = await pumpApp(
        tester,
        size: _tall,
        overrides: [localNotifierProvider.overrideWithValue(notifier)],
      );
      unawaited(
        container.read(routerProvider).push<void>(Routes.notificationSettings),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Permitir avisos'));
      await tester.pumpAndSettle();
      expect(container.read(pushPrefsProvider).enabled, isTrue);
    });
  });

  group('Montos en los widgets (ajuste)', () {
    testWidgets('el interruptor del Perfil lo cambia y lo recuerda', (
      tester,
    ) async {
      final container = await pumpApp(tester, size: _tall);
      unawaited(container.read(routerProvider).push<void>(Routes.profile));
      await tester.pumpAndSettle();
      await scrollIntoView(tester, find.text('Mostrar montos en los widgets'));
      expect(container.read(widgetAmountsProvider), isTrue);
      await tester.tap(find.text('Mostrar montos en los widgets'));
      await tester.pumpAndSettle();
      expect(container.read(widgetAmountsProvider), isFalse);
    });
  });
}
