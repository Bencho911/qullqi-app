import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';
import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/format/dates.dart';
import 'package:inti/core/money/money.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/core/scope/scope_provider.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart';
import 'package:inti/features/accounts/domain/account.dart';
import 'package:inti/features/accounts/presentation/widgets/account_picker.dart';
import 'package:inti/features/business/data/business_back_office.dart';
import 'package:inti/features/business/data/invoices_repository.dart';
import 'package:inti/features/business/domain/business.dart';
import 'package:inti/features/business/domain/reconcile.dart';
import 'package:inti/features/transactions/data/ledger.dart';
import 'package:inti/features/transactions/data/transactions_repository.dart';
import 'package:inti/features/transactions/domain/transaction.dart';

/// Etiqueta de estado de una factura.
StatusPill invoicePill(Invoice i, DateTime now) => switch (i.statusAt(now)) {
  InvoiceStatus.paid => const StatusPill('Pagada', tone: PillTone.primary),
  InvoiceStatus.overdue => StatusPill(
    'Vencida hace ${-daysBetween(now, i.due)} '
    '${-daysBetween(now, i.due) == 1 ? 'día' : 'días'}',
    tone: PillTone.danger,
  ),
  InvoiceStatus.pending => StatusPill(Dates.dueLabel(i.due, now)),
};

/// Bloque del negocio en el Inicio (vista Negocio): utilidad, cobros e IVA.
class BusinessSummaryCard extends StatelessWidget {
  const BusinessSummaryCard({
    required this.month,
    required this.now,
    super.key,
  });

  final BusinessMonth month;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final iva = month.iva;
    return QCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.sm,
        AppSpace.md,
        AppSpace.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailLine(
            'Utilidad de ${Dates.month(now)}',
            Cop.format(month.profit),
            emphasis: true,
          ),
          Text(
            'Ingresos ${Cop.format(month.income)} · gastos '
            '${Cop.format(month.expense)}',
            style: context.text.bodySmall,
          ),
          const Divider(height: AppSpace.lg),
          SettingsRow(
            icon: Icons.receipt_long_outlined,
            title: 'Facturas por cobrar',
            subtitle: month.overdueCount == 0
                ? Cop.format(month.receivable)
                : '${Cop.format(month.receivable)} · '
                      '${month.overdueCount} '
                      '${month.overdueCount == 1 ? 'vencida' : 'vencidas'}',
            onTap: () => context.push(Routes.invoices),
          ),
          SettingsRow(
            icon: Icons.account_balance_outlined,
            title: 'IVA de ${iva.label}',
            subtitle:
                '${Cop.format(iva.toPay)} · '
                '${Dates.dueLabel(iva.due, now).toLowerCase()}',
            onTap: () => context.push(Routes.iva),
          ),
          SettingsRow(
            icon: Icons.storefront_outlined,
            title: 'Más herramientas del negocio',
            subtitle: 'Cotizaciones, facturas recurrentes y enlaces de pago',
            onTap: () => context.push(Routes.businessHub),
          ),
        ],
      ),
    );
  }
}

/// En la vista Todo: acceso compacto al negocio.
class BusinessTeaser extends ConsumerWidget {
  const BusinessTeaser({required this.month, required this.now, super.key});

  final BusinessMonth month;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OptionRow(
      icon: Icons.storefront_outlined,
      title: 'Tu negocio',
      subtitle: 'Utilidad de ${Dates.month(now)}: ${Cop.format(month.profit)}',
      onTap: () => ref.read(scopeProvider.notifier).select(Scope.business),
    );
  }
}

/// Facturas por cobrar: vencidas primero, luego por cobrar y pagadas.
class InvoicesPage extends ConsumerWidget {
  const InvoicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoicesProvider);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('Facturas por cobrar')),
      body: switch (invoices) {
        AsyncData(:final value) when value.isEmpty => MessageBody(
          child: EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'Anota lo que te deben',
            message:
                'Registra tus facturas y te avisamos cuando se venzan. Al '
                'pagarlas, el ingreso queda en tu cuenta.',
            actionLabel: 'Registrar cobro',
            onAction: () => context.push(Routes.newInvoice),
          ),
        ),
        AsyncData(:final value) => _list(context, value, now),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar tus facturas',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(invoicesProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando tus facturas'),
      },
    );
  }

  Widget _list(BuildContext context, List<Invoice> all, DateTime now) {
    List<Invoice> of(InvoiceStatus s) =>
        all.where((i) => i.statusAt(now) == s).toList()
          ..sort((a, b) => a.due.compareTo(b.due));
    final groups = [
      ('Vencidas', of(InvoiceStatus.overdue)),
      ('Por cobrar', of(InvoiceStatus.pending)),
      ('Pagadas', of(InvoiceStatus.paid)),
    ].where((g) => g.$2.isNotEmpty);
    final open = all.where((i) => i.paidOn == null);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xxl,
      ),
      children: [
        Semantics(
          label: 'Te deben ${Cop.spoken(open.fold(0, (s, i) => s + i.total))}',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Te deben', style: context.text.bodySmall),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: MoneyText(
                  open.fold(0, (s, i) => s + i.total),
                  currency: true,
                  style: AppTypography.display.copyWith(
                    color: context.colors.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        QButton.secondary(
          label: 'Registrar cobro',
          icon: Icons.add_rounded,
          onPressed: () => context.push(Routes.newInvoice),
        ),
        for (final (title, items) in groups) ...[
          const SizedBox(height: AppSpace.lg),
          SectionHeader(title),
          const SizedBox(height: AppSpace.xs),
          for (final i in items) ...[
            _InvoiceTile(invoice: i, now: now),
            const SizedBox(height: AppSpace.xs),
          ],
        ],
      ],
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  const _InvoiceTile({required this.invoice, required this.now});

  final Invoice invoice;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final i = invoice;
    final pill = invoicePill(i, now);
    return QCard(
      onTap: () => context.push(Routes.invoice(i.id)),
      semanticLabel:
          '${i.client}. ${i.number}. ${Cop.spoken(i.total)}. ${pill.label}',
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: ExcludeSemantics(
        child: AmountRowLayout(
          leading: const IconTile(icon: Icons.receipt_long_outlined),
          title: i.client,
          titleLines: 2,
          details: [
            Text(i.number, style: context.text.bodySmall),
            const SizedBox(height: AppSpace.xxs),
            pill,
          ],
          trailing: MoneyText(
            i.total,
            animate: false,
            style: AppTypography.body.copyWith(
              color: context.colors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Detalle de una factura: valores, fechas y acciones.
class InvoiceDetailPage extends ConsumerWidget {
  const InvoiceDetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoicesProvider);
    final i = invoices.value?.where((x) => x.id == id).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Factura')),
      body: switch (invoices) {
        AsyncValue(hasValue: true) when i != null => _InvoiceDetail(i: i),
        AsyncValue(hasValue: true) => MessageBody(
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Esta factura ya no existe',
            message: 'Puede que la hayas eliminado.',
            actionLabel: 'Ver facturas',
            onAction: () => context.pushReplacement(Routes.invoices),
          ),
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar la factura',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(invoicesProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando la factura'),
      },
    );
  }
}

class _InvoiceDetail extends ConsumerWidget {
  const _InvoiceDetail({required this.i});

  final Invoice i;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final now = ref.watch(clockProvider)();
    final status = i.statusAt(now);
    final reconcileHint =
        (ref.watch(reconcileSuggestionsProvider).value ??
                const <ReconcileSuggestion>[])
            .where((s) => s.invoice.id == i.id)
            .firstOrNull;
    final businessAccounts = (ref.watch(accountsProvider).value ?? const [])
        .where((a) => !a.isCard && a.ownership == Ownership.business)
        .toList();

    Future<void> markPaid() async {
      final accounts = businessAccounts.isEmpty
          ? (ref.read(accountsProvider).value ?? const <Account>[])
                .where((a) => !a.isCard)
                .toList()
          : businessAccounts;
      final accountId = await pickAccount(
        context,
        title: '¿A qué cuenta llegó la plata?',
        accounts: accounts,
      );
      if (accountId == null || !context.mounted) return;
      try {
        // El pago queda como ingreso del negocio y sube el saldo.
        await ref
            .read(ledgerProvider)
            .record(
              kind: TransactionKind.income,
              amount: i.total,
              accountId: accountId,
              categoryId: Categories.fees.id,
              ownership: Ownership.business,
              title: 'Pago ${i.client}',
              note: 'Factura ${i.number}',
            );
        await ref.read(invoicesRepositoryProvider).markPaid(i.id);
        if (context.mounted) {
          showQToast(context, '${i.number} pagada: ${Cop.format(i.total)}');
        }
      } on Object {
        if (context.mounted) {
          showQToast(context, 'No pudimos guardarlo. Inténtalo de nuevo.');
        }
      }
    }

    Future<void> remind() async {
      final text =
          'Hola, te recuerdo la factura ${i.number} por '
          '${Cop.format(i.total)}, con vencimiento el '
          '${Dates.dayMonth(i.due)}. ¡Gracias!';
      await Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) {
        showQToast(context, 'Copiamos el recordatorio para que lo envíes');
      }
    }

    Future<void> delete() async {
      final ok = await confirmDestructive(
        context,
        title: '¿Eliminar la factura ${i.number}?',
        message: 'Deja de contar en tus cobros y en tu IVA estimado.',
        confirmLabel: 'Eliminar ${i.number}',
      );
      if (!ok || !context.mounted) return;
      try {
        await ref.read(invoicesRepositoryProvider).delete(i.id);
        if (context.mounted) {
          showQToast(context, 'Eliminamos ${i.number}');
          context.pop();
        }
      } on Object {
        if (context.mounted) {
          showQToast(context, 'No pudimos eliminarla. Inténtalo de nuevo.');
        }
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xxl,
      ),
      children: [
        Semantics(
          header: true,
          child: Text(i.client, style: context.text.headlineSmall),
        ),
        Text(i.number, style: context.text.bodySmall),
        if (reconcileHint != null) ...[
          const SizedBox(height: AppSpace.md),
          QBanner(
            tone: BannerTone.info,
            title: 'Parece que ya te pagaron',
            message:
                '${reconcileHint.deposit.title} por '
                '${Cop.format(reconcileHint.deposit.amount)} puede ser este '
                'pago.',
            actionLabel: 'Conciliar',
            onAction: () => context.push(Routes.reconcile),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        Align(alignment: Alignment.centerLeft, child: invoicePill(i, now)),
        const SizedBox(height: AppSpace.md),
        Semantics(
          label: 'Total: ${Cop.spoken(i.total)}',
          excludeSemantics: true,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: MoneyText(
              i.total,
              currency: true,
              style: AppTypography.display.copyWith(color: c.ink),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        QCard(
          child: Column(
            children: [
              DetailLine('Valor', Cop.format(i.base)),
              DetailLine(
                'IVA',
                i.chargesIva ? Cop.format(i.iva) : 'No cobra IVA',
              ),
              DetailLine('Emitida', Dates.dayMonth(i.issued)),
              DetailLine('Vence', Dates.dayMonth(i.due)),
              if (i.paidOn != null)
                DetailLine('Fecha de pago', Dates.dayMonth(i.paidOn!)),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        if (status != InvoiceStatus.paid) ...[
          QButton(
            label: 'Marcar como pagada',
            icon: Icons.check_rounded,
            onPressed: markPaid,
          ),
          const SizedBox(height: AppSpace.xs),
          QButton.secondary(
            label: 'Copiar recordatorio',
            icon: Icons.copy_rounded,
            onPressed: remind,
          ),
          const SizedBox(height: AppSpace.xs),
          QButton.secondary(
            label: 'Crear enlace de pago',
            icon: Icons.add_link_rounded,
            onPressed: () => context.push(Routes.newPaymentLinkFor(i.id)),
          ),
        ],
        const SizedBox(height: AppSpace.xl),
        QButton.text(
          label: 'Eliminar factura',
          icon: Icons.delete_outline_rounded,
          color: c.danger,
          onPressed: delete,
        ),
      ],
    );
  }
}

/// Plazos de pago sugeridos (días).
const _terms = [15, 30, 60];

/// Registrar un cobro (factura por cobrar).
class NewInvoicePage extends ConsumerStatefulWidget {
  const NewInvoicePage({super.key});

  @override
  ConsumerState<NewInvoicePage> createState() => _NewInvoicePageState();
}

class _NewInvoicePageState extends ConsumerState<NewInvoicePage> {
  final _client = TextEditingController();
  final _base = TextEditingController();
  bool _iva = true;
  int _days = 30;
  bool _tried = false;
  bool _saving = false;

  int get _amount => AmountInput.value(_base.text);

  @override
  void dispose() {
    _client.dispose();
    _base.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _tried = true);
    if (_client.text.trim().length < 2 || _amount <= 0) return;
    setState(() => _saving = true);
    final now = ref.read(clockProvider)();
    try {
      final inv = await ref
          .read(invoicesRepositoryProvider)
          .create(
            client: _client.text,
            base: _amount,
            chargesIva: _iva,
            due: dateOnly(now).add(Duration(days: _days)),
          );
      if (!mounted) return;
      showQToast(
        context,
        'Registramos ${inv.number} por ${Cop.format(inv.total)}',
      );
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos guardarla. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final iva = _iva ? (_amount * ivaRate).round() : 0;
    return DiscardGuard(
      dirty: !_saving && (_client.text.isNotEmpty || _base.text.isNotEmpty),
      title: '¿Descartar este cobro?',
      confirmLabel: 'Descartar cobro',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Registrar cobro'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.xs,
              AppSpace.gutter,
              AppSpace.xl,
            ),
            children: [
              TextField(
                controller: _client,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Cliente',
                  hintText: 'Ej. Estudio Alameda S.A.S.',
                  errorText: _tried && _client.text.trim().length < 2
                      ? 'Escribe a quién le cobras.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              // Formulario de varios campos: el monto usa el teclado del
              // sistema (el teclado propio es para pantallas de solo monto).
              TextField(
                controller: _base,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(AmountInput.maxDigits),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Valor antes de IVA',
                  prefixText: r'$ ',
                  errorText: _tried && _amount <= 0
                      ? 'Escribe el valor de la factura.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              SwitchRow(
                title: 'Cobra IVA (19 %)',
                subtitle: 'Si eres responsable de IVA.',
                value: _iva,
                onChanged: (v) => setState(() => _iva = v),
              ),
              const SizedBox(height: AppSpace.md),
              const SectionHeader('Plazo de pago'),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                children: [
                  for (final d in _terms)
                    ChoiceChip(
                      label: Text('$d días'),
                      selected: _days == d,
                      onSelected: (_) => setState(() => _days = d),
                    ),
                ],
              ),
              if (_amount > 0) ...[
                const SizedBox(height: AppSpace.lg),
                QCard(
                  child: Column(
                    children: [
                      DetailLine('Valor', Cop.format(_amount)),
                      DetailLine('IVA', Cop.format(iva)),
                      DetailLine(
                        'Total a cobrar',
                        Cop.format(_amount + iva),
                        emphasis: true,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.xl),
              QButton(
                label: 'Registrar cobro',
                loading: _saving,
                loadingLabel: 'Guardando',
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// IVA estimado del bimestre, explicado.
class IvaPage extends ConsumerWidget {
  const IvaPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoices = ref.watch(invoicesProvider);
    final txs = ref.watch(transactionsProvider);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('IVA estimado')),
      body: switch ((invoices, txs)) {
        (AsyncData(value: final inv), AsyncData(value: final t)) => _body(
          context,
          IvaEstimate.of(inv, t, now),
          now,
        ),
        (AsyncError(), _) || (_, AsyncError()) => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos calcular tu IVA',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref
              ..invalidate(invoicesProvider)
              ..invalidate(transactionsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Calculando tu IVA'),
      },
    );
  }

  Widget _body(BuildContext context, IvaEstimate iva, DateTime now) {
    final c = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xxl,
      ),
      children: [
        Semantics(
          header: true,
          child: Text(
            'Bimestre de ${iva.label}',
            style: context.text.headlineSmall,
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Semantics(
          label: 'A pagar: ${Cop.spoken(iva.toPay)}',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('A pagar', style: context.text.bodySmall),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: MoneyText(
                  iva.toPay,
                  currency: true,
                  style: AppTypography.display.copyWith(color: c.ink),
                ),
              ),
              Text(
                'Declaras hasta el ${Dates.dayMonth(iva.due)} · '
                '${Dates.dueLabel(iva.due, now).toLowerCase()}',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        QCard(
          child: Column(
            children: [
              DetailLine('IVA que cobraste', Cop.format(iva.generated)),
              DetailLine(
                'IVA de tus gastos del negocio',
                '-${Cop.format(iva.deductible)}',
              ),
              DetailLine('A pagar', Cop.format(iva.toPay), emphasis: true),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        const TrustNote(
          'Es un estimado con lo que registras en Inti; tu contador '
          'confirma el valor final. Ya lo descontamos de tu disponible.',
        ),
        const SizedBox(height: AppSpace.xl),
        const SectionHeader('Facturas del bimestre'),
        if (iva.invoices.isEmpty)
          const SectionNote('No registraste facturas en este bimestre.')
        else
          for (final i in iva.invoices)
            DetailLine('${i.number} · ${i.client}', Cop.format(i.iva)),
      ],
    );
  }
}
