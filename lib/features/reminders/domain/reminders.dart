import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/features/business/domain/business.dart';
import 'package:qullqi/features/home/domain/money_summary.dart';
import 'package:qullqi/features/investments/domain/investment.dart';
import 'package:qullqi/features/notifications/domain/notice.dart';
import 'package:qullqi/features/profile/data/push_prefs.dart';
import 'package:qullqi/features/recurring/domain/recurring.dart';
import 'package:qullqi/features/taxes/domain/tax_calendar.dart';

/// iOS guarda hasta 64 notificaciones programadas: nos quedamos por debajo.
const int maxReminders = 60;

/// Hora a la que llegan los recordatorios de "faltan N días".
const int reminderHour = 9;

/// Hora a la que llega el recordatorio del mismo día.
const int dueDayHour = 8;

/// Una notificación que se programa para el futuro.
@immutable
class Reminder {
  const Reminder({
    required this.id,
    required this.when,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.route,
    required this.kind,
  });

  final int id;
  final DateTime when;
  final String title;

  /// La línea corta bajo el título: "Vence en 3 días".
  final String subtitle;
  final String body;

  /// A dónde lleva tocarla.
  final String route;
  final NoticeKind kind;

  Reminder movedTo(DateTime t) => Reminder(
    id: id,
    when: t,
    title: title,
    subtitle: subtitle,
    body: body,
    route: route,
    kind: kind,
  );

  /// Lo que la notificación guarda para poder abrirse o posponerse.
  String get payload => jsonEncode({
    'route': route,
    'title': title,
    'subtitle': subtitle,
    'body': body,
    'kind': kind.name,
  });
}

/// Identificador estable (FNV-1a de 31 bits): el mismo aviso siempre cae en
/// el mismo número, así reprogramar no duplica.
int stableId(String key) {
  var h = 0x811c9dc5;
  for (final c in key.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

DateTime _at(DateTime day, int hour) =>
    DateTime(day.year, day.month, day.day, hour);

/// Los recordatorios que hay que programar a partir de lo que viene.
///
/// Respeta qué tipos de aviso quiere la persona y no programa nada en el
/// pasado. Del más próximo al más lejano, hasta [maxReminders].
List<Reminder> buildReminders({
  required DateTime now,
  required List<UpcomingPayment> payments,
  required List<Invoice> invoices,
  required List<Investment> investments,
  required List<RecurringCharge> recurring,
  required List<Obligation> obligations,
  required Set<NoticeKind> enabled,
  required bool hasBusiness,
}) {
  final out = <Reminder>[];

  void add({
    required String key,
    required NoticeKind kind,
    required DateTime when,
    required String title,
    required String subtitle,
    required String body,
    required String route,
  }) {
    if (!when.isAfter(now)) return;
    out.add(
      Reminder(
        id: stableId('$key|${when.toIso8601String()}'),
        when: when,
        title: title,
        subtitle: subtitle,
        body: body,
        route: route,
        kind: kind,
      ),
    );
  }

  if (enabled.contains(NoticeKind.payments)) {
    for (final p in payments) {
      if (p.ownership == Ownership.business && !hasBusiness) continue;
      final due = dateOnly(p.due);
      final title = p.kind == PaymentKind.card ? 'Paga tu ${p.title}' : p.title;
      final route = p.kind == PaymentKind.card && p.accountId != null
          ? Routes.account(p.accountId!)
          : Routes.home;
      final body = p.minimum == null
          ? Cop.format(p.amount)
          : '${Cop.format(p.amount)} · mínimo ${Cop.format(p.minimum!)}';
      add(
        key: 'pago:${p.id}:3',
        kind: NoticeKind.payments,
        when: _at(
          due.subtract(const Duration(days: paymentNoticeDays)),
          reminderHour,
        ),
        title: title,
        subtitle: 'Vence en $paymentNoticeDays días',
        body: body,
        route: route,
      );
      add(
        key: 'pago:${p.id}:0',
        kind: NoticeKind.payments,
        when: _at(due, dueDayHour),
        title: title,
        subtitle: 'Vence hoy',
        body: body,
        route: route,
      );
    }
  }

  if (enabled.contains(NoticeKind.invoices) && hasBusiness) {
    for (final i in invoices.where((i) => i.paidOn == null)) {
      final due = dateOnly(i.due);
      add(
        key: 'factura:${i.id}',
        kind: NoticeKind.invoices,
        when: _at(due.subtract(const Duration(days: 1)), reminderHour),
        title: 'Mañana vence el cobro de ${i.client}',
        subtitle: i.number,
        body: Cop.format(i.total),
        route: Routes.invoice(i.id),
      );
    }
  }

  if (enabled.contains(NoticeKind.investments)) {
    for (final i in investments) {
      final m = i.maturity;
      if (m == null) continue;
      add(
        key: 'cdt:${i.id}',
        kind: NoticeKind.investments,
        when: _at(
          dateOnly(m).subtract(const Duration(days: maturityNoticeDays)),
          reminderHour,
        ),
        title: 'Se acerca el vencimiento de ${i.name}',
        subtitle: 'Vence el ${Dates.dayMonth(m)}',
        body: 'Decide si lo renuevas o lo retiras en tu entidad.',
        route: Routes.investment(i.id),
      );
    }
  }

  if (enabled.contains(NoticeKind.recurring)) {
    for (final r in recurring) {
      add(
        key: 'recurrente:${r.key}',
        kind: NoticeKind.recurring,
        when: _at(
          dateOnly(r.nextDate).subtract(const Duration(days: 1)),
          reminderHour,
        ),
        title: '${r.title} se cobra mañana',
        subtitle: 'Cada mes',
        body: Cop.format(r.amount),
        route: Routes.recurring,
      );
    }
  }

  if (enabled.contains(NoticeKind.obligations)) {
    for (final o in obligations) {
      final due = dateOnly(o.due);
      add(
        key: 'impuesto:${o.id}:7',
        kind: NoticeKind.obligations,
        when: _at(
          due.subtract(const Duration(days: obligationNoticeDays)),
          reminderHour,
        ),
        title: o.title,
        subtitle: 'Vence el ${Dates.dayMonth(due)}',
        body: '${o.detail}. Fecha de referencia: confírmala en la DIAN.',
        route: Routes.taxes,
      );
    }
  }

  out.sort((a, b) => a.when.compareTo(b.when));
  return out.take(maxReminders).toList();
}

/// Mueve al final del silencio los recordatorios que caerían en el horario de
/// "no molestar".
List<Reminder> applyQuietHours(List<Reminder> all, QuietHours quiet) {
  final to = quiet.toHour;
  if (to == null) return all;
  return [
    for (final r in all)
      if (quiet.contains(r.when))
        r.movedTo(
          r.when.hour >= (quiet.fromHour ?? 0)
              // Pasada la hora de inicio: sigue el silencio hasta mañana.
              ? DateTime(r.when.year, r.when.month, r.when.day + 1, to)
              : DateTime(r.when.year, r.when.month, r.when.day, to),
        )
      else
        r,
  ];
}
