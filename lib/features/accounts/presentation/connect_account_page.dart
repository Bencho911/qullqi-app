import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart';
import 'package:inti/features/accounts/domain/account.dart';
import 'package:inti/features/accounts/domain/institution.dart';
import 'package:inti/features/transactions/domain/transaction_filter.dart';

enum _Step { pick, consent, connecting, done, failed }

/// Conectar (o reconectar) una cuenta por Open Finance:
/// elegir entidad → permisos → conectando → listo o error.
class ConnectAccountPage extends ConsumerStatefulWidget {
  const ConnectAccountPage({super.key, this.reconnectAccountId});

  /// Si viene, se renueva el permiso de esa cuenta (sin elegir entidad).
  final String? reconnectAccountId;

  @override
  ConsumerState<ConnectAccountPage> createState() => _ConnectAccountPageState();
}

class _ConnectAccountPageState extends ConsumerState<ConnectAccountPage> {
  _Step _step = _Step.pick;
  Institution? _institution;
  String _query = '';
  bool _accepted = false;
  bool _payments = false;
  String? _error;
  Account? _created;

  bool get _isReconnect => widget.reconnectAccountId != null;

  @override
  void initState() {
    super.initState();
    if (_isReconnect) _step = _Step.consent;
  }

  Account? get _reconnecting => ref
      .read(accountsProvider)
      .value
      ?.where((a) => a.id == widget.reconnectAccountId)
      .firstOrNull;

  String get _name =>
      _institution?.name ?? _reconnecting?.institution ?? 'tu banco';

  Future<void> _connect() async {
    setState(() => _step = _Step.connecting);
    final repo = ref.read(accountsRepositoryProvider);
    try {
      if (_isReconnect) {
        await repo.reconnect(widget.reconnectAccountId!);
      } else {
        _created = await repo.connect(_institution!, payments: _payments);
      }
      if (mounted) setState(() => _step = _Step.done);
    } on ConnectionFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _step = _Step.failed;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Se perdió la conexión. No se guardó nada.';
          _step = _Step.failed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_step) {
      _Step.pick => _pick(context),
      _Step.consent => _consent(context),
      _Step.connecting => _connecting(context),
      _Step.done => _done(context),
      _Step.failed => _failed(context),
    };
    return PopScope(
      // Mientras conecta no se sale; desde los permisos, "atrás" vuelve a la
      // lista (salvo al reconectar, que empieza ahí).
      canPop:
          _step != _Step.connecting &&
          !(_step == _Step.consent && !_isReconnect),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step == _Step.consent) {
          setState(() => _step = _Step.pick);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _step == _Step.consent && !_isReconnect
              ? BackButton(onPressed: () => setState(() => _step = _Step.pick))
              : _step == _Step.connecting
              ? const SizedBox.shrink()
              : const CloseButton(),
          title: Text(switch (_step) {
            _Step.pick => 'Conectar cuenta',
            _Step.consent => _isReconnect ? 'Reconectar $_name' : _name,
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

  Widget _pick(BuildContext context) {
    final q = normalizeForSearch(_query);
    final list = Institutions.all
        .where((i) => q.isEmpty || normalizeForSearch(i.name).contains(q))
        .toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xl,
      ),
      children: [
        TextField(
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            labelText: 'Busca tu banco o billetera',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (list.isEmpty)
          SectionNote('No encontramos «$_query». Puedes agregarla a mano.')
        else
          for (final i in list)
            SettingsRow(
              leading: InitialsAvatar(i.badge),
              title: i.name,
              subtitle: i.description,
              enabled: i.available,
              trailing: i.available ? null : const StatusPill('Muy pronto'),
              onTap: () => setState(() {
                _institution = i;
                _payments = false;
                _accepted = false;
                _step = _Step.consent;
              }),
            ),
        const SizedBox(height: AppSpace.md),
        OptionRow(
          icon: Icons.edit_outlined,
          title: 'Agregar cuenta a mano',
          subtitle: 'Si tu entidad no aparece o no tiene conexión',
          onTap: () => context.pushReplacement(Routes.manualAccount),
        ),
      ],
    );
  }

  Widget _consent(BuildContext context) {
    final c = context.colors;
    final supportsPayments = _institution?.supportsPayments ?? !_isReconnect;
    Widget permission(IconData icon, String title, String detail) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(
              icon: icon,
              background: c.primaryContainer,
              foreground: c.onPrimaryContainer,
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall),
                  Text(detail, style: context.text.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.xs,
        AppSpace.gutter,
        AppSpace.xl,
      ),
      children: [
        Text(
          _isReconnect
              ? 'Tu permiso con $_name venció. Renuévalo para volver a ver '
                    'tus saldos de hoy.'
              : 'Inti va a pedirle a $_name permiso para leer tu '
                    'información. Esto es lo que verás:',
          style: AppTypography.body.copyWith(color: c.inkMuted),
        ),
        const SizedBox(height: AppSpace.md),
        permission(
          Icons.account_balance_wallet_outlined,
          'Saldos',
          'Para calcular cuánto puedes gastar de verdad.',
        ),
        permission(
          Icons.receipt_long_outlined,
          'Movimientos de los últimos 12 meses',
          'Para ordenarlos y detectar traslados y suscripciones.',
        ),
        permission(
          Icons.visibility_off_outlined,
          'Nunca tus claves',
          'Entras en $_name y autorizas un permiso que puedes revocar.',
        ),
        if (!_isReconnect && supportsPayments) ...[
          const SizedBox(height: AppSpace.sm),
          QCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: SwitchRow(
              title: 'Permitir mover plata (opcional)',
              subtitle:
                  'Para pagar tarjetas y pasar plata entre tus cuentas. Cada '
                  'movimiento pide tu huella o PIN.',
              value: _payments,
              onChanged: (v) => setState(() => _payments = v),
            ),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        CheckRow(
          value: _accepted,
          onChanged: (v) => setState(() => _accepted = v),
          label:
              'Autorizo a Inti a consultar mi información financiera según '
              'la Ley 1581 de Habeas Data.',
        ),
        const SizedBox(height: AppSpace.md),
        QButton(
          label: 'Continuar a $_name',
          onPressed: _accepted ? _connect : null,
        ),
        if (!_accepted)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Text(
              'Marca la autorización para continuar.',
              textAlign: TextAlign.center,
              style: context.text.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _connecting(BuildContext context) => BusyMessage(
    title: 'Conectando con $_name',
    message: 'Traemos tus saldos y movimientos. Toma unos segundos.',
  );

  Widget _done(BuildContext context) {
    final c = context.colors;
    final created = _created;
    return MessageBody(
      child: EmptyState(
        icon: Icons.check_rounded,
        celebrate: true,
        iconBackground: c.primaryContainer,
        iconColor: c.onPrimaryContainer,
        title: _isReconnect ? '$_name está al día' : '$_name quedó conectada',
        message: _isReconnect
            ? 'Renovamos el permiso y actualizamos tus saldos.'
            : 'Ya ves tus saldos y los movimientos de los últimos 12 meses.',
        actionLabel: created == null ? 'Cerrar' : 'Ver la cuenta',
        onAction: () => created == null
            ? context.pop()
            : context.pushReplacement(Routes.account(created.id)),
        secondaryLabel: created == null ? null : 'Conectar otra',
        onSecondary: () => setState(() {
          _institution = null;
          _created = null;
          _step = _Step.pick;
        }),
      ),
    );
  }

  Widget _failed(BuildContext context) {
    final c = context.colors;
    return MessageBody(
      child: EmptyState(
        icon: Icons.link_off_rounded,
        iconBackground: c.dangerContainer,
        iconColor: c.onDangerContainer,
        title: 'No pudimos conectar $_name',
        message: _error ?? 'Inténtalo de nuevo en unos minutos.',
        actionLabel: 'Reintentar',
        onAction: _connect,
        secondaryLabel: 'Agregar cuenta a mano',
        onSecondary: () => context.pushReplacement(Routes.manualAccount),
      ),
    );
  }
}
