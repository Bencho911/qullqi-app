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

/// Días que tiene el cliente para pagar la factura que sale de una
/// cotización.
const int _invoiceTermDays = 15;

/// Etiqueta de estado de una cotización.
StatusPill quotePill(Quote q, DateTime now) => switch (q.statusAt(now)) {
  QuoteStatus.draft => const StatusPill('Borrador'),
  QuoteStatus.sent => StatusPill(
    Dates.dueLabel(q.validUntil, now).replaceFirst('Vence', 'Válida'),
  ),
  QuoteStatus.accepted => const StatusPill('Aceptada', tone: PillTone.primary),
  QuoteStatus.rejected => const StatusPill('Rechazada'),
  QuoteStatus.expired => const StatusPill('Vencida', tone: PillTone.warning),
};

/// Cotizaciones: lo que propusiste y cómo va cada una.
class QuotesPage extends ConsumerWidget {
  const QuotesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotes = ref.watch(quotesProvider);
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('Cotizaciones')),
      body: switch (quotes) {
        AsyncData(:final value) when value.isEmpty => MessageBody(
          child: EmptyState(
            icon: Icons.request_quote_outlined,
            title: 'Propón un precio',
            message:
                'Arma una cotización con sus renglones. Si el cliente acepta, '
                'la conviertes en factura con un toque.',
            actionLabel: 'Crear cotización',
            onAction: () => context.push(Routes.newQuote),
          ),
        ),
        AsyncData(:final value) => _list(context, value, now),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar tus cotizaciones',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(quotesProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando tus cotizaciones'),
      },
    );
  }

  Widget _list(BuildContext context, List<Quote> all, DateTime now) {
    List<Quote> of(Set<QuoteStatus> s) =>
        all.where((q) => s.contains(q.statusAt(now))).toList();
    final waiting = of({QuoteStatus.sent});
    final groups = [
      ('Por responder', waiting),
      ('Borradores', of({QuoteStatus.draft})),
      (
        'Cerradas',
        of({QuoteStatus.accepted, QuoteStatus.rejected, QuoteStatus.expired}),
      ),
    ].where((g) => g.$2.isNotEmpty);
    final waitingTotal = waiting.fold<int>(0, (s, q) => s + q.total);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xxl,
      ),
      children: [
        HeroBalance(
          label: 'Esperando respuesta',
          value: waitingTotal,
          caption: waiting.length == 1
              ? '1 cotización enviada'
              : '${waiting.length} cotizaciones enviadas',
        ),
        const SizedBox(height: AppSpace.md),
        QButton.secondary(
          label: 'Crear cotización',
          icon: Icons.add_rounded,
          onPressed: () => context.push(Routes.newQuote),
        ),
        for (final (title, items) in groups) ...[
          const SizedBox(height: AppSpace.lg),
          SectionHeader(title),
          const SizedBox(height: AppSpace.xs),
          for (final q in items) ...[
            _QuoteTile(quote: q, now: now),
            const SizedBox(height: AppSpace.xs),
          ],
        ],
      ],
    );
  }
}

class _QuoteTile extends StatelessWidget {
  const _QuoteTile({required this.quote, required this.now});

  final Quote quote;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final q = quote;
    final pill = quotePill(q, now);
    return QCard(
      onTap: () => context.push(Routes.quote(q.id)),
      semanticLabel:
          '${q.client}. ${q.number}. ${Cop.spoken(q.total)}. ${pill.label}',
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
      child: ExcludeSemantics(
        child: AmountRowLayout(
          leading: const IconTile(icon: Icons.request_quote_outlined),
          title: q.client,
          titleLines: 2,
          details: [
            Text(q.number, style: context.text.bodySmall),
            const SizedBox(height: AppSpace.xxs),
            pill,
          ],
          trailing: MoneyText(
            q.total,
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

/// Detalle de una cotización y lo que se puede hacer con ella.
class QuoteDetailPage extends ConsumerWidget {
  const QuoteDetailPage({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quotes = ref.watch(quotesProvider);
    final q = quotes.value?.where((x) => x.id == id).firstOrNull;
    return Scaffold(
      appBar: AppBar(title: const Text('Cotización')),
      body: switch (quotes) {
        AsyncValue(hasValue: true) when q != null => _QuoteDetail(q: q),
        AsyncValue(hasValue: true) => MessageBody(
          child: EmptyState(
            icon: Icons.search_off_rounded,
            title: 'Esta cotización ya no existe',
            message: 'Puede que la hayas eliminado.',
            actionLabel: 'Ver cotizaciones',
            onAction: () => context.pushReplacement(Routes.quotes),
          ),
        ),
        AsyncError() => MessageBody(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'No pudimos cargar la cotización',
            message: 'Revisa tu conexión a internet e inténtalo de nuevo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(quotesProvider),
          ),
        ),
        _ => const PageSkeleton(label: 'Cargando la cotización'),
      },
    );
  }
}

class _QuoteDetail extends ConsumerWidget {
  const _QuoteDetail({required this.q});

  final Quote q;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final now = ref.watch(clockProvider)();
    final status = q.statusAt(now);
    final repo = ref.read(quotesRepositoryProvider);

    Future<void> run(Future<void> Function() action, String done) async {
      try {
        await action();
        if (context.mounted) showQToast(context, done);
      } on Object {
        if (context.mounted) {
          showQToast(context, 'No pudimos guardarlo. Inténtalo de nuevo.');
        }
      }
    }

    Future<void> accept() => run(() async {
      // La cotización aceptada pasa a ser una factura por cobrar.
      final today = dateOnly(now);
      final invoice = await ref
          .read(invoicesRepositoryProvider)
          .create(
            client: q.client,
            base: q.base,
            chargesIva: q.chargesIva,
            due: today.add(const Duration(days: _invoiceTermDays)),
          );
      await repo.linkInvoice(q.id, invoice.id);
    }, 'Creamos la factura de ${q.number}');

    Future<void> delete() async {
      final ok = await confirmDestructive(
        context,
        title: '¿Eliminar la cotización ${q.number}?',
        message:
            'Se borra de tu lista. Las facturas que salieron de ella se '
            'quedan.',
        confirmLabel: 'Eliminar ${q.number}',
      );
      if (!ok || !context.mounted) return;
      await run(() => repo.delete(q.id), 'Eliminamos ${q.number}');
      if (context.mounted) context.pop();
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
          child: Text(q.client, style: context.text.headlineSmall),
        ),
        Text(q.number, style: context.text.bodySmall),
        const SizedBox(height: AppSpace.md),
        Align(alignment: Alignment.centerLeft, child: quotePill(q, now)),
        const SizedBox(height: AppSpace.md),
        Semantics(
          label: 'Total: ${Cop.spoken(q.total)}',
          excludeSemantics: true,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: MoneyText(
              q.total,
              currency: true,
              style: AppTypography.display.copyWith(color: c.ink),
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        QCard(
          child: Column(
            children: [
              for (final l in q.lines)
                DetailLine(l.description, Cop.format(l.amount)),
              const Divider(),
              DetailLine('Subtotal', Cop.format(q.base)),
              DetailLine(
                'IVA',
                q.chargesIva ? Cop.format(q.iva) : 'No cobra IVA',
              ),
              DetailLine('Emitida', Dates.dayMonth(q.issued)),
              DetailLine('Válida hasta', Dates.dayMonth(q.validUntil)),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        if (status == QuoteStatus.draft) ...[
          QButton(
            label: 'Marcar como enviada',
            icon: Icons.send_outlined,
            onPressed: () => run(
              () => repo.setStatus(q.id, QuoteStatus.sent),
              '${q.number} quedó como enviada',
            ),
          ),
        ],
        if (status == QuoteStatus.sent || status == QuoteStatus.expired) ...[
          QButton(
            label: 'El cliente la aceptó',
            icon: Icons.check_rounded,
            onPressed: accept,
          ),
          const SizedBox(height: AppSpace.xs),
          QButton.secondary(
            label: 'El cliente la rechazó',
            onPressed: () => run(
              () => repo.setStatus(q.id, QuoteStatus.rejected),
              '${q.number} quedó como rechazada',
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          QButton.text(
            label: 'Copiar para enviar',
            icon: Icons.copy_rounded,
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text:
                      'Cotización ${q.number} para ${q.client}: '
                      '${Cop.format(q.total)} (válida hasta el '
                      '${Dates.dayMonth(q.validUntil)}).',
                ),
              );
              if (context.mounted) {
                showQToast(context, 'Copiamos el resumen para que lo envíes');
              }
            },
          ),
        ],
        if (status == QuoteStatus.accepted && q.invoiceId != null)
          QButton(
            label: 'Ver la factura',
            icon: Icons.receipt_long_outlined,
            onPressed: () => context.push(Routes.invoice(q.invoiceId!)),
          ),
        const SizedBox(height: AppSpace.xl),
        QButton.text(
          label: 'Eliminar cotización',
          icon: Icons.delete_outline_rounded,
          color: c.danger,
          onPressed: delete,
        ),
      ],
    );
  }
}

/// Vigencias sugeridas (días).
const _validity = [7, 15, 30];

class _LineDraft {
  final description = TextEditingController();
  final amount = TextEditingController();

  void dispose() {
    description.dispose();
    amount.dispose();
  }
}

/// Crear una cotización: cliente, renglones, IVA y vigencia.
class NewQuotePage extends ConsumerStatefulWidget {
  const NewQuotePage({super.key});

  @override
  ConsumerState<NewQuotePage> createState() => _NewQuotePageState();
}

class _NewQuotePageState extends ConsumerState<NewQuotePage> {
  final _client = TextEditingController();
  final _lines = [_LineDraft()];
  bool _iva = true;
  bool _sent = false;
  int _days = 15;
  bool _tried = false;
  bool _saving = false;

  static const _maxLines = 8;

  @override
  void dispose() {
    _client.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  int _amountOf(_LineDraft l) => AmountInput.value(l.amount.text);

  List<QuoteLine> get _valid => [
    for (final l in _lines)
      if (l.description.text.trim().isNotEmpty && _amountOf(l) > 0)
        QuoteLine(description: l.description.text.trim(), amount: _amountOf(l)),
  ];

  bool get _dirty =>
      _client.text.isNotEmpty ||
      _lines.any(
        (l) => l.description.text.isNotEmpty || l.amount.text.isNotEmpty,
      );

  Future<void> _save() async {
    setState(() => _tried = true);
    if (_client.text.trim().length < 2 || _valid.isEmpty) return;
    setState(() => _saving = true);
    try {
      final q = await ref
          .read(quotesRepositoryProvider)
          .create(
            client: _client.text,
            lines: _valid,
            chargesIva: _iva,
            validDays: _days,
            send: _sent,
          );
      if (!mounted) return;
      showQToast(context, 'Creamos la cotización ${q.number}');
      context.pushReplacement(Routes.quote(q.id));
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos crearla. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final base = _valid.fold<int>(0, (s, l) => s + l.amount);
    final iva = _iva ? (base * 0.19).round() : 0;
    final digitsOnly = [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(AmountInput.maxDigits),
    ];
    return DiscardGuard(
      dirty: !_saving && _dirty,
      title: '¿Descartar esta cotización?',
      confirmLabel: 'Descartar cotización',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Crear cotización'),
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
                      ? 'Escribe el nombre del cliente.'
                      : null,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('Qué le cotizas'),
              const SizedBox(height: AppSpace.xs),
              for (final (i, l) in _lines.indexed) ...[
                TextField(
                  controller: l.description,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Renglón ${i + 1}',
                    hintText: 'Ej. Diseño de marca',
                    suffixIcon: _lines.length > 1
                        ? IconButton(
                            tooltip: 'Quitar renglón ${i + 1}',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() {
                              _lines.removeAt(i).dispose();
                            }),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                TextField(
                  controller: l.amount,
                  keyboardType: TextInputType.number,
                  inputFormatters: digitsOnly,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Valor del renglón ${i + 1}',
                    prefixText: r'$ ',
                    helperText: _amountOf(l) == 0
                        ? null
                        : Cop.format(_amountOf(l)),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
              ],
              if (_tried && _valid.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.xs),
                  child: Text(
                    'Agrega al menos un renglón con descripción y valor.',
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onDangerContainer,
                    ),
                  ),
                ),
              if (_lines.length < _maxLines)
                QButton.secondary(
                  label: 'Agregar renglón',
                  icon: Icons.add_rounded,
                  onPressed: () => setState(() => _lines.add(_LineDraft())),
                ),
              const SizedBox(height: AppSpace.lg),
              const SectionHeader('¿Hasta cuándo es válida?'),
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
              SwitchRow(
                title: 'Cobra IVA',
                subtitle: '19 % sobre el valor.',
                value: _iva,
                onChanged: (v) => setState(() => _iva = v),
              ),
              SwitchRow(
                title: 'Ya se la envié al cliente',
                subtitle: 'Si no, queda como borrador.',
                value: _sent,
                onChanged: (v) => setState(() => _sent = v),
              ),
              if (base > 0) ...[
                const SizedBox(height: AppSpace.md),
                QCard(
                  child: Column(
                    children: [
                      DetailLine('Subtotal', Cop.format(base)),
                      DetailLine('IVA', Cop.format(iva)),
                      DetailLine(
                        'Total',
                        Cop.format(base + iva),
                        emphasis: true,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.xl),
              QButton(
                label: 'Crear cotización',
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
