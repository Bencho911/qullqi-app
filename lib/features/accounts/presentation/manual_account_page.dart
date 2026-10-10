import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/accounts/domain/account.dart';

/// Agregar una cuenta a mano: efectivo, cooperativas o bancos sin conexión.
/// Sus saldos se actualizan con lo que registres.
class ManualAccountPage extends ConsumerStatefulWidget {
  const ManualAccountPage({super.key});

  @override
  ConsumerState<ManualAccountPage> createState() => _ManualAccountPageState();
}

class _ManualAccountPageState extends ConsumerState<ManualAccountPage> {
  final _name = TextEditingController();
  final _balance = TextEditingController();
  final _last4 = TextEditingController();
  AccountKind _kind = AccountKind.savings;
  Ownership _ownership = Ownership.personal;
  bool _tried = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    _last4.dispose();
    super.dispose();
  }

  String? get _nameError => _name.text.trim().length < 2
      ? 'Escribe cómo se llama, por ejemplo "Efectivo" o "Confiar".'
      : null;

  int get _amount => AmountInput.value(_balance.text);

  Future<void> _save() async {
    setState(() => _tried = true);
    if (_nameError != null) return;
    setState(() => _saving = true);
    try {
      final account = await ref
          .read(accountsRepositoryProvider)
          .addManual(
            name: _name.text,
            kind: _kind,
            balance: _amount,
            ownership: _ownership,
            last4: _last4.text,
          );
      if (!mounted) return;
      showQToast(context, 'Agregamos ${account.shortName}');
      context.pushReplacement(Routes.account(account.id));
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos guardarla. Inténtalo de nuevo.');
    }
  }

  bool get _dirty => _name.text.isNotEmpty || _balance.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final hasBusiness = ref.watch(currentUserProvider).hasBusiness;
    return DiscardGuard(
      dirty: _dirty && !_saving,
      title: '¿Descartar esta cuenta?',
      confirmLabel: 'Descartar cuenta',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Agregar cuenta a mano'),
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
              Text(
                'Para efectivo, cooperativas o bancos sin conexión. El saldo '
                'cambia con lo que registres.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.inkMuted,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Ej. Efectivo, Confiar, Cooperativa',
                  errorText: _tried ? _nameError : null,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('Tipo'),
              const SizedBox(height: AppSpace.xs),
              SegmentedButton<AccountKind>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: AccountKind.savings,
                    label: Text('Ahorros'),
                  ),
                  ButtonSegment(
                    value: AccountKind.checking,
                    label: Text('Corriente'),
                  ),
                  ButtonSegment(
                    value: AccountKind.cash,
                    label: Text('Efectivo'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: AppSpace.lg),
              // Es un formulario de varios campos: el saldo usa el teclado del
              // sistema (el teclado propio es para pantallas de solo monto).
              TextField(
                controller: _balance,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(AmountInput.maxDigits),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Saldo de hoy',
                  prefixText: r'$ ',
                  helperText: _amount == 0
                      ? 'Puedes dejarlo en 0 y registrar después.'
                      : Cop.format(_amount),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _last4,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: const InputDecoration(
                  labelText: 'Últimos 4 dígitos (opcional)',
                  helperText: 'Para reconocerla si tienes varias.',
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
                  selected: {_ownership},
                  onSelectionChanged: (s) =>
                      setState(() => _ownership = s.first),
                ),
              ],
              const SizedBox(height: AppSpace.xl),
              QButton(
                label: 'Agregar cuenta',
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
