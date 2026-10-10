import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/transactions/data/ledger.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';
import 'package:qullqi/features/transactions/presentation/transactions_controller.dart';

/// Detalle de un movimiento: qué fue, de qué cuenta, y cómo clasificarlo.
class TransactionDetailPage extends ConsumerWidget {
  const TransactionDetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tx = ref.watch(transactionByIdProvider(id));
    return Scaffold(
      appBar: AppBar(title: const Text('Movimiento')),
      body: switch (tx) {
        AsyncData(value: final t?) => _Detail(t: t),
        AsyncData() => MessageBody(
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Este movimiento ya no existe',
            message:
                'Puede que lo hayas borrado. Tus demás movimientos '
                'siguen intactos.',
            actionLabel: 'Ver movimientos',
            onAction: () => context.go(Routes.transactions),
          ),
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar el movimiento',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(transactionsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando el movimiento'),
      },
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.t});

  final Transaction t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final hasBusiness = ref.watch(currentUserProvider).hasBusiness;
    final account = ref
        .watch(accountsProvider)
        .value
        ?.where((a) => a.id == t.accountId)
        .firstOrNull;
    final (tileBg, tileFg, amountColor) = switch (t.kind) {
      TransactionKind.income => (
        c.primaryContainer,
        c.onPrimaryContainer,
        c.income,
      ),
      TransactionKind.expense => (c.surfaceMuted, c.inkMuted, c.ink),
      TransactionKind.transfer => (c.transferContainer, c.transfer, c.transfer),
    };

    Future<void> pickCategory() async {
      final picked = await pickFromSheet<String>(
        context,
        title: 'Categoría',
        selected: t.categoryId,
        options: [
          for (final cat in Categories.pickable)
            PickOption(
              value: cat.id,
              title: cat.name,
              leading: IconTile(icon: cat.icon),
            ),
        ],
      );
      if (picked == null || picked == t.categoryId || !context.mounted) return;
      // Elegir una categoría convierte un traslado por revisar en gasto.
      final updated = t.copyWith(
        categoryId: picked,
        needsReview: false,
        kind: t.kind == TransactionKind.transfer
            ? TransactionKind.expense
            : t.kind,
      );
      await saveTransaction(
        context,
        ref,
        updated,
        done: 'Categoría: ${Categories.byId(picked).name}',
        undo: t,
      );
    }

    Future<void> delete() async {
      final ok = await confirmDestructive(
        context,
        title: '¿Borrar este movimiento?',
        message:
            'Se quita de tu historial y de tus totales. No se puede '
            'deshacer.',
        confirmLabel: 'Borrar ${t.title}',
      );
      if (!ok || !context.mounted) return;
      try {
        // Borra y devuelve el saldo de la cuenta a como estaba.
        await ref.read(ledgerProvider).remove(t);
        if (context.mounted) {
          showQToast(context, 'Borramos ${t.title}');
          context.pop();
        }
      } on Object {
        if (context.mounted) {
          showQToast(context, 'No pudimos borrarlo. Inténtalo de nuevo.');
        }
      }
    }

    final signed = t.kind == TransactionKind.expense ? -t.amount : t.amount;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xxl,
      ),
      children: [
        Row(
          children: [
            IconTile(
              icon: t.category.icon,
              size: AppSize.avatarLg,
              background: tileBg,
              foreground: tileFg,
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(t.title, style: context.text.headlineSmall),
                  ),
                  Text(
                    '${Dates.longDay(t.date)} · ${Dates.time(t.date)}',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        Semantics(
          label: '${t.kind.label}: ${Cop.spoken(t.amount)}',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.kind.label, style: context.text.bodySmall),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MoneyText(
                  t.kind == TransactionKind.transfer ? t.amount : signed,
                  signed: t.kind == TransactionKind.income,
                  currency: true,
                  style: AppTypography.display.copyWith(color: amountColor),
                ),
              ),
            ],
          ),
        ),
        if (t.needsReview) ...[
          const SizedBox(height: AppSpace.md),
          QBanner(
            tone: BannerTone.info,
            title: 'Parece un traslado entre tus cuentas',
            message: 'Confírmalo para que no cuente como gasto.',
            actionLabel: 'Revisar',
            onAction: () => context.push(Routes.reviewTransfers),
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        QCard(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          child: Column(
            children: [
              SettingsRow(
                icon: t.category.icon,
                title: 'Categoría',
                subtitle: t.category.name,
                onTap: pickCategory,
              ),
              const Divider(),
              SettingsRow(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Cuenta',
                subtitle: account == null
                    ? 'Cuenta sin conexión'
                    : account.isCard
                    ? account.shortName
                    : '${account.shortName} · ${account.detail}',
              ),
            ],
          ),
        ),
        if (hasBusiness) ...[
          const SizedBox(height: AppSpace.lg),
          const SectionHeader('¿De quién es?'),
          const SizedBox(height: AppSpace.xs),
          SegmentedButton<Ownership>(
            showSelectedIcon: false,
            segments: [
              for (final o in Ownership.values)
                ButtonSegment(value: o, label: Text(o.label)),
            ],
            selected: {t.ownership},
            onSelectionChanged: (s) => saveTransaction(
              context,
              ref,
              t.copyWith(ownership: s.first),
              done: s.first == Ownership.business
                  ? 'Lo pasamos a Negocio'
                  : 'Lo pasamos a Personal',
              undo: t,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'Cambia en qué vista aparece y cómo cuenta en tus reportes.',
            style: context.text.bodySmall,
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        _NoteField(t: t),
        const SizedBox(height: AppSpace.xl),
        if (t.canDelete)
          QButton.text(
            label: 'Borrar movimiento',
            icon: Icons.delete_outline_rounded,
            color: c.danger,
            onPressed: delete,
          )
        else
          Text(
            'Este movimiento viene de tu banco: puedes clasificarlo, pero no '
            'borrarlo.',
            style: context.text.bodySmall,
          ),
      ],
    );
  }
}

class _NoteField extends ConsumerStatefulWidget {
  const _NoteField({required this.t});

  final Transaction t;

  @override
  ConsumerState<_NoteField> createState() => _NoteFieldState();
}

class _NoteFieldState extends ConsumerState<_NoteField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.t.note ?? '',
  );
  bool _saving = false;

  bool get _changed => _c.text.trim() != (widget.t.note ?? '');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await saveTransaction(
      context,
      ref,
      widget.t.copyWith(note: _c.text),
      done: _c.text.trim().isEmpty ? 'Quitamos la nota' : 'Guardamos tu nota',
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _c,
          minLines: 1,
          maxLines: 4,
          maxLength: 140,
          textCapitalization: TextCapitalization.sentences,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: 'Nota',
            hintText: 'Ej. Almuerzo con el cliente',
          ),
        ),
        if (_changed)
          QButton.secondary(
            label: 'Guardar nota',
            loading: _saving,
            loadingLabel: 'Guardando',
            onPressed: _save,
          ),
      ],
    );
  }
}
