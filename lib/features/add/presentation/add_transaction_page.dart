import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/scope/scope_provider.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/domain/account.dart';
import 'package:qullqi/features/accounts/presentation/widgets/account_picker.dart';
import 'package:qullqi/features/rules/data/rules_provider.dart';
import 'package:qullqi/features/rules/domain/category_rule.dart';
import 'package:qullqi/features/transactions/data/ledger.dart';
import 'package:qullqi/features/transactions/domain/transaction.dart';

/// Datos que llegan ya leídos (p. ej. desde el escáner de facturas).
@immutable
class AddPrefill {
  const AddPrefill({this.amount, this.title, this.categoryId, this.note});

  final int? amount;
  final String? title;
  final String? categoryId;

  /// Datos extra leídos (p. ej. el NIT de la factura).
  final String? note;
}

/// Categorías que se ofrecen a un toque, según el tipo.
const _quickExpense = ['mercado', 'transporte', 'salidas', 'hogar', 'salud'];
const _quickIncome = ['honorarios', 'entre-personas', 'otros'];

/// Registrar un gasto o un ingreso: monto con teclado siempre visible,
/// cuenta y categoría a un toque. Tres toques y queda guardado.
class AddTransactionPage extends ConsumerStatefulWidget {
  const AddTransactionPage({required this.kind, super.key, this.prefill});

  final TransactionKind kind;
  final AddPrefill? prefill;

  @override
  ConsumerState<AddTransactionPage> createState() => _AddTransactionPageState();
}

class _AddTransactionPageState extends ConsumerState<AddTransactionPage> {
  late String _digits = widget.prefill?.amount?.toString() ?? '';
  String? _accountId;
  late String _categoryId =
      widget.prefill?.categoryId ??
      (_isExpense ? _quickExpense.first : _quickIncome.first);
  late String _title = widget.prefill?.title ?? '';
  late String _note = widget.prefill?.note ?? '';
  Ownership? _ownership;
  bool _saving = false;
  bool _triedEmpty = false;

  bool get _isExpense => widget.kind == TransactionKind.expense;
  int get _amount => AmountInput.value(_digits);

  List<Account> _choices(List<Account> all) =>
      _isExpense ? all : all.where((a) => !a.isCard).toList();

  Account? _account(List<Account> all) {
    final choices = _choices(all);
    if (choices.isEmpty) return null;
    final scope = ref.read(scopeProvider);
    return choices.where((a) => a.id == _accountId).firstOrNull ??
        choices.where((a) => a.ownership.visibleIn(scope)).firstOrNull ??
        choices.first;
  }

  String? _overdraft(Account? a) {
    if (!_isExpense || a == null || _amount == 0) return null;
    if (a.isCard && _amount > a.availableCredit) {
      return 'Es más que el cupo libre de tu tarjeta. Puedes guardarlo igual.';
    }
    if (!a.isCard && _amount > a.balance) {
      return 'Es más de lo que tienes en ${a.shortName}. Puedes guardarlo '
          'igual.';
    }
    return null;
  }

  Future<void> _save(Account account) async {
    if (_amount <= 0) {
      setState(() => _triedEmpty = true);
      return;
    }
    setState(() => _saving = true);
    final ledger = ref.read(ledgerProvider);
    try {
      final tx = await ledger.record(
        kind: widget.kind,
        amount: _amount,
        accountId: account.id,
        categoryId: _categoryId,
        ownership: _ownership ?? account.ownership,
        title: _title,
        note: _note,
      );
      if (!mounted) return;
      showQToast(
        context,
        '${_isExpense ? 'Gasto' : 'Ingreso'} guardado: ${Cop.format(_amount)}',
        actionLabel: 'Deshacer',
        onAction: () => ledger.remove(tx),
      );
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos guardarlo. Inténtalo de nuevo.');
    }
  }

  Future<void> _details() async {
    final result = await showQSheet<(String, String)>(
      context,
      title: 'Comercio y nota',
      builder: (context) => _DetailsForm(title: _title, note: _note),
    );
    if (result != null) {
      // Si hay una regla para este comercio, la categoría sale sola.
      final rule = ruleFor(result.$1, ref.read(categoryRulesProvider));
      setState(() {
        _title = result.$1;
        _note = result.$2;
        if (rule != null) _categoryId = rule.categoryId;
      });
      if (rule != null && mounted) {
        showQToast(context, 'Categoría según tu regla: ${rule.category.name}');
      }
    }
  }

  Future<void> _moreCategories() async {
    final picked = await pickFromSheet<String>(
      context,
      title: 'Categoría',
      selected: _categoryId,
      options: [
        for (final cat in Categories.pickable)
          PickOption(
            value: cat.id,
            title: cat.name,
            leading: IconTile(icon: cat.icon),
          ),
      ],
    );
    if (picked != null) setState(() => _categoryId = picked);
  }

  @override
  Widget build(BuildContext context) {
    final noun = _isExpense ? 'gasto' : 'ingreso';
    return DiscardGuard(
      dirty: _amount > 0 && !_saving,
      title: '¿Descartar este $noun?',
      confirmLabel: 'Descartar $noun',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: Text(_isExpense ? 'Registrar gasto' : 'Registrar ingreso'),
        ),
        body: SafeArea(
          child: AccountsGate(builder: (accounts) => _form(context, accounts)),
        ),
      ),
    );
  }

  Widget _form(BuildContext context, List<Account> accounts) {
    final c = context.colors;
    final hasBusiness = ref.watch(currentUserProvider).hasBusiness;
    final account = _account(accounts);
    final quick = _isExpense ? _quickExpense : _quickIncome;
    final categoryIds = {...quick, _categoryId}.toList();
    final noun = _isExpense ? 'gasto' : 'ingreso';
    return KeypadLayout(
      fields: [
        AmountDisplay(
          digits: _digits,
          label: _isExpense ? '¿Cuánto gastaste?' : '¿Cuánto recibiste?',
          error: _triedEmpty && _amount == 0 ? 'Escribe cuánto fue.' : null,
        ),
        const SizedBox(height: AppSpace.sm),
        if (account == null)
          const SectionNote(
            'Conecta o registra una cuenta para guardar '
            'movimientos.',
          )
        else
          AccountField(
            label: _isExpense ? 'Pagaste con' : 'Llegó a',
            account: account,
            error: _overdraft(account),
            onTap: () async {
              final id = await pickAccount(
                context,
                title: _isExpense ? 'Pagaste con' : 'Llegó a',
                accounts: _choices(accounts),
                selected: account.id,
              );
              if (id != null) setState(() => _accountId = id);
            },
          ),
        const SizedBox(height: AppSpace.md),
        const SectionHeader('Categoría'),
        // Una sola fila que se desliza: deja espacio al teclado.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final id in categoryIds)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpace.xs),
                  child: ChoiceChip(
                    avatar: Icon(
                      Categories.byId(id).icon,
                      size: AppSize.iconSm,
                    ),
                    label: Text(Categories.byId(id).name),
                    selected: _categoryId == id,
                    onSelected: (_) => setState(() => _categoryId = id),
                  ),
                ),
              ActionChip(
                side: BorderSide(color: c.outlineStrong),
                label: const Text('Más categorías'),
                onPressed: _moreCategories,
              ),
            ],
          ),
        ),
        if (hasBusiness && account != null) ...[
          const SizedBox(height: AppSpace.md),
          const SectionHeader('¿De quién es?'),
          const SizedBox(height: AppSpace.xs),
          SegmentedButton<Ownership>(
            showSelectedIcon: false,
            segments: [
              for (final o in Ownership.values)
                ButtonSegment(value: o, label: Text(o.label)),
            ],
            selected: {_ownership ?? account.ownership},
            onSelectionChanged: (s) => setState(() => _ownership = s.first),
          ),
        ],
        const SizedBox(height: AppSpace.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: QButton.text(
            icon: Icons.edit_note_rounded,
            label: _title.isEmpty && _note.isEmpty
                ? 'Agregar comercio o nota'
                : 'Editar comercio o nota',
            onPressed: _details,
          ),
        ),
        if (_title.isNotEmpty || _note.isNotEmpty)
          Text(
            [_title, _note].where((s) => s.isNotEmpty).join(' · '),
            style: context.text.bodySmall,
          ),
      ],
      keypad: AmountKeypad(
        digits: _digits,
        onChanged: (d) => setState(() {
          _digits = d;
          _triedEmpty = false;
        }),
      ),
      action: QButton(
        label: 'Guardar $noun',
        loading: _saving,
        loadingLabel: 'Guardando',
        onPressed: account == null ? null : () => _save(account),
      ),
    );
  }
}

class _DetailsForm extends StatefulWidget {
  const _DetailsForm({required this.title, required this.note});

  final String title;
  final String note;

  @override
  State<_DetailsForm> createState() => _DetailsFormState();
}

class _DetailsFormState extends State<_DetailsForm> {
  late final _title = TextEditingController(text: widget.title);
  late final _note = TextEditingController(text: widget.note);

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _title,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          maxLength: 60,
          decoration: const InputDecoration(
            labelText: 'Comercio o persona',
            hintText: 'Ej. Éxito Calle 80',
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        TextField(
          controller: _note,
          textCapitalization: TextCapitalization.sentences,
          maxLength: 140,
          decoration: const InputDecoration(
            labelText: 'Nota',
            hintText: 'Ej. Almuerzo con el cliente',
          ),
        ),
        const SizedBox(height: AppSpace.md),
        QButton(
          label: 'Usar estos detalles',
          onPressed: () =>
              Navigator.of(context)
                  .pop((_title.text.trim(), _note.text.trim())),
        ),
      ],
    );
  }
}
