import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';
import 'package:qullqi/features/transactions/presentation/transaction_tile.dart';
import 'package:qullqi/features/transactions/presentation/transactions_controller.dart';

/// Traslados detectados entre cuentas propias. Si la persona confirma, no
/// cuentan como gasto ni como ingreso.
class ReviewTransfersPage extends ConsumerWidget {
  const ReviewTransfersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(transactionsViewProvider);

    Future<void> decide(Transaction t, {required bool isTransfer}) async {
      final updated = isTransfer
          ? t.copyWith(needsReview: false, kind: TransactionKind.transfer)
          : t.copyWith(
              needsReview: false,
              kind: TransactionKind.expense,
              categoryId: Categories.other.id,
            );
      await saveTransaction(
        context,
        ref,
        updated,
        done: isTransfer
            ? 'Listo: no lo contamos como gasto'
            : 'Lo dejamos como gasto en Otros',
        undo: t,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Traslados por revisar')),
      body: switch (view) {
        AsyncData(:final value) when value.toReview.isEmpty =>
          const MessageBody(
            child: EmptyState(
              icon: Icons.task_alt_rounded,
              title: 'Todo revisado',
              message:
                  'Cuando detectemos plata que pasa entre tus cuentas, te la '
                  'mostramos aquí.',
            ),
          ),
        AsyncData(:final value) => ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.xs,
            AppSpace.gutter,
            AppSpace.xxl,
          ),
          children: [
            Text(
              'Detectamos plata que salió de una cuenta tuya hacia otra tuya. '
              'Si lo confirmas, no cuenta como gasto ni como ingreso.',
              style: AppTypography.body.copyWith(
                color: context.colors.inkMuted,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            for (final t in value.toReview) ...[
              QCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // La misma fila de la lista: mismo color de traslado y
                    // mismo comportamiento con texto grande.
                    TransactionTile(
                      transaction: t,
                      accounts: value.accounts,
                      now: value.now,
                      showReview: false,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    QButton(
                      label: 'Es un traslado',
                      onPressed: () => decide(t, isTransfer: true),
                    ),
                    const SizedBox(height: AppSpace.xs),
                    QButton.secondary(
                      label: 'Es un gasto',
                      onPressed: () => decide(t, isTransfer: false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.sm),
            ],
          ],
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar tus traslados',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref
              ..invalidate(transactionsProvider)
              ..invalidate(accountsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando tus traslados', rows: 2),
      },
    );
  }
}
