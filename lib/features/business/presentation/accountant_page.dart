import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inti/core/clock/clock.dart';
import 'package:inti/core/format/dates.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/business/data/business_back_office.dart';
import 'package:inti/features/business/data/invoices_repository.dart';
import 'package:inti/features/business/domain/accountant.dart';
import 'package:inti/features/transactions/data/transactions_repository.dart';

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$');

/// Tu contador: quién ve tu negocio y el archivo que le puedes mandar.
class AccountantPage extends ConsumerStatefulWidget {
  const AccountantPage({super.key});

  @override
  ConsumerState<AccountantPage> createState() => _AccountantPageState();
}

class _AccountantPageState extends ConsumerState<AccountantPage> {
  final _address = TextEditingController();
  ExportPeriod _period = ExportPeriod.thisMonth;
  bool _tried = false;
  bool _sending = false;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  bool get _valid => _email.hasMatch(_address.text.trim());

  Future<void> _invite() async {
    setState(() => _tried = true);
    if (!_valid) return;
    setState(() => _sending = true);
    try {
      final invite = await ref
          .read(accountantRepositoryProvider)
          .invite(_address.text);
      if (!mounted) return;
      _address.clear();
      setState(() {
        _sending = false;
        _tried = false;
      });
      showQToast(context, 'Le enviamos la invitación a ${invite.email}');
    } on Object {
      if (!mounted) return;
      setState(() => _sending = false);
      showQToast(context, 'No pudimos enviarla. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final invites = ref.watch(accountantInvitesProvider).value ?? const [];
    final invoices = ref.watch(invoicesProvider).value ?? const [];
    final bills = ref.watch(billsProvider).value ?? const [];
    final txs = ref.watch(transactionsProvider).value ?? const [];
    final now = ref.watch(clockProvider)();
    final export = buildAccountantExport(
      invoices: invoices,
      bills: bills,
      transactions: txs,
      period: _period,
      now: now,
    );
    final visible = invites.where((i) => i.status != InviteStatus.revoked);

    return Scaffold(
      appBar: AppBar(title: const Text('Tu contador')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.xs,
            AppSpace.gutter,
            AppSpace.xxl,
          ),
          children: [
            Text(
              'Dale a tu contador acceso de solo lectura al negocio, o mándale '
              'un archivo con lo que necesita.',
              style: context.text.bodyMedium?.copyWith(
                color: context.colors.inkMuted,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            const SectionHeader('Quién puede ver tu negocio'),
            const SizedBox(height: AppSpace.xs),
            if (visible.isEmpty)
              const SectionNote('Nadie todavía.')
            else
              QCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: Column(
                  children: [
                    for (final (i, inv) in visible.indexed) ...[
                      if (i > 0) const Divider(),
                      SettingsRow(
                        icon: Icons.person_outline_rounded,
                        title: inv.email,
                        subtitle:
                            '${inv.status.label} · '
                            '${Dates.dayMonth(inv.createdAt)}',
                        trailing: IconButton(
                          tooltip: 'Quitar acceso a ${inv.email}',
                          icon: const Icon(Icons.person_remove_outlined),
                          onPressed: () => _revoke(inv),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: AppSpace.lg),
            TextField(
              controller: _address,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Correo de tu contador',
                hintText: 'contadora@ejemplo.co',
                errorText: _tried && !_valid
                    ? 'Escribe un correo válido.'
                    : null,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            QButton(
              label: 'Invitar a mi contador',
              icon: Icons.send_outlined,
              loading: _sending,
              loadingLabel: 'Enviando',
              onPressed: _invite,
            ),
            const SizedBox(height: AppSpace.xl),
            const SectionHeader('Qué ve'),
            const SizedBox(height: AppSpace.xs),
            const QCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Visibility(
                    Icons.check_circle_outline_rounded,
                    'Ve: facturas, cuentas por pagar, ingresos, gastos e IVA '
                    'del negocio.',
                  ),
                  SizedBox(height: AppSpace.xs),
                  _Visibility(
                    Icons.block_rounded,
                    'No ve: tus finanzas personales, saldos, claves ni cómo '
                    'mover plata.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            const SectionHeader('O mándale un archivo'),
            const SizedBox(height: AppSpace.xs),
            Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                for (final p in ExportPeriod.values)
                  ChoiceChip(
                    label: Text(p.label),
                    selected: _period == p,
                    onSelected: (_) => setState(() => _period = p),
                  ),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              export.rows == 1
                  ? '1 registro en ${_period.label.toLowerCase()}.'
                  : '${export.rows} registros en '
                        '${_period.label.toLowerCase()}.',
              style: context.text.bodySmall,
            ),
            const SizedBox(height: AppSpace.sm),
            QButton.secondary(
              label: 'Copiar archivo (CSV)',
              icon: Icons.copy_rounded,
              onPressed: export.rows == 0
                  ? null
                  : () {
                      // Copiar no debe frenar nada: se hace sin esperar.
                      unawaited(
                        Clipboard.setData(ClipboardData(text: export.csv)),
                      );
                      showQToast(
                        context,
                        'Copiamos ${export.rows} registros para tu contador',
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _revoke(AccountantInvite inv) async {
    final ok = await confirmDestructive(
      context,
      title: '¿Quitar el acceso de ${inv.email}?',
      message:
          'Deja de ver tu negocio de inmediato. Puedes volver a invitarlo '
          'cuando quieras.',
      confirmLabel: 'Quitar acceso a ${inv.email}',
    );
    if (!ok || !mounted) return;
    await ref.read(accountantRepositoryProvider).revoke(inv.id);
    if (mounted) showQToast(context, 'Quitamos el acceso');
  }
}

class _Visibility extends StatelessWidget {
  const _Visibility(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: Icon(
              icon,
              size: AppSize.iconSm,
              color: context.colors.inkMuted,
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(child: Text(text, style: context.text.bodyMedium)),
        ],
      ),
    );
  }
}
