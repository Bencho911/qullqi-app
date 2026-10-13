import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/scope/scope_provider.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/business/data/invoices_repository.dart';
import 'package:qullqi/features/business/domain/business.dart';
import 'package:qullqi/features/taxes/data/tax_document_provider.dart';
import 'package:qullqi/features/taxes/domain/tax_calendar.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';

/// Días antes de la fecha en que se marca como cercana.
const int _soonDays = 7;

IconData _iconOf(ObligationKind k) => switch (k) {
  ObligationKind.renta => Icons.description_outlined,
  ObligationKind.retencion => Icons.receipt_long_outlined,
  ObligationKind.pila => Icons.health_and_safety_outlined,
  ObligationKind.prima => Icons.card_giftcard_outlined,
  ObligationKind.cesantias => Icons.savings_outlined,
  ObligationKind.intereses => Icons.percent_rounded,
};

/// Impuestos y obligaciones: tus fechas, el 4x1000 y el resumen para la renta.
class TaxesPage extends ConsumerStatefulWidget {
  const TaxesPage({super.key});

  @override
  ConsumerState<TaxesPage> createState() => _TaxesPageState();
}

class _TaxesPageState extends ConsumerState<TaxesPage> {
  final _number = TextEditingController();
  TaxDocumentType _type = TaxDocumentType.cedula;
  bool _tried = false;

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _tried = true);
    final doc = TaxDocument(type: _type, number: _number.text);
    if (!doc.isValid) return;
    await ref.read(taxDocumentProvider.notifier).save(doc);
  }

  @override
  Widget build(BuildContext context) {
    final doc = ref.watch(taxDocumentProvider);
    final hasBusiness = ref.watch(currentUserProvider).hasBusiness;
    final now = ref.watch(clockProvider)();
    final scope = ref.watch(scopeProvider);
    final txs = ref.watch(transactionsProvider).value ?? const [];
    final accounts = ref.watch(accountsProvider).value ?? const [];
    final invoices = ref.watch(invoicesProvider).value;
    final iva = invoices == null || !hasBusiness
        ? null
        : BusinessMonth.of(invoices, txs, now).iva;
    final obligations = doc == null
        ? const <Obligation>[]
        : buildTaxCalendar(document: doc, now: now, hasBusiness: hasBusiness);
    final gmf = GmfEstimate.of(
      txs,
      debitAccountIds: {
        for (final a in accounts)
          if (!a.isCard) a.id,
      },
      scope: scope,
      now: now,
    );
    final year = YearSummary.of(txs, scope: scope, now: now);

    return Scaffold(
      appBar: AppBar(title: const Text('Impuestos y obligaciones')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.xs,
            AppSpace.gutter,
            AppSpace.xxl,
          ),
          children: [
            const QBanner(
              tone: BannerTone.info,
              title: 'Fechas de referencia',
              message:
                  'La DIAN publica las fechas exactas cada año. Confírmalas en '
                  'dian.gov.co antes de actuar.',
            ),
            const SizedBox(height: AppSpace.lg),
            if (doc == null) _documentForm(context) else _documentRow(doc),
            const SizedBox(height: AppSpace.xl),
            const SectionHeader('Lo que viene'),
            const SizedBox(height: AppSpace.xs),
            if (doc == null)
              const SectionNote('Agrega tu documento para ver tus fechas.')
            else
              QCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: Column(
                  children: [
                    if (iva != null) ...[
                      SettingsRow(
                        leading: const IconTile(
                          icon: Icons.account_balance_outlined,
                        ),
                        title: 'IVA de ${iva.label}',
                        subtitle:
                            '${Dates.dueLabel(iva.due, now)} · '
                            '${Dates.dayMonth(iva.due)} · estimado '
                            '${Cop.format(iva.toPay)}',
                        onTap: () => context.push(Routes.iva),
                      ),
                      const Divider(),
                    ],
                    for (final (i, o) in obligations.indexed) ...[
                      if (i > 0) const Divider(),
                      _ObligationRow(obligation: o, now: now),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: AppSpace.xl),
            const SectionHeader('4x1000 de este mes'),
            const SizedBox(height: AppSpace.xs),
            QCard(
              child: Column(
                children: [
                  DetailLine('Salió de tus cuentas', Cop.format(gmf.base)),
                  DetailLine(
                    'Pagaste de 4x1000, aprox.',
                    Cop.format(gmf.estimated),
                    emphasis: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Si marcaste una cuenta como exenta en tu banco, pagas menos: '
              'la exención cubre hasta 350 UVT al mes.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: AppSpace.xl),
            SectionHeader('Resumen para tu renta de ${year.year}'),
            const SizedBox(height: AppSpace.xs),
            QCard(
              child: Column(
                children: [
                  DetailLine('Ingresos del año', Cop.format(year.income)),
                  for (final (cat, amount) in year.incomeByCategory.take(3))
                    DetailLine('· ${cat.name}', Cop.format(amount)),
                  DetailLine('Gastos en salud', Cop.format(year.health)),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Es un apoyo con lo que ves en Qullqi. Para declarar usa tus '
              'certificados de ingresos y retenciones.',
              style: context.text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _documentForm(BuildContext context) {
    final invalid = _tried && _number.text.length < 5;
    return QCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Para armar tu calendario necesitamos tu documento: los últimos '
            'dígitos deciden tus fechas.',
            style: context.text.bodyMedium,
          ),
          const SizedBox(height: AppSpace.md),
          SegmentedButton<TaxDocumentType>(
            showSelectedIcon: false,
            segments: [
              for (final t in TaxDocumentType.values)
                ButtonSegment(value: t, label: Text(t.label)),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _number,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(12),
            ],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Número de ${_type.label.toLowerCase()}',
              helperText: _type == TaxDocumentType.nit
                  ? 'Sin dígito de verificación ni puntos.'
                  : 'Sin puntos ni espacios.',
              errorText: invalid ? 'Escribe al menos 5 dígitos.' : null,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          QButton(label: 'Guardar documento', onPressed: _save),
        ],
      ),
    );
  }

  Widget _documentRow(TaxDocument doc) {
    return QCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: SettingsRow(
        icon: Icons.badge_outlined,
        title: doc.masked,
        subtitle: 'Tu calendario sale de este documento',
        trailing: QButton.text(
          label: 'Cambiar',
          onPressed: () async {
            await ref.read(taxDocumentProvider.notifier).clear();
            if (mounted) setState(_number.clear);
          },
        ),
      ),
    );
  }
}

class _ObligationRow extends StatelessWidget {
  const _ObligationRow({required this.obligation, required this.now});

  final Obligation obligation;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final o = obligation;
    final days = daysBetween(now, o.due);
    final detail =
        '${o.detail} · ${Dates.dayMonth(o.due)}'
        '${o.ifEmployer ? ' · si tienes empleados' : ''}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(icon: _iconOf(o.kind)),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    o.title,
                    style: AppTypography.body.copyWith(
                      color: c.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(detail, style: context.text.bodySmall),
                  const SizedBox(height: AppSpace.xxs),
                  StatusPill(
                    Dates.dueLabel(o.due, now),
                    tone: days <= _soonDays
                        ? PillTone.warning
                        : PillTone.neutral,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
