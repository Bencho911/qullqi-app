import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';
import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/format/dates.dart';
import 'package:inti/core/money/money.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/investments/data/investments_repository.dart';
import 'package:inti/features/investments/domain/investment.dart';
import 'package:inti/features/investments/presentation/widgets/investment_widgets.dart';

/// Pantalla de "no existe" o "no cargó" para una inversión.
Widget _missingOrFailed(
  BuildContext context,
  WidgetRef ref,
  AsyncValue<List<Investment>> investments, {
  int rows = 4,
}) => switch (investments) {
  AsyncValue(hasValue: true) => MessageBody(
    child: EmptyState(
      icon: Icons.search_off_rounded,
      title: 'Esta inversión ya no existe',
      message: 'Puede que la hayas quitado.',
      actionLabel: 'Ver mis inversiones',
      onAction: () => context.go(Routes.investments),
    ),
  ),
  AsyncError() => MessageBody(
    child: EmptyState(
      icon: Icons.cloud_off_rounded,
      title: 'No pudimos cargar la inversión',
      message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
      actionLabel: 'Reintentar',
      onAction: () => ref.invalidate(investmentsProvider),
    ),
  ),
  _ => PageSkeleton(label: 'Cargando la inversión', rows: rows),
};

/// Detalle de una inversión: cuánto pusiste, cuánto vale y cómo va.
class InvestmentDetailPage extends ConsumerWidget {
  const InvestmentDetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final investments = ref.watch(investmentsProvider);
    final item = investments.value?.where((i) => i.id == id).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Inversión')),
      body: item != null
          ? _Detail(item: item)
          : _missingOrFailed(context, ref, investments),
    );
  }
}

class _Detail extends ConsumerStatefulWidget {
  const _Detail({required this.item});

  final Investment item;

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  bool _reconnecting = false;

  Investment get i => widget.item;

  Future<void> _reconnect() async {
    setState(() => _reconnecting = true);
    try {
      await ref.read(investmentsRepositoryProvider).reconnect(i.id);
      if (!mounted) return;
      showQToast(context, 'Reconectamos ${i.place}');
    } on Object {
      if (!mounted) return;
      showQToast(context, 'No pudimos reconectar. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  Future<void> _remove() async {
    final ok = await confirmDestructive(
      context,
      title: '¿Quitar ${i.name}?',
      message: i.isManual
          ? 'Se borra de Inti. Tu plata no se mueve.'
          : 'Se quita de Inti y revocamos el permiso. Tu inversión sigue '
                'en ${i.place}.',
      confirmLabel: 'Quitar ${i.name}',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(investmentsRepositoryProvider).remove(i.id);
      if (!mounted) return;
      showQToast(context, 'Quitamos ${i.name}');
      context.pop();
    } on Object {
      if (!mounted) return;
      showQToast(context, 'No pudimos quitarla. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = ref.watch(clockProvider)();
    final gainColor = i.gain > 0 ? c.income : c.ink;
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
          child: Text(i.name, style: context.text.headlineSmall),
        ),
        Text(
          i.institution == null
              ? i.kind.label
              : '${i.kind.label} · ${i.institution}',
          style: context.text.bodySmall,
        ),
        const SizedBox(height: AppSpace.lg),
        Semantics(
          label:
              'Hoy vale ${Cop.spoken(i.value)}. ${gainPhrase(i.gain)}, '
              '${signedPercent(i.returnRatio)}',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hoy vale', style: context.text.bodySmall),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: MoneyText(
                  i.value,
                  currency: true,
                  style: AppTypography.display.copyWith(color: c.ink),
                ),
              ),
              Text(
                '${gainPhrase(i.gain)} (${signedPercent(i.returnRatio)})',
                style: AppTypography.label.copyWith(color: gainColor),
              ),
            ],
          ),
        ),
        if (i.needsReconnect) ...[
          const SizedBox(height: AppSpace.lg),
          QBanner(
            title: 'Reconecta ${i.place}',
            message: 'Venció el permiso y el valor puede estar desactualizado.',
            actionLabel: _reconnecting ? 'Reconectando…' : 'Reconectar',
            onAction: _reconnecting ? null : _reconnect,
          ),
        ],
        const SizedBox(height: AppSpace.lg),
        QCard(
          child: Column(
            children: [
              DetailLine('Pusiste', Cop.format(i.invested)),
              DetailLine(
                'Ganancia o pérdida',
                Cop.format(i.gain, signed: true),
              ),
              DetailLine('Rentabilidad', signedPercent(i.returnRatio)),
              if (i.annualRate != null)
                DetailLine(
                  'Tasa',
                  '${Cop.percent(i.annualRate! * 100, decimals: 1)} e. a.',
                ),
              if (i.maturity != null)
                DetailLine(
                  'Vence',
                  '${Dates.dayMonth(i.maturity!)} · '
                      '${Dates.dueLabel(i.maturity!, now).toLowerCase()}',
                ),
              DetailLine('Desde', Dates.dayMonth(i.openedOn)),
              DetailLine('Estado', investmentSyncLabel(i, now)),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        if (i.isManual) ...[
          QButton(
            label: 'Actualizar valor',
            icon: Icons.edit_outlined,
            onPressed: () => context.push(Routes.updateInvestment(i.id)),
          ),
          const SizedBox(height: AppSpace.xs),
        ],
        QButton.secondary(
          label: 'Simular si sigues aportando',
          icon: Icons.trending_up_rounded,
          onPressed: () => context.push(
            Routes.simulatorFrom(initial: i.value, rate: i.annualRate),
          ),
        ),
        const SizedBox(height: AppSpace.xl),
        const TrustNote(
          'Inti solo muestra esta inversión: no la compra, la vende ni '
          'mueve tu plata.',
        ),
        const SizedBox(height: AppSpace.lg),
        QButton.text(
          label: 'Quitar inversión',
          icon: Icons.delete_outline_rounded,
          color: c.danger,
          onPressed: _remove,
        ),
      ],
    );
  }
}

/// Cambiar lo que vale hoy una inversión registrada a mano.
class UpdateInvestmentValuePage extends ConsumerStatefulWidget {
  const UpdateInvestmentValuePage({required this.id, super.key});

  final String id;

  @override
  ConsumerState<UpdateInvestmentValuePage> createState() =>
      _UpdateInvestmentValuePageState();
}

class _UpdateInvestmentValuePageState
    extends ConsumerState<UpdateInvestmentValuePage> {
  /// `null` hasta que el usuario escribe: mientras tanto se muestra el valor
  /// actual.
  String? _digits;
  bool _tried = false;
  bool _saving = false;

  Future<void> _save(Investment i, int amount) async {
    setState(() => _tried = true);
    if (amount <= 0) return;
    setState(() => _saving = true);
    try {
      await ref.read(investmentsRepositoryProvider).updateValue(i.id, amount);
      if (!mounted) return;
      showQToast(context, 'Actualizamos ${i.name}');
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos guardarlo. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final investments = ref.watch(investmentsProvider);
    final item = investments.value?.where((i) => i.id == widget.id).firstOrNull;
    final digits = _digits ?? (item == null ? '' : '${item.value}');
    final amount = AmountInput.value(digits);
    return DiscardGuard(
      dirty: !_saving && _digits != null && _digits != '${item?.value}',
      title: '¿Descartar este valor?',
      confirmLabel: 'Descartar valor',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Actualizar valor'),
        ),
        body: SafeArea(
          child: item == null
              ? _missingOrFailed(context, ref, investments, rows: 2)
              : KeypadLayout(
                  fields: [
                    AmountDisplay(
                      digits: digits,
                      label: '¿Cuánto vale hoy ${item.name}?',
                      error: _tried && amount <= 0
                          ? 'Escribe cuánto vale hoy.'
                          : null,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      'Pusiste ${Cop.format(item.invested)}.',
                      textAlign: TextAlign.center,
                      style: context.text.bodySmall,
                    ),
                    const SizedBox(height: AppSpace.sm),
                    const TrustNote(
                      'Solo cambia lo que ves en Inti: no mueve plata.',
                    ),
                  ],
                  keypad: AmountKeypad(
                    digits: digits,
                    onChanged: (d) => setState(() => _digits = d),
                  ),
                  action: QButton(
                    label: 'Guardar valor',
                    loading: _saving,
                    loadingLabel: 'Guardando',
                    onPressed: () => _save(item, amount),
                  ),
                ),
        ),
      ),
    );
  }
}
