import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart'
    show ConnectionFailure;
import 'package:inti/features/investments/data/investments_repository.dart';
import 'package:inti/features/investments/domain/investment.dart';
import 'package:inti/features/investments/domain/investment_source.dart';
import 'package:inti/features/transactions/domain/transaction_filter.dart';

enum _Step { pick, consent, connecting, done, failed }

/// Conectar una entidad con tus inversiones (solo lectura):
/// elegir entidad → permisos → conectando → listo o error.
class ConnectInvestmentPage extends ConsumerStatefulWidget {
  const ConnectInvestmentPage({super.key});

  @override
  ConsumerState<ConnectInvestmentPage> createState() =>
      _ConnectInvestmentPageState();
}

class _ConnectInvestmentPageState extends ConsumerState<ConnectInvestmentPage> {
  _Step _step = _Step.pick;
  InvestmentSource? _source;
  String _query = '';
  bool _accepted = false;
  String? _error;
  List<Investment> _created = const [];

  String get _name => _source?.name ?? 'tu entidad';

  Future<void> _connect() async {
    final source = _source;
    if (source == null) return;
    setState(() => _step = _Step.connecting);
    try {
      final created = await ref
          .read(investmentsRepositoryProvider)
          .connect(source);
      if (!mounted) return;
      setState(() {
        _created = created;
        _step = _Step.done;
      });
    } on ConnectionFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _step = _Step.failed;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _error = 'Se perdió la conexión. No se guardó nada.';
        _step = _Step.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = switch (_step) {
      _Step.pick => _pick(context),
      _Step.consent => _consent(context),
      _Step.connecting => BusyMessage(
        title: 'Conectando con $_name',
        message: 'Traemos lo que tienes invertido. Toma unos segundos.',
      ),
      _Step.done => _done(context),
      _Step.failed => _failed(context),
    };
    return PopScope(
      // Mientras conecta no se sale; desde los permisos, "atrás" vuelve a la
      // lista.
      canPop: _step != _Step.connecting && _step != _Step.consent,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step == _Step.consent) {
          setState(() => _step = _Step.pick);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _step == _Step.consent
              ? BackButton(onPressed: () => setState(() => _step = _Step.pick))
              : _step == _Step.connecting
              ? const SizedBox.shrink()
              : const CloseButton(),
          title: Text(switch (_step) {
            _Step.pick => 'Conectar entidad',
            _Step.consent => _name,
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
    final list = InvestmentSources.all
        .where((s) => q.isEmpty || normalizeForSearch(s.name).contains(q))
        .toList();
    // Entidades que ya traen datos: no se conectan dos veces.
    final items = ref.watch(investmentsProvider).value ?? const <Investment>[];
    final connected = {
      for (final i in items)
        if (!i.isManual && i.institution != null) i.institution!,
    };
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
            labelText: 'Busca tu banco, comisionista o fondo',
            prefixIcon: Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        if (list.isEmpty)
          SectionNote('No encontramos «$_query». Puedes agregarla a mano.')
        else
          for (final s in list)
            SettingsRow(
              leading: InitialsAvatar(s.badge),
              title: s.name,
              subtitle: s.description,
              enabled: s.available && !connected.contains(s.name),
              trailing: !s.available
                  ? const StatusPill('Muy pronto')
                  : connected.contains(s.name)
                  ? const StatusPill('Conectada', tone: PillTone.primary)
                  : null,
              onTap: () => setState(() {
                _source = s;
                _accepted = false;
                _step = _Step.consent;
              }),
            ),
        const SizedBox(height: AppSpace.md),
        OptionRow(
          icon: Icons.edit_outlined,
          title: 'Agregar a mano',
          subtitle: 'Si tu entidad no aparece o no tiene conexión',
          onTap: () => context.pushReplacement(Routes.addInvestment),
        ),
      ],
    );
  }

  Widget _consent(BuildContext context) {
    final c = context.colors;
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
          'Inti va a pedirle a $_name permiso para leer lo que tienes '
          'invertido. Esto es lo que verás:',
          style: AppTypography.body.copyWith(color: c.inkMuted),
        ),
        const SizedBox(height: AppSpace.md),
        permission(
          Icons.pie_chart_outline_rounded,
          'Tus inversiones y su valor',
          'Qué tienes y cuánto vale hoy, para sumarlo a tu patrimonio.',
        ),
        permission(
          Icons.trending_up_rounded,
          'Rentabilidad y vencimientos',
          'Para decirte cuánto has ganado y cuándo vence un CDT.',
        ),
        permission(
          Icons.visibility_off_outlined,
          'Solo lectura, nunca tus claves',
          'Inti no compra, vende ni mueve tu plata. Entras en $_name y '
              'autorizas un permiso que puedes revocar.',
        ),
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

  Widget _done(BuildContext context) {
    final n = _created.length;
    return MessageBody(
      child: EmptyState(
        icon: Icons.check_rounded,
        celebrate: true,
        title: '$_name quedó conectada',
        message:
            '${n == 1 ? 'Trajimos 1 inversión' : 'Trajimos $n inversiones'}. '
            'Ya cuentan en tu patrimonio.',
        actionLabel: 'Listo',
        onAction: () => context.pop(),
        secondaryLabel: 'Conectar otra',
        onSecondary: () => setState(() {
          _source = null;
          _created = const [];
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
        secondaryLabel: 'Agregar a mano',
        onSecondary: () => context.pushReplacement(Routes.addInvestment),
      ),
    );
  }
}
