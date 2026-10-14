import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';
import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/format/dates.dart';
import 'package:inti/core/money/money.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart';
import 'package:inti/features/accounts/domain/account.dart';
import 'package:inti/features/accounts/presentation/widgets/account_picker.dart';
import 'package:inti/features/business/data/business_back_office.dart';
import 'package:inti/features/business/domain/bill.dart';
import 'package:inti/features/transactions/data/ledger.dart';
import 'package:inti/features/transactions/domain/transaction.dart';

/// Etiqueta de estado de una cuenta por pagar.
StatusPill billPill(Bill b, DateTime now) => switch (b.statusAt(now)) {
  BillStatus.paid => const StatusPill('Pagada', tone: PillTone.primary),
  BillStatus.overdue => StatusPill(
    'Vencida hace ${-daysBetween(now, b.due)} '
    '${-daysBetween(now, b.due) == 1 ? 'día' : 'días'}',
    tone: PillTone.danger,
  ),
  BillStatus.pending => StatusPill(Dates.dueLabel(b.due, now)),
};

/// Cuentas por pagar: lo que le debe tu negocio a sus proveedores.
class BillsPage extends ConsumerWidget {
  const BillsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(billsProvider);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('Cuentas por pagar')),
      body: switch (bills) {
        AsyncData(:final value) when value.isEmpty => MessageBody(
          child: EmptyState(
            icon: Icons.request_page_outlined,
            title: 'Anota lo que debes',
            message:
                'Registra lo que le debes a tus proveedores. Cuenta en lo que '
                'puedes gastar y te avisamos antes de que venza.',
            actionLabel: 'Registrar cuenta por pagar',
            onAction: () => context.push(Routes.newBill),
          ),
        ),
        AsyncData(:final value) => _list(context, ref, value, now),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar tus cuentas por pagar',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(billsProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando tus cuentas por pagar'),
      },
    );
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    List<Bill> all,
    DateTime now,
  ) {
    List<Bill> of(BillStatus s) =>
        all.where((b) => b.statusAt(now) == s).toList()
          ..sort((a, b) => a.due.compareTo(b.due));
    final groups = [
      ('Vencidas', of(BillStatus.overdue)),
      ('Por pagar', of(BillStatus.pending)),
      ('Pagadas', of(BillStatus.paid)),
    ].where((g) => g.$2.isNotEmpty);
    final open = all.where((b) => b.paidOn == null);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xxl,
      ),
      children: [
        HeroBalance(
          label: 'Le debes a proveedores',
          value: open.fold(0, (s, b) => s + b.amount),
          caption: open.length == 1
              ? '1 cuenta por pagar'
              : '${open.length} cuentas por pagar',
        ),
        const SizedBox(height: AppSpace.md),
        QButton.secondary(
          label: 'Registrar cuenta por pagar',
          icon: Icons.add_rounded,
          onPressed: () => context.push(Routes.newBill),
        ),
        for (final (title, items) in groups) ...[
          const SizedBox(height: AppSpace.lg),
          SectionHeader(title),
          const SizedBox(height: AppSpace.xs),
          for (final b in items) ...[
            _BillTile(
              bill: b,
              now: now,
              onTap: () => _actions(context, ref, b, now),
            ),
            const SizedBox(height: AppSpace.xs),
          ],
        ],
      ],
    );
  }

  Future<void> _actions(
    BuildContext context,
    WidgetRef ref,
    Bill b,
    DateTime now,
  ) {
    return showQSheet<void>(
      context,
      title: b.supplier,
      builder: (sheet) {
        final c = sheet.colors;
        Future<void> pay() async {
          Navigator.of(sheet).pop();
          final all = ref.read(accountsProvider).value ?? const <Account>[];
          final business = all
              .where((a) => !a.isCard && a.ownership == Ownership.business)
              .toList();
          final choices = business.isEmpty
              ? all.where((a) => !a.isCard).toList()
              : business;
          final accountId = await pickAccount(
            context,
            title: '¿De qué cuenta pagaste?',
            accounts: choices,
          );
          if (accountId == null || !context.mounted) return;
          try {
            // El pago queda como gasto del negocio y baja el saldo.
            await ref
                .read(ledgerProvider)
                .record(
                  kind: TransactionKind.expense,
                  amount: b.amount,
                  accountId: accountId,
                  categoryId: b.categoryId,
                  ownership: Ownership.business,
                  title: b.supplier,
                  note: b.concept,
                );
            await ref.read(billsRepositoryProvider).markPaid(b.id);
            if (context.mounted) {
              showQToast(
                context,
                'Pagaste ${Cop.format(b.amount)} a ${b.supplier}',
              );
            }
          } on Object {
            if (context.mounted) {
              showQToast(context, 'No pudimos guardarlo. Inténtalo de nuevo.');
            }
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${b.concept} · ${Cop.format(b.amount)} · '
              '${Dates.dayMonth(b.due)}',
              style: AppTypography.body.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: AppSpace.lg),
            if (b.paidOn == null)
              QButton(
                label: 'Marcar como pagada',
                icon: Icons.check_rounded,
                onPressed: pay,
              ),
            const SizedBox(height: AppSpace.xs),
            QButton.text(
              label: 'Eliminar cuenta por pagar',
              icon: Icons.delete_outline_rounded,
              color: c.danger,
              onPressed: () async {
                Navigator.of(sheet).pop();
                final ok = await confirmDestructive(
                  context,
                  title: '¿Eliminar esta cuenta por pagar?',
                  message:
                      'Deja de contar en lo que debes y en tus pagos '
                      'próximos.',
                  confirmLabel: 'Eliminar ${b.supplier}',
                );
                if (!ok || !context.mounted) return;
                await ref.read(billsRepositoryProvider).delete(b.id);
                if (context.mounted) {
                  showQToast(context, 'Eliminamos la cuenta de ${b.supplier}');
                }
              },
            ),
          ],
        );
      },
    );
  }
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.bill, required this.now, required this.onTap});

  final Bill bill;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final b = bill;
    final pill = billPill(b, now);
    return QCard(
      onTap: onTap,
      semanticLabel:
          '${b.supplier}. ${b.concept}. ${Cop.spoken(b.amount)}. '
          '${pill.label}',
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: ExcludeSemantics(
        child: AmountRowLayout(
          leading: const IconTile(icon: Icons.request_page_outlined),
          title: b.supplier,
          titleLines: 2,
          details: [
            Text(b.concept, style: context.text.bodySmall),
            const SizedBox(height: AppSpace.xxs),
            pill,
          ],
          trailing: MoneyText(
            b.amount,
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

/// Plazos sugeridos (días desde hoy).
const _dueOptions = [0, 7, 15, 30];

String _dueLabel(int d) => d == 0 ? 'Hoy' : 'En $d días';

/// Registrar una cuenta por pagar.
class NewBillPage extends ConsumerStatefulWidget {
  const NewBillPage({super.key});

  @override
  ConsumerState<NewBillPage> createState() => _NewBillPageState();
}

class _NewBillPageState extends ConsumerState<NewBillPage> {
  final _supplier = TextEditingController();
  final _concept = TextEditingController();
  final _amount = TextEditingController();
  int _days = 15;
  String _categoryId = Categories.other.id;
  bool _tried = false;
  bool _saving = false;

  int get _value => AmountInput.value(_amount.text);

  @override
  void dispose() {
    _supplier.dispose();
    _concept.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _tried = true);
    if (_supplier.text.trim().length < 2 ||
        _concept.text.trim().length < 2 ||
        _value <= 0) {
      return;
    }
    setState(() => _saving = true);
    final today = dateOnly(ref.read(clockProvider)());
    try {
      await ref
          .read(billsRepositoryProvider)
          .create(
            supplier: _supplier.text,
            concept: _concept.text,
            amount: _value,
            due: today.add(Duration(days: _days)),
            categoryId: _categoryId,
          );
      if (!mounted) return;
      showQToast(context, 'Registramos la cuenta de ${_supplier.text.trim()}');
      context.pop();
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos guardarla. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DiscardGuard(
      dirty:
          !_saving &&
          (_supplier.text.isNotEmpty ||
              _concept.text.isNotEmpty ||
              _amount.text.isNotEmpty),
      title: '¿Descartar esta cuenta por pagar?',
      confirmLabel: 'Descartar cuenta',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Cuenta por pagar'),
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
                controller: _supplier,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Proveedor',
                  hintText: 'Ej. Papelería El Norte',
                  errorText: _tried && _supplier.text.trim().length < 2
                      ? 'Escribe a quién le debes.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _concept,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Qué es',
                  hintText: 'Ej. Insumos de oficina',
                  errorText: _tried && _concept.text.trim().length < 2
                      ? 'Describe qué compraste.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(AmountInput.maxDigits),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Valor a pagar',
                  prefixText: r'$ ',
                  helperText: _value == 0 ? null : Cop.format(_value),
                  errorText: _tried && _value <= 0
                      ? 'Escribe cuánto debes.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('¿Cuándo vence?'),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  for (final d in _dueOptions)
                    ChoiceChip(
                      label: Text(_dueLabel(d)),
                      selected: _days == d,
                      onSelected: (_) => setState(() => _days = d),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('Categoría del gasto'),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  for (final cat in Categories.pickable)
                    ChoiceChip(
                      label: Text(cat.name),
                      selected: _categoryId == cat.id,
                      onSelected: (_) => setState(() => _categoryId = cat.id),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.xl),
              QButton(
                label: 'Registrar cuenta por pagar',
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
