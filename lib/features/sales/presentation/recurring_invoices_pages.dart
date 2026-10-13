import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/business/data/invoices_repository.dart';
import 'package:qullqi/features/sales/data/sales_repositories.dart';
import 'package:qullqi/features/sales/domain/sales.dart';

/// Facturas recurrentes: las que emites cada mes al mismo cliente.
class RecurringInvoicesPage extends ConsumerWidget {
  const RecurringInvoicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(invoiceTemplatesProvider);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('Facturas recurrentes')),
      body: switch (templates) {
        AsyncData(:final value) when value.isEmpty => MessageBody(
          child: EmptyState(
            icon: Icons.event_repeat_rounded,
            title: 'Cobra lo mismo cada mes',
            message:
                'Guarda una factura como plantilla y te recordamos emitirla '
                'el día que elijas, sin volver a escribirla.',
            actionLabel: 'Crear factura recurrente',
            onAction: () => context.push(Routes.newInvoiceTemplate),
          ),
        ),
        AsyncData(:final value) => _list(context, ref, value, now),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar tus facturas recurrentes',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(invoiceTemplatesProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando tus facturas recurrentes'),
      },
    );
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    List<InvoiceTemplate> all,
    DateTime now,
  ) {
    final monthly = all
        .where((t) => t.active)
        .fold<int>(0, (s, t) => s + t.total);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xxl,
      ),
      children: [
        HeroBalance(
          label: 'Facturas fijas cada mes',
          value: monthly,
          caption: '${all.where((t) => t.active).length} activas',
        ),
        const SizedBox(height: AppSpace.md),
        QButton.secondary(
          label: 'Crear factura recurrente',
          icon: Icons.add_rounded,
          onPressed: () => context.push(Routes.newInvoiceTemplate),
        ),
        const SizedBox(height: AppSpace.lg),
        const SectionHeader('Tus plantillas'),
        const SizedBox(height: AppSpace.xs),
        for (final t in all) ...[
          _TemplateTile(
            template: t,
            now: now,
            onTap: () => _actions(context, ref, t, now),
          ),
          const SizedBox(height: AppSpace.xs),
        ],
      ],
    );
  }

  Future<void> _actions(
    BuildContext context,
    WidgetRef ref,
    InvoiceTemplate t,
    DateTime now,
  ) {
    return showQSheet<void>(
      context,
      title: t.client,
      builder: (sheet) {
        Future<void> close(Future<void> Function() action, String done) async {
          Navigator.of(sheet).pop();
          try {
            await action();
            if (context.mounted) showQToast(context, done);
          } on Object {
            if (context.mounted) {
              showQToast(context, 'No pudimos guardarlo. Inténtalo de nuevo.');
            }
          }
        }

        final repo = ref.read(invoiceTemplatesRepositoryProvider);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${t.concept} · ${Cop.format(t.total)} el día ${t.dayOfMonth} '
              'de cada mes.',
              style: AppTypography.body.copyWith(
                color: context.colors.inkMuted,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            if (t.active && !t.issuedThisMonth(now)) ...[
              QButton(
                label: 'Emitir la de este mes ahora',
                icon: Icons.receipt_long_outlined,
                onPressed: () => close(() async {
                  final today = dateOnly(now);
                  await ref
                      .read(invoicesRepositoryProvider)
                      .create(
                        client: t.client,
                        base: t.base,
                        chargesIva: t.chargesIva,
                        due: today.add(Duration(days: t.termDays)),
                      );
                  await repo.markIssued(t.id);
                }, 'Emitimos la factura de ${t.client}'),
              ),
              const SizedBox(height: AppSpace.xs),
            ],
            QButton.secondary(
              label: t.active ? 'Pausar' : 'Reanudar',
              icon: t.active ? Icons.pause_rounded : Icons.play_arrow_rounded,
              onPressed: () => close(
                () => repo.setActive(t.id, active: !t.active),
                t.active ? 'Pausamos la plantilla' : 'Reanudamos la plantilla',
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            QButton.text(
              label: 'Eliminar plantilla',
              icon: Icons.delete_outline_rounded,
              color: context.colors.danger,
              onPressed: () async {
                Navigator.of(sheet).pop();
                final ok = await confirmDestructive(
                  context,
                  title: '¿Eliminar la plantilla de ${t.client}?',
                  message:
                      'Dejamos de recordarte emitirla. Las facturas que ya '
                      'emitiste se quedan.',
                  confirmLabel: 'Eliminar plantilla de ${t.client}',
                );
                if (!ok || !context.mounted) return;
                await repo.delete(t.id);
                if (context.mounted) {
                  showQToast(context, 'Eliminamos la plantilla');
                }
              },
            ),
          ],
        );
      },
    );
  }
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.now,
    required this.onTap,
  });

  final InvoiceTemplate template;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = template;
    final when = t.active
        ? 'Cada mes el ${t.dayOfMonth} · próxima: '
              '${Dates.dayMonth(t.nextIssue(now))}'
        : 'Cada mes el ${t.dayOfMonth}';
    return QCard(
      onTap: onTap,
      semanticLabel:
          '${t.client}. ${t.concept}. ${Cop.spoken(t.total)}. $when'
          '${t.active ? '' : '. Pausada'}',
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: ExcludeSemantics(
        child: AmountRowLayout(
          leading: const IconTile(icon: Icons.event_repeat_rounded),
          title: t.client,
          titleLines: 2,
          details: [
            Text(t.concept, style: context.text.bodySmall),
            Text(
              when,
              style: AppTypography.caption.copyWith(color: c.inkSubtle),
            ),
            if (!t.active) ...[
              const SizedBox(height: AppSpace.xxs),
              const StatusPill('Pausada', tone: PillTone.warning),
            ] else if (t.issuedThisMonth(now)) ...[
              const SizedBox(height: AppSpace.xxs),
              const StatusPill('Ya emitida este mes', tone: PillTone.primary),
            ],
          ],
          trailing: MoneyText(
            t.total,
            animate: false,
            style: AppTypography.body.copyWith(
              color: c.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// Días del mes sugeridos para emitir.
const _days = [1, 5, 10, 15, 20, 25];

/// Plazos de pago sugeridos (días).
const _terms = [15, 30, 60];

/// Crear una plantilla de factura mensual.
class NewInvoiceTemplatePage extends ConsumerStatefulWidget {
  const NewInvoiceTemplatePage({super.key});

  @override
  ConsumerState<NewInvoiceTemplatePage> createState() =>
      _NewInvoiceTemplatePageState();
}

class _NewInvoiceTemplatePageState
    extends ConsumerState<NewInvoiceTemplatePage> {
  final _client = TextEditingController();
  final _concept = TextEditingController();
  final _base = TextEditingController();
  bool _iva = true;
  int _day = 5;
  int _term = 15;
  bool _tried = false;
  bool _saving = false;

  int get _amount => AmountInput.value(_base.text);

  @override
  void dispose() {
    _client.dispose();
    _concept.dispose();
    _base.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _tried = true);
    if (_client.text.trim().length < 2 ||
        _concept.text.trim().length < 2 ||
        _amount <= 0) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(invoiceTemplatesRepositoryProvider)
          .create(
            client: _client.text,
            concept: _concept.text,
            base: _amount,
            chargesIva: _iva,
            dayOfMonth: _day,
            termDays: _term,
          );
      if (!mounted) return;
      showQToast(context, 'Creamos la factura recurrente');
      context.pop();
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos crearla. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DiscardGuard(
      dirty:
          !_saving &&
          (_client.text.isNotEmpty ||
              _concept.text.isNotEmpty ||
              _base.text.isNotEmpty),
      title: '¿Descartar esta factura recurrente?',
      confirmLabel: 'Descartar plantilla',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Factura recurrente'),
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
                  errorText: _tried && _client.text.trim().length < 2
                      ? 'Escribe el nombre del cliente.'
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
                  labelText: 'Qué le cobras',
                  hintText: 'Ej. Mantenimiento web mensual',
                  errorText: _tried && _concept.text.trim().length < 2
                      ? 'Describe qué le cobras.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _base,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(AmountInput.maxDigits),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Valor mensual (antes de IVA)',
                  prefixText: r'$ ',
                  helperText: _amount == 0 ? null : Cop.format(_amount),
                  errorText: _tried && _amount <= 0
                      ? 'Escribe cuánto cobras.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('¿Qué día del mes la emites?'),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  for (final d in _days)
                    ChoiceChip(
                      label: Text('Día $d'),
                      selected: _day == d,
                      onSelected: (_) => setState(() => _day = d),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('¿En cuántos días te pagan?'),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  for (final d in _terms)
                    ChoiceChip(
                      label: Text('$d días'),
                      selected: _term == d,
                      onSelected: (_) => setState(() => _term = d),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              SwitchRow(
                title: 'Cobra IVA',
                subtitle: '19 % sobre el valor.',
                value: _iva,
                onChanged: (v) => setState(() => _iva = v),
              ),
              const SizedBox(height: AppSpace.xl),
              QButton(
                label: 'Crear factura recurrente',
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
