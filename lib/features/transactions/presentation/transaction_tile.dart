import 'package:flutter/material.dart';

import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/domain/account.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';

/// Un movimiento como fila: "Hoy 14:32 · Nequi".
class TransactionTile extends StatelessWidget {
  const TransactionTile({
    required this.transaction,
    required this.accounts,
    required this.now,
    super.key,
    this.showOwnership = false,
    this.showDay = true,
    this.showReview = true,
    this.onTap,
  });

  final Transaction transaction;

  /// Para mostrar el nombre de la cuenta.
  final List<Account> accounts;
  final DateTime now;

  /// Etiqueta de ámbito (solo en la vista Todo, y solo para Negocio: lo
  /// personal es lo esperado y no necesita marca).
  final bool showOwnership;
  final VoidCallback? onTap;

  /// En listas agrupadas por día el encabezado ya dice el día: solo la hora.
  final bool showDay;

  /// En la pantalla de revisión todos están por revisar: sin etiqueta.
  final bool showReview;

  @override
  Widget build(BuildContext context) {
    final t = transaction;
    final account = accounts.where((a) => a.id == t.accountId).firstOrNull;
    final accountName = account?.shortName;
    final when = showDay
        ? '${Dates.relativeDay(t.date, now)} ${Dates.time(t.date)}'
        : Dates.time(t.date);
    // La fecha va primero para que nunca se corte; la categoría ya la dice
    // el ícono y la lee el lector de pantalla.
    final subtitle = [when, ?accountName].join(' · ');

    // "Por revisar" es un traslado detectado: lleva el índigo de los traslados.
    final pill = t.needsReview && showReview
        ? const StatusPill('Por revisar', tone: PillTone.transfer)
        : showOwnership && t.ownership == Ownership.business
        ? const StatusPill('Negocio', tone: PillTone.business)
        : null;

    return TransactionRow(
      icon: t.category.icon,
      categoryLabel: t.kind == TransactionKind.transfer
          ? null
          : t.category.name,
      title: t.title,
      subtitle: subtitle,
      amount: t.amount,
      kind: switch (t.kind) {
        TransactionKind.expense => FlowKind.expense,
        TransactionKind.income => FlowKind.income,
        TransactionKind.transfer => FlowKind.transfer,
      },
      pill: pill,
      onTap: onTap,
    );
  }
}
