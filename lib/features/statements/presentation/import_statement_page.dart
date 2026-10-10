import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:qullqi/app/routes.dart';
import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/domain/account.dart';
import 'package:qullqi/features/accounts/presentation/widgets/account_picker.dart';
import 'package:qullqi/features/statements/data/statement_repository.dart';
import 'package:qullqi/features/statements/domain/statement.dart';
import 'package:qullqi/features/transactions/data/transactions_repository.dart';
import 'package:qullqi/features/transactions/domain/transaction_filter.dart';
import 'package:qullqi/features/transactions/presentation/transactions_controller.dart';

enum _Stage { choose, reading, review, done }

/// Importar un extracto (PDF, Excel o CSV) a una cuenta: para las cuentas
/// sin conexión o para traer meses anteriores.
class ImportStatementPage extends ConsumerStatefulWidget {
  const ImportStatementPage({super.key, this.accountId});

  /// Cuenta ya elegida (al abrir desde su detalle).
  final String? accountId;

  @override
  ConsumerState<ImportStatementPage> createState() =>
      _ImportStatementPageState();
}

class _ImportStatementPageState extends ConsumerState<ImportStatementPage> {
  _Stage _stage = _Stage.choose;
  late String? _accountId = widget.accountId;
  bool _tried = false;
  StatementProblem? _problem;
  String _fileName = '';
  List<ImportCandidate> _candidates = const [];
  Set<int> _selected = {};
  bool _saving = false;
  int _imported = 0;
  int _toReview = 0;

  Future<void> _pickAndRead(List<Account> accounts) async {
    setState(() {
      _tried = true;
      _problem = null;
    });
    final account = accounts.where((a) => a.id == _accountId).firstOrNull;
    if (account == null) return;
    final StatementFile? file;
    try {
      file = await ref.read(statementPickerProvider).pick();
    } on Object {
      setState(() => _problem = StatementProblem.failed);
      return;
    }
    if (file == null || !mounted) return;
    setState(() {
      _stage = _Stage.reading;
      _fileName = file!.name;
    });
    try {
      final lines = await ref.read(statementReaderProvider).read(file);
      final existing = ref.read(transactionsProvider).value ?? const [];
      final candidates = matchStatement(lines, existing, account.id);
      if (!mounted) return;
      setState(() {
        _candidates = candidates;
        _selected = {
          for (final (i, c) in candidates.indexed)
            if (!c.duplicate) i,
        };
        _stage = _Stage.review;
      });
    } on StatementException catch (e) {
      if (!mounted) return;
      setState(() {
        _problem = e.problem;
        _stage = _Stage.choose;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _problem = StatementProblem.failed;
        _stage = _Stage.choose;
      });
    }
  }

  Future<void> _import(Account account) async {
    final lines = [for (final i in _selected) _candidates[i].line];
    setState(() => _saving = true);
    try {
      final count = await ref
          .read(statementImporterProvider)
          .import(account, lines);
      if (!mounted) return;
      setState(() {
        _imported = count;
        _toReview = lines.where(looksLikeTransfer).length;
        _stage = _Stage.done;
        _saving = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos importar. Inténtalo de nuevo.');
    }
  }

  void _seeMovements(Account account) {
    ref
        .read(transactionFilterProvider.notifier)
        .set(TransactionFilter(range: DateRange.all, accountIds: {account.id}));
    context.go(Routes.transactions);
  }

  @override
  Widget build(BuildContext context) {
    return DiscardGuard(
      dirty: _stage == _Stage.review && !_saving,
      title: '¿Descartar la importación?',
      confirmLabel: 'Descartar importación',
      message: 'No traemos ningún movimiento de este extracto.',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Importar extracto'),
        ),
        body: AccountsGate(
          builder: (accounts) {
            final account = accounts
                .where((a) => a.id == _accountId)
                .firstOrNull;
            return switch (_stage) {
              _Stage.choose => _choose(accounts, account),
              _Stage.reading => BusyMessage(
                title: 'Leyendo tu extracto',
                message: _fileName,
              ),
              _Stage.review => _review(account!),
              _Stage.done => _done(account!),
            };
          },
        ),
      ),
    );
  }

  Widget _choose(List<Account> accounts, Account? account) {
    final c = context.colors;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.xs,
          AppSpace.gutter,
          AppSpace.xl,
        ),
        children: [
          Text(
            'Trae los movimientos de una cuenta sin conexión o de meses '
            'anteriores. Usa el extracto que descargas de tu banco.',
            style: AppTypography.body.copyWith(color: c.inkMuted),
          ),
          const SizedBox(height: AppSpace.lg),
          AccountField(
            label: 'Cuenta del extracto',
            account: account,
            error: _tried && account == null
                ? 'Elige a qué cuenta pertenece el extracto.'
                : null,
            onTap: () async {
              final id = await pickAccount(
                context,
                title: 'Cuenta del extracto',
                accounts: accounts,
                selected: _accountId,
              );
              if (id != null) setState(() => _accountId = id);
            },
          ),
          if (_problem case final p?) ...[
            const SizedBox(height: AppSpace.md),
            QBanner(
              tone: BannerTone.danger,
              title: p.title,
              message: p.message,
            ),
          ],
          const SizedBox(height: AppSpace.lg),
          QButton(
            label: 'Elegir archivo',
            icon: Icons.upload_file_rounded,
            onPressed: () => _pickAndRead(accounts),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            'PDF, Excel (.xlsx) o CSV, hasta 10 MB.',
            textAlign: TextAlign.center,
            style: context.text.bodySmall,
          ),
          const SizedBox(height: AppSpace.xl),
          const TrustNote(
            'Solo leemos los movimientos. No guardamos el archivo ni te '
            'pedimos la clave de tu banco.',
          ),
        ],
      ),
    );
  }

  Widget _review(Account account) {
    final c = context.colors;
    final duplicates = _candidates.where((x) => x.duplicate).length;
    final count = _selected.length;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.xs,
          AppSpace.gutter,
          AppSpace.xl,
        ),
        children: [
          Text(
            'Encontramos ${_candidates.length} movimientos para '
            '${account.shortName}.',
            style: AppTypography.subtitle.copyWith(color: c.ink),
          ),
          const SizedBox(height: AppSpace.xxs),
          Text(
            duplicates == 0
                ? 'Quita los que no quieras traer.'
                : duplicates == 1
                ? 'Uno ya estaba en Qullqi: no lo traemos otra vez.'
                : '$duplicates ya estaban en Qullqi: no los traemos otra '
                      'vez.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: AppSpace.md),
          QCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: Column(
              children: [
                for (final (i, x) in _candidates.indexed) ...[
                  if (i > 0) const Divider(),
                  _LineRow(
                    candidate: x,
                    selected: _selected.contains(i),
                    onChanged: x.duplicate || _saving
                        ? null
                        : (on) => setState(
                            () => on ? _selected.add(i) : _selected.remove(i),
                          ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          QButton(
            label: switch (count) {
              0 => 'Elige al menos un movimiento',
              1 => 'Importar 1 movimiento',
              _ => 'Importar $count movimientos',
            },
            loading: _saving,
            loadingLabel: 'Importando',
            onPressed: count == 0 ? null : () => _import(account),
          ),
          const SizedBox(height: AppSpace.xs),
          QButton.secondary(
            label: 'Elegir otro archivo',
            onPressed: _saving
                ? null
                : () => setState(() {
                    _stage = _Stage.choose;
                    _candidates = const [];
                  }),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            'El saldo de la cuenta no cambia: el extracto cuenta lo que ya '
            'pasó.',
            textAlign: TextAlign.center,
            style: context.text.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _done(Account account) {
    final review = switch (_toReview) {
      0 => '',
      1 => ' Uno parece un traslado: revísalo en Movimientos.',
      _ => ' $_toReview parecen traslados: revísalos en Movimientos.',
    };
    return MessageBody(
      child: EmptyState(
        icon: Icons.check_rounded,
        celebrate: true,
        title: _imported == 1
            ? 'Importamos 1 movimiento'
            : 'Importamos $_imported movimientos',
        message:
            'Ya cuentan en tus reportes. Le pusimos categoría a cada uno; '
            'puedes cambiarla.$review',
        actionLabel: 'Ver movimientos',
        onAction: () => _seeMovements(account),
        secondaryLabel: 'Listo',
        onSecondary: () => context.pop(),
      ),
    );
  }
}

/// Renglón del extracto con su casilla. Los que ya estaban no se eligen.
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.candidate,
    required this.selected,
    required this.onChanged,
  });

  final ImportCandidate candidate;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l = candidate.line;
    final income = l.amount > 0;
    final date = Dates.dayMonth(l.date);
    return Semantics(
      checked: selected,
      enabled: onChanged != null,
      label: [
        l.description,
        if (income) 'Ingreso' else 'Gasto',
        Cop.spoken(l.amount.abs()),
        date,
        if (candidate.duplicate) 'Ya está en Qullqi',
      ].join('. '),
      // La acción va en este nodo: la casilla de adentro queda excluida.
      onTap: onChanged == null ? null : () => onChanged!(!selected),
      excludeSemantics: true,
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!selected),
        borderRadius: AppRadius.controlAll,
        child: AmountRowLayout(
          leading: Checkbox(
            value: selected,
            onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
          ),
          title: l.description,
          titleLines: 2,
          details: [
            Text(
              date,
              style: AppTypography.caption.copyWith(color: c.inkSubtle),
            ),
            if (candidate.duplicate)
              const Padding(
                padding: EdgeInsets.only(top: AppSpace.xxs),
                child: StatusPill('Ya está en Qullqi'),
              ),
          ],
          trailing: MoneyText(
            l.amount,
            signed: income,
            animate: false,
            style: AppTypography.body.copyWith(
              color: candidate.duplicate
                  ? c.inkSubtle
                  : income
                  ? c.income
                  : c.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
