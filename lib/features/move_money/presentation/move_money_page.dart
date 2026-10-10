import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/format/dates.dart';
import 'package:qullqi/core/money/money.dart';
import 'package:qullqi/core/security/confirm_identity.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/widgets/widgets.dart';
import 'package:qullqi/features/accounts/data/accounts_repository.dart';
import 'package:qullqi/features/accounts/domain/account.dart';
import 'package:qullqi/features/accounts/presentation/widgets/account_picker.dart';
import 'package:qullqi/features/move_money/data/money_mover.dart';
import 'package:qullqi/features/move_money/domain/move.dart';

enum _Step { form, review, sending, result }

/// Cuentas ya elegidas al abrir (p. ej. "Pagar tarjeta" desde su detalle).
@immutable
class MovePreset {
  const MovePreset({this.fromId, this.toId});

  final String? fromId;
  final String? toId;
}

/// Mover plata entre tus cuentas en cuatro pasos claros:
/// elegir (desde, hacia, cuánto) → revisar → confirmar que eres tú →
/// resultado con comprobante.
class MoveMoneyPage extends ConsumerStatefulWidget {
  const MoveMoneyPage({super.key, this.preset});

  final MovePreset? preset;

  @override
  ConsumerState<MoveMoneyPage> createState() => _MoveMoneyPageState();
}

class _MoveMoneyPageState extends ConsumerState<MoveMoneyPage> {
  _Step _step = _Step.form;
  late String? _fromId = widget.preset?.fromId;
  late String? _toId = widget.preset?.toId;
  String _digits = '';
  bool _tried = false;
  late MoveResult _result;

  int get _amount => AmountInput.value(_digits);

  Account? _find(List<Account> all, String? id) =>
      all.where((a) => a.id == id).firstOrNull;

  /// Origen por defecto: la cuenta con más plata que se pueda usar.
  Account? _from(List<Account> all) {
    final usable =
        all
            .where(
              (a) =>
                  !a.isCard &&
                  a.paymentsEnabled &&
                  a.status != ConnectionStatus.needsReconnect,
            )
            .toList()
          ..sort((a, b) => b.balance.compareTo(a.balance));
    return _find(all, _fromId) ?? usable.firstOrNull;
  }

  Account? _to(List<Account> all, Account? from) =>
      _find(all, _toId) ??
      all.where((a) => a.id != from?.id && !a.isCard).firstOrNull;

  Future<void> _send(Account from, Account to) async {
    final ok = await confirmIdentity(
      context,
      reason:
          'Para mover ${Cop.format(_amount)} de ${from.shortName} a '
          '${to.shortName}.',
      pinOnly: _amount >= highAmountThreshold,
      pinOnlyNote: 'Por ser un monto alto, escribe tu PIN de Qullqi.',
    );
    if (!ok || !mounted) return;
    setState(() => _step = _Step.sending);
    try {
      final r = await ref
          .read(moneyMoverProvider)
          .move(from: from, to: to, amount: _amount);
      if (!mounted) return;
      // La vibración nunca debe bloquear el flujo.
      unawaited(HapticFeedback.mediumImpact());
      setState(() {
        _result = r;
        _step = _Step.result;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _result = MoveResult(
          status: MoveStatus.rejected,
          reference: '—',
          when: DateTime.now(),
          reason:
              'Se perdió la conexión. No se movió nada; inténtalo de '
              'nuevo.',
        );
        _step = _Step.result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    if (!accountsAsync.hasValue) {
      // Mientras cargan (o si fallan) las cuentas, la pantalla lo dice.
      return Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Mover plata'),
        ),
        body: SafeArea(child: AccountsGate(builder: (_) => const SizedBox())),
      );
    }
    final accounts = accountsAsync.requireValue;
    final from = _from(accounts);
    final to = _to(accounts, from);
    final problem = validateMove(from: from, to: to, amount: _amount);

    final body = switch (_step) {
      _Step.form => _form(context, accounts, from, to, problem),
      _Step.review => _review(context, from!, to!),
      _Step.sending => _Sending(amount: _amount, to: to!),
      _Step.result => _ResultView(
        result: _result,
        amount: _amount,
        from: from!,
        to: to!,
        onDone: () => Navigator.of(context).pop(),
        onRetry: () => setState(() => _step = _Step.review),
      ),
    };

    return PopScope(
      // Desde la revisión, "atrás" vuelve al formulario; mientras se envía
      // no se puede salir.
      canPop: _step == _Step.form || _step == _Step.result,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step == _Step.review) {
          setState(() => _step = _Step.form);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _step == _Step.review
              ? BackButton(onPressed: () => setState(() => _step = _Step.form))
              : _step == _Step.sending
              ? const SizedBox.shrink()
              : const CloseButton(),
          title: Text(switch (_step) {
            _Step.form => 'Mover plata',
            _Step.review => 'Revisa antes de mover',
            _ => '',
          }),
        ),
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: AppMotion.of(context, AppMotion.standard),
            child: KeyedSubtree(key: ValueKey(_step), child: body),
          ),
        ),
      ),
    );
  }

  Widget _form(
    BuildContext context,
    List<Account> accounts,
    Account? from,
    Account? to,
    MoveProblem? problem,
  ) {
    final sources = accounts.where((a) => !a.isCard).toList();
    final targets = accounts.where((a) => a.id != from?.id).toList();
    // Solo se avisa del problema cuando ya hay algo que corregir.
    final shown =
        problem == null || (problem == MoveProblem.noAmount && !_tried)
        ? null
        : moveProblemMessage(problem, from: from, to: to);
    final fromProblem = {
      MoveProblem.insufficientFunds,
      MoveProblem.sourceDisconnected,
      MoveProblem.sourceManual,
      MoveProblem.paymentsNotEnabled,
    }.contains(problem);

    return KeypadLayout(
      fields: [
        AmountDisplay(
          digits: _digits,
          label: '¿Cuánto quieres mover?',
          error: fromProblem ? null : shown,
        ),
        const SizedBox(height: AppSpace.sm),
        AccountField(
          label: 'Desde',
          account: from,
          error: fromProblem ? shown : null,
          onTap: () async {
            final id = await pickAccount(
              context,
              title: 'Desde qué cuenta',
              accounts: sources,
              selected: from?.id,
            );
            if (id != null) {
              setState(() {
                _fromId = id;
                if (_toId == id) _toId = null;
              });
            }
          },
        ),
        const SizedBox(height: AppSpace.xs),
        AccountField(
          label: to?.isCard ?? false ? 'Tarjeta a pagar' : 'Hacia',
          account: to,
          onTap: () async {
            final id = await pickAccount(
              context,
              title: 'Hacia qué cuenta',
              accounts: targets,
              selected: to?.id,
            );
            if (id != null) setState(() => _toId = id);
          },
        ),
        if (from != null && !from.isCard && from.balance > 0) ...[
          const SizedBox(height: AppSpace.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: QButton.text(
              label: to?.isCard ?? false
                  ? 'Pagar toda la deuda'
                  : 'Mover todo el saldo',
              onPressed: () => setState(() {
                final all = to?.isCard ?? false
                    ? to!.debt.clamp(0, from.balance)
                    : from.balance;
                _digits = all > 0 ? '$all' : '';
              }),
            ),
          ),
        ],
      ],
      keypad: AmountKeypad(
        digits: _digits,
        onChanged: (d) => setState(() {
          _digits = d;
          _tried = false;
        }),
      ),
      action: QButton(
        label: 'Revisar',
        onPressed: () {
          if (problem != null) {
            setState(() => _tried = true);
            return;
          }
          // Se fijan las cuentas: los saldos cambian al mover y el
          // origen por defecto no debe saltar a otra cuenta.
          setState(() {
            _fromId = from!.id;
            _toId = to!.id;
            _step = _Step.review;
          });
        },
      ),
    );
  }

  Widget _review(BuildContext context, Account from, Account to) {
    final c = context.colors;
    final instant = {'nequi', 'daviplata'}.contains(from.id);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xl,
      ),
      children: [
        Text('Vas a mover', style: context.text.bodySmall),
        MoneyText(
          _amount,
          currency: true,
          style: AppTypography.display.copyWith(color: c.ink),
        ),
        const SizedBox(height: AppSpace.lg),
        QCard(
          child: Column(
            children: [
              DetailLine('Desde', from.shortName),
              DetailLine(to.isCard ? 'Tarjeta a pagar' : 'Hacia', to.shortName),
              const DetailLine('Costo', 'Sin costo'),
              DetailLine('Llega', instant ? 'Al instante' : 'Hoy mismo'),
              if (to.isCard)
                DetailLine(
                  'Deuda después',
                  Cop.format((to.debt - _amount).clamp(0, to.debt)),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        const TrustNote(
          'Te pediremos tu huella, Face ID o PIN. Nunca guardamos tus '
          'claves del banco.',
        ),
        const SizedBox(height: AppSpace.xl),
        QButton(
          label: 'Mover ${Cop.format(_amount)}',
          icon: Icons.swap_horiz_rounded,
          onPressed: () => _send(from, to),
        ),
        const SizedBox(height: AppSpace.xs),
        QButton.secondary(
          label: 'Cambiar algo',
          onPressed: () => setState(() => _step = _Step.form),
        ),
      ],
    );
  }
}

class _Sending extends StatelessWidget {
  const _Sending({required this.amount, required this.to});

  final int amount;
  final Account to;

  @override
  Widget build(BuildContext context) => BusyMessage(
    title: 'Moviendo ${Cop.format(amount)} a ${to.shortName}',
    message: 'No cierres la app. Toma unos segundos.',
  );
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.result,
    required this.amount,
    required this.from,
    required this.to,
    required this.onDone,
    required this.onRetry,
  });

  final MoveResult result;
  final int amount;
  final Account from;
  final Account to;
  final VoidCallback onDone;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, bg, fg, title, message) = switch (result.status) {
      MoveStatus.done => (
        Icons.check_rounded,
        c.primaryContainer,
        c.onPrimaryContainer,
        to.isCard ? 'Tarjeta pagada' : 'Plata movida',
        '${Cop.format(amount)} ya están en ${to.shortName}.',
      ),
      MoveStatus.pending => (
        Icons.schedule_rounded,
        c.warningContainer,
        c.warning,
        'Tu banco lo está procesando',
        '${from.shortName} recibió la orden. Los '
            '${Cop.format(amount)} llegan hoy a ${to.shortName}; te avisamos.',
      ),
      MoveStatus.rejected => (
        Icons.close_rounded,
        c.dangerContainer,
        c.onDangerContainer,
        'No se movió la plata',
        result.reason ?? 'Tu banco rechazó la operación.',
      ),
    };
    final ok = result.status != MoveStatus.rejected;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xl,
      ),
      children: [
        Semantics(
          liveRegion: true,
          child: EmptyState(
            icon: icon,
            title: title,
            message: message,
            iconBackground: bg,
            iconColor: fg,
            celebrate: result.status == MoveStatus.done,
          ),
        ),
        if (ok) ...[
          const SizedBox(height: AppSpace.lg),
          QCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Comprobante', style: context.text.bodySmall),
                SelectableText(
                  result.reference,
                  style: AppTypography.subtitle.copyWith(
                    color: c.ink,
                    fontFeatures: AppTypography.tabular,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  '${Dates.longDay(result.when)} · ${Dates.time(result.when)}',
                  style: context.text.bodySmall,
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpace.xl),
        if (ok)
          QButton(label: 'Cerrar', onPressed: onDone)
        else ...[
          QButton(label: 'Reintentar', onPressed: onRetry),
          const SizedBox(height: AppSpace.xs),
          QButton.secondary(label: 'Cerrar', onPressed: onDone),
        ],
      ],
    );
  }
}
