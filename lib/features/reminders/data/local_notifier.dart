import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/business/data/business_back_office.dart';
import 'package:qullqi/features/business/data/invoices_repository.dart';
import 'package:qullqi/features/business/domain/bill.dart';
import 'package:qullqi/features/business/domain/business.dart';
import 'package:qullqi/features/commitments/data/commitments_repository.dart';
import 'package:qullqi/features/home/domain/home_data.dart';
import 'package:qullqi/features/home/domain/money_summary.dart';
import 'package:qullqi/features/investments/data/investments_repository.dart';
import 'package:qullqi/features/profile/data/notification_prefs.dart';
import 'package:qullqi/features/profile/data/push_prefs.dart';
import 'package:qullqi/features/recurring/domain/recurring.dart';
import 'package:qullqi/features/reminders/domain/reminders.dart';
import 'package:qullqi/features/taxes/data/tax_document_provider.dart';
import 'package:qullqi/features/taxes/domain/tax_calendar.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Notificaciones programadas en el teléfono (no necesitan servidor).
abstract interface class LocalNotifier {
  /// Prepara las notificaciones. [onOpen] recibe la ruta a la que lleva la
  /// que la persona tocó.
  Future<void> init({required void Function(String route) onOpen});

  /// Pide permiso para mostrar avisos. `true` si lo concedió.
  Future<bool> requestPermission();

  /// Deja programados exactamente [reminders] (con lista vacía, ninguno).
  Future<void> replaceAll(List<Reminder> reminders);

  /// Muestra una notificación ahora mismo (la de prueba).
  Future<void> showNow(Reminder reminder);
}

/// No hace nada: pruebas y plataformas sin notificaciones.
class NoopLocalNotifier implements LocalNotifier {
  const NoopLocalNotifier();

  @override
  Future<void> init({required void Function(String route) onOpen}) async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {}

  @override
  Future<void> showNow(Reminder reminder) async {}
}

/// El notificador real se pone en `main`; por defecto no hace nada.
final localNotifierProvider = Provider<LocalNotifier>(
  (ref) => const NoopLocalNotifier(),
);

/// Los recordatorios que deben estar programados; `null` mientras carga lo
/// necesario para calcularlos (así no se borra lo programado sin motivo).
final reminderPlanProvider = Provider<List<Reminder>?>((ref) {
  final prefs = ref.watch(pushPrefsProvider);
  if (!prefs.enabled) return const [];
  if (ref.watch(sessionProvider).status != SessionStatus.unlocked) {
    return const [];
  }
  final accounts = ref.watch(accountsProvider).value;
  final commitments = ref.watch(commitmentsProvider).value;
  final transactions = ref.watch(transactionsProvider).value;
  final invoices = ref.watch(invoicesProvider).value;
  if (accounts == null ||
      commitments == null ||
      transactions == null ||
      invoices == null) {
    return null;
  }
  final now = ref.watch(clockProvider)();
  final hasBusiness = ref.watch(currentUserProvider).hasBusiness;
  final investments = ref.watch(investmentsProvider).value ?? const [];
  final bills = ref.watch(billsProvider).value ?? const <Bill>[];
  final document = ref.watch(taxDocumentProvider);
  final business = BusinessMonth.of(invoices, transactions, now);
  final fixed = withBillCommitments(
    withIvaCommitment(commitments, business),
    bills,
  );
  final plan = buildReminders(
    now: now,
    payments: upcomingPayments(
      accounts: accounts,
      commitments: fixed,
      scope: Scope.all,
    ),
    invoices: invoices,
    investments: investments,
    recurring: detectRecurring(transactions, now),
    obligations: document == null
        ? const []
        : buildTaxCalendar(
            document: document,
            now: now,
            hasBusiness: hasBusiness,
          ),
    enabled: ref.watch(noticePrefsProvider),
    hasBusiness: hasBusiness,
  );
  return applyQuietHours(plan, prefs.quiet);
});

/// Implementación con `flutter_local_notifications` (iOS y Android).
class FlutterLocalNotifier implements LocalNotifier {
  FlutterLocalNotifier({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  void Function(String route)? _onOpen;

  static const _category = 'qullqi.reminder';
  static const _openAction = 'open';
  static const _snoozeAction = 'snooze';

  @override
  Future<void> init({required void Function(String route) onOpen}) async {
    _onOpen = onOpen;
    tzdata.initializeTimeZones();
    // Colombia no cambia de hora: una sola zona para todo el país.
    tz.setLocalLocation(tz.getLocation('America/Bogota'));
    await _plugin.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // El permiso se pide cuando la persona activa los avisos.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(
              _category,
              actions: [
                DarwinNotificationAction.plain(
                  _openAction,
                  'Ver',
                  options: {DarwinNotificationActionOption.foreground},
                ),
                DarwinNotificationAction.plain(
                  _snoozeAction,
                  'Recordármelo mañana',
                ),
              ],
            ),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: _onResponse,
    );
    // Si la app se abrió tocando una notificación, también lleva a su pantalla.
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final response = launch?.notificationResponse;
    if ((launch?.didNotificationLaunchApp ?? false) && response != null) {
      _onResponse(response);
    }
  }

  void _onResponse(NotificationResponse response) {
    final data = decodePayload(response.payload);
    if (data == null) return;
    if (response.actionId == _snoozeAction) {
      unawaited(_snooze(data));
      return;
    }
    final route = data['route'];
    if (route is String) _onOpen?.call(route);
  }

  /// Vuelve a mostrarla mañana a las 9.
  Future<void> _snooze(Map<String, Object?> data) async {
    final tomorrow = tz.TZDateTime.now(tz.local).add(const Duration(days: 1));
    final when = tz.TZDateTime(
      tz.local,
      tomorrow.year,
      tomorrow.month,
      tomorrow.day,
      reminderHour,
    );
    await _plugin.zonedSchedule(
      id: stableId('posponer:${data['route']}:${when.toIso8601String()}'),
      scheduledDate: when,
      notificationDetails: _details(
        subtitle: '${data['subtitle'] ?? ''}',
        body: '${data['body'] ?? ''}',
        thread: '${data['kind'] ?? 'avisos'}',
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: '${data['title'] ?? 'Qullqi'}',
      body: '${data['body'] ?? ''}',
      payload: jsonEncode(data),
    );
  }

  NotificationDetails _details({
    required String subtitle,
    required String body,
    required String thread,
  }) => NotificationDetails(
    iOS: DarwinNotificationDetails(
      subtitle: subtitle,
      threadIdentifier: thread,
      categoryIdentifier: _category,
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentSound: true,
    ),
    android: AndroidNotificationDetails(
      'avisos',
      'Avisos de Qullqi',
      channelDescription: 'Pagos, cobros y cosas por revisar.',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      subText: subtitle,
      groupKey: thread,
      styleInformation: BigTextStyleInformation(body),
      actions: [const AndroidNotificationAction(_snoozeAction, 'Mañana')],
    ),
  );

  @override
  Future<bool> requestPermission() async {
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> showNow(Reminder reminder) async {
    await _plugin.show(
      id: stableId('prueba:${reminder.id}'),
      title: reminder.title,
      body: reminder.body,
      notificationDetails: _details(
        subtitle: reminder.subtitle,
        body: reminder.body,
        thread: reminder.kind.name,
      ),
      payload: reminder.payload,
    );
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async {
    await _plugin.cancelAllPendingNotifications();
    for (final r in reminders) {
      await _plugin.zonedSchedule(
        id: r.id,
        scheduledDate: tz.TZDateTime.from(r.when, tz.local),
        notificationDetails: _details(
          subtitle: r.subtitle,
          body: r.body,
          thread: r.kind.name,
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
        payload: r.payload,
      );
    }
  }
}

/// Lee lo que guarda una notificación; `null` si no es de Qullqi.
@visibleForTesting
Map<String, Object?>? decodePayload(String? payload) {
  if (payload == null) return null;
  try {
    final decoded = jsonDecode(payload);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}
