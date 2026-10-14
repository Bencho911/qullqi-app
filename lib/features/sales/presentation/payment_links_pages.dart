import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:inti/features/business/data/invoices_repository.dart';
import 'package:inti/features/sales/data/sales_repositories.dart';
import 'package:inti/features/sales/domain/sales.dart';

/// Etiqueta de estado de un enlace de pago.
StatusPill linkPill(PaymentLink l, DateTime now) {
  final s = l.statusAt(now);
  return switch (s) {
    PaymentLinkStatus.active => StatusPill(
      Dates.dueLabel(l.expiresAt, now).replaceFirst('Vence', 'Activo,'),
    ),
    PaymentLinkStatus.paid => StatusPill(s.label, tone: PillTone.primary),
    PaymentLinkStatus.expired => StatusPill(s.label, tone: PillTone.warning),
    PaymentLinkStatus.cancelled => StatusPill(s.label),
  };
}

/// Copia el enlace y avisa.
Future<void> copyLink(BuildContext context, PaymentLink l) async {
  await Clipboard.setData(ClipboardData(text: l.url));
  if (context.mounted) showQToast(context, 'Copiamos el enlace');
}

/// Muestra el enlace con sus acciones.
Future<void> showLinkSheet(
  BuildContext context,
  WidgetRef ref,
  PaymentLink l,
  DateTime now,
) {
  return showQSheet<void>(
    context,
    title: l.concept,
    builder: (sheet) {
      final c = sheet.colors;
      final status = l.statusAt(now);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${Cop.format(l.amount)}'
            '${l.client == null ? '' : ' · ${l.client}'}',
            style: AppTypography.body.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: AppSpace.sm),
          QCard(
            child: SelectableText(
              l.url,
              style: AppTypography.body.copyWith(color: c.ink),
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Align(alignment: Alignment.centerLeft, child: linkPill(l, now)),
          const SizedBox(height: AppSpace.lg),
          QButton(
            label: 'Copiar enlace',
            icon: Icons.copy_rounded,
            onPressed: () async {
              Navigator.of(sheet).pop();
              await copyLink(context, l);
            },
          ),
          if (status == PaymentLinkStatus.active) ...[
            const SizedBox(height: AppSpace.xs),
            QButton.text(
              label: 'Cancelar enlace',
              icon: Icons.link_off_rounded,
              color: c.danger,
              onPressed: () async {
                Navigator.of(sheet).pop();
                final ok = await confirmDestructive(
                  context,
                  title: '¿Cancelar este enlace?',
                  message:
                      'Quien lo abra ya no podrá pagar. Si ya pagó, el pago '
                      'queda registrado.',
                  confirmLabel: 'Cancelar enlace de ${l.concept}',
                );
                if (!ok || !context.mounted) return;
                await ref.read(paymentLinksRepositoryProvider).cancel(l.id);
                if (context.mounted) {
                  showQToast(context, 'Cancelamos el enlace');
                }
              },
            ),
          ],
        ],
      );
    },
  );
}

/// Enlaces de pago: lo que le mandas al cliente para que te pague.
class PaymentLinksPage extends ConsumerWidget {
  const PaymentLinksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final links = ref.watch(paymentLinksProvider);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('Enlaces de pago')),
      body: switch (links) {
        AsyncData(:final value) when value.isEmpty => MessageBody(
          child: EmptyState(
            icon: Icons.add_link_rounded,
            title: 'Cobra con un enlace',
            message:
                'Crea un enlace por el valor que quieras y mándalo por '
                'WhatsApp. Tu cliente paga desde su celular.',
            actionLabel: 'Crear enlace de pago',
            onAction: () => context.push(Routes.newPaymentLink),
          ),
        ),
        AsyncData(:final value) => _list(context, ref, value, now),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar tus enlaces',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(paymentLinksProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando tus enlaces de pago'),
      },
    );
  }

  Widget _list(
    BuildContext context,
    WidgetRef ref,
    List<PaymentLink> all,
    DateTime now,
  ) {
    final open = all.where((l) => l.statusAt(now) == PaymentLinkStatus.active);
    final openTotal = open.fold<int>(0, (s, l) => s + l.amount);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xxl,
      ),
      children: [
        HeroBalance(
          label: 'Esperando que te paguen',
          value: openTotal,
          caption: open.length == 1
              ? '1 enlace activo'
              : '${open.length} enlaces activos',
        ),
        const SizedBox(height: AppSpace.md),
        QButton.secondary(
          label: 'Crear enlace de pago',
          icon: Icons.add_rounded,
          onPressed: () => context.push(Routes.newPaymentLink),
        ),
        const SizedBox(height: AppSpace.lg),
        const SectionHeader('Tus enlaces'),
        const SizedBox(height: AppSpace.xs),
        for (final l in all) ...[
          QCard(
            onTap: () => showLinkSheet(context, ref, l, now),
            semanticLabel:
                '${l.concept}. ${Cop.spoken(l.amount)}. '
                '${linkPill(l, now).label}',
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: ExcludeSemantics(
              child: AmountRowLayout(
                leading: const IconTile(icon: Icons.link_rounded),
                title: l.concept,
                titleLines: 2,
                details: [
                  if (l.client != null)
                    Text(l.client!, style: context.text.bodySmall),
                  const SizedBox(height: AppSpace.xxs),
                  linkPill(l, now),
                ],
                trailing: MoneyText(
                  l.amount,
                  animate: false,
                  style: AppTypography.body.copyWith(
                    color: context.colors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xs),
        ],
        const SizedBox(height: AppSpace.md),
        const TrustNote(
          'El cliente paga en la página de nuestro aliado de pagos. Inti '
          'no ve ni guarda los datos de su tarjeta.',
        ),
      ],
    );
  }
}

/// Vigencias sugeridas (días).
const _validity = [3, 7, 15, 30];

/// Crear un enlace de pago, opcionalmente de una factura.
class NewPaymentLinkPage extends ConsumerStatefulWidget {
  const NewPaymentLinkPage({super.key, this.invoiceId});

  /// Factura que se cobra con el enlace (parte con su valor y su cliente).
  final String? invoiceId;

  @override
  ConsumerState<NewPaymentLinkPage> createState() => _NewPaymentLinkPageState();
}

class _NewPaymentLinkPageState extends ConsumerState<NewPaymentLinkPage> {
  final _concept = TextEditingController();
  final _amount = TextEditingController();
  int _days = 7;
  bool _seeded = false;
  bool _tried = false;
  bool _saving = false;

  int get _value => AmountInput.value(_amount.text);

  @override
  void dispose() {
    _concept.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save(String? client) async {
    setState(() => _tried = true);
    if (_concept.text.trim().length < 2 || _value <= 0) return;
    setState(() => _saving = true);
    try {
      final link = await ref
          .read(paymentLinksRepositoryProvider)
          .create(
            concept: _concept.text,
            amount: _value,
            validDays: _days,
            client: client,
            invoiceId: widget.invoiceId,
          );
      // Copiar no debe frenar la creación: se hace sin esperar.
      unawaited(Clipboard.setData(ClipboardData(text: link.url)));
      if (!mounted) return;
      showQToast(context, 'Creamos el enlace y lo copiamos');
      context.pop();
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos crearlo. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoiceId == null
        ? null
        : ref
              .watch(invoicesProvider)
              .value
              ?.where((i) => i.id == widget.invoiceId)
              .firstOrNull;
    if (invoice != null && !_seeded) {
      _seeded = true;
      _concept.text = 'Factura ${invoice.number}';
      _amount.text = '${invoice.total}';
    }
    return DiscardGuard(
      dirty: !_saving && (_concept.text.isNotEmpty || _amount.text.isNotEmpty),
      title: '¿Descartar este enlace?',
      confirmLabel: 'Descartar enlace',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Crear enlace de pago'),
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
              if (invoice != null) ...[
                Text(
                  'Para la factura ${invoice.number} de ${invoice.client}',
                  style: context.text.bodyMedium?.copyWith(
                    color: context.colors.inkMuted,
                  ),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              TextField(
                controller: _concept,
                autofocus: invoice == null,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: '¿Qué está pagando?',
                  hintText: 'Ej. Anticipo del sitio web',
                  errorText: _tried && _concept.text.trim().length < 2
                      ? 'Escribe qué está pagando tu cliente.'
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
                  labelText: 'Valor a cobrar',
                  prefixText: r'$ ',
                  helperText: _value == 0 ? null : Cop.format(_value),
                  errorText: _tried && _value <= 0
                      ? 'Escribe cuánto cobras.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('¿Cuánto tiempo estará activo?'),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  for (final d in _validity)
                    ChoiceChip(
                      label: Text('$d días'),
                      selected: _days == d,
                      onSelected: (_) => setState(() => _days = d),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              const TrustNote(
                'Al crearlo copiamos el enlace para que lo pegues en '
                'WhatsApp o en un correo.',
              ),
              const SizedBox(height: AppSpace.xl),
              QButton(
                label: 'Crear enlace',
                loading: _saving,
                loadingLabel: 'Creando',
                onPressed: () => _save(invoice?.client),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
