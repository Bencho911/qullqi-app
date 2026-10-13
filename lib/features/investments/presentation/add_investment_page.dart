import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/investments/data/investments_repository.dart';
import 'package:qullqi/features/investments/domain/investment.dart';

/// Plazos de un CDT (en meses); `null` = no sé.
const _terms = <int?>[null, 1, 3, 6, 12];

String _termLabel(int? m) => switch (m) {
  null => 'No sé',
  1 => '1 mes',
  12 => '1 año',
  _ => '$m meses',
};

/// Agregar una inversión a mano: cripto, cooperativas o lo que no tenga
/// conexión automática.
class AddInvestmentPage extends ConsumerStatefulWidget {
  const AddInvestmentPage({super.key});

  @override
  ConsumerState<AddInvestmentPage> createState() => _AddInvestmentPageState();
}

class _AddInvestmentPageState extends ConsumerState<AddInvestmentPage> {
  final _name = TextEditingController();
  final _place = TextEditingController();
  final _invested = TextEditingController();
  final _value = TextEditingController();
  final _rate = TextEditingController();
  InvestmentKind _kind = InvestmentKind.cdt;
  int? _months;
  Ownership _ownership = Ownership.personal;
  bool _tried = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _place.dispose();
    _invested.dispose();
    _value.dispose();
    _rate.dispose();
    super.dispose();
  }

  int get _investedAmount => AmountInput.value(_invested.text);
  int get _valueAmount => AmountInput.value(_value.text);

  /// Tasa como fracción (10 → 0.10); `null` si está vacía o no es válida.
  double? get _rateValue {
    final v = double.tryParse(_rate.text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0 || v > 100) return null;
    return v / 100;
  }

  String? get _nameError => _name.text.trim().length < 2
      ? 'Ponle un nombre, por ejemplo "CDT" o "Bitcoin".'
      : null;

  String? get _investedError =>
      _investedAmount <= 0 ? 'Escribe cuánto pusiste.' : null;

  bool get _dirty =>
      _name.text.isNotEmpty ||
      _invested.text.isNotEmpty ||
      _value.text.isNotEmpty;

  Future<void> _save() async {
    setState(() => _tried = true);
    if (_nameError != null || _investedError != null) return;
    setState(() => _saving = true);
    final now = ref.read(clockProvider)();
    try {
      final item = await ref
          .read(investmentsRepositoryProvider)
          .addManual(
            name: _name.text,
            kind: _kind,
            institution: _place.text,
            invested: _investedAmount,
            // Sin valor de hoy, se parte de lo que pusiste.
            value: _valueAmount > 0 ? _valueAmount : _investedAmount,
            ownership: _ownership,
            maturity: _kind == InvestmentKind.cdt && _months != null
                ? DateTime(now.year, now.month + _months!, now.day)
                : null,
            annualRate: _kind == InvestmentKind.cdt ? _rateValue : null,
          );
      if (!mounted) return;
      showQToast(context, 'Agregamos ${item.name}');
      context.pushReplacement(Routes.investment(item.id));
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos guardarla. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBusiness = ref.watch(currentUserProvider).hasBusiness;
    final digitsOnly = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(AmountInput.maxDigits),
    ];
    return DiscardGuard(
      dirty: _dirty && !_saving,
      title: '¿Descartar esta inversión?',
      confirmLabel: 'Descartar inversión',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Agregar inversión'),
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
                'Para cripto, cooperativas o lo que no tenga conexión. El '
                'valor cambia cuando tú lo actualices.',
                style: context.text.bodyMedium?.copyWith(
                  color: context.colors.inkMuted,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              TextField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Nombre',
                  hintText: 'Ej. CDT a 180 días, Bitcoin, fondo',
                  errorText: _tried ? _nameError : null,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('Tipo'),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  for (final k in InvestmentKind.values)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              TextField(
                controller: _place,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Entidad (opcional)',
                  hintText: 'Ej. Bancolombia, Confiar',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              // Formulario de varios campos: el monto usa el teclado del
              // sistema (el teclado propio es para pantallas de solo monto).
              TextField(
                controller: _invested,
                keyboardType: TextInputType.number,
                inputFormatters: digitsOnly,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '¿Cuánto pusiste?',
                  prefixText: r'$ ',
                  helperText: _investedAmount == 0
                      ? null
                      : Cop.format(_investedAmount),
                  errorText: _tried ? _investedError : null,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _value,
                keyboardType: TextInputType.number,
                inputFormatters: digitsOnly,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '¿Cuánto vale hoy?',
                  prefixText: r'$ ',
                  helperText: _valueAmount == 0
                      ? 'Si lo dejas vacío, usamos lo que pusiste.'
                      : Cop.format(_valueAmount),
                ),
              ),
              if (_kind == InvestmentKind.cdt) ...[
                const SizedBox(height: AppSpace.lg),
                const SectionHeader('¿Cuándo vence?'),
                const SizedBox(height: AppSpace.xs),
                Wrap(
                  spacing: AppSpace.xs,
                  runSpacing: AppSpace.xs,
                  children: [
                    for (final m in _terms)
                      ChoiceChip(
                        label: Text(_termLabel(m)),
                        selected: _months == m,
                        onSelected: (_) => setState(() => _months = m),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                TextField(
                  controller: _rate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
                    LengthLimitingTextInputFormatter(5),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Tasa efectiva anual (opcional)',
                    suffixText: '% e. a.',
                    helperText: 'Ej. 9,8',
                  ),
                ),
              ],
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
                label: 'Agregar inversión',
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
