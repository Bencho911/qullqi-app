import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/core/scope/scope.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/app_tokens.dart';
import 'package:qullqi/core/theme/app_typography.dart';
import 'package:qullqi/core/theme/theme_mode.dart';
import 'package:qullqi/core/widgets/widgets.dart';

/// Galería del sistema de diseño (Hito 0). Herramienta interna: muestra cada
/// componente con datos de ejemplo en claro y oscuro.
class GalleryPage extends ConsumerStatefulWidget {
  const GalleryPage({super.key});

  @override
  ConsumerState<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends ConsumerState<GalleryPage> {
  Scope _scope = Scope.all;
  String _digits = '85400';
  bool _switch = true;
  bool _loading = false;
  String _account = 'bancolombia';
  int _chip = 0;

  int get _available => switch (_scope) {
    Scope.all => 3240000,
    Scope.personal => 1910000,
    Scope.business => 1330000,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mode = ref.watch(themeModeProvider);
    final dark =
        mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return Scaffold(
      appBar: AppBar(
        title: const QullqiLockup(),
        actions: [
          IconButton(
            tooltip: dark ? 'Usar tema claro' : 'Usar tema oscuro',
            icon: Icon(
              dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
            ),
            onPressed: () => ref
                .read(themeModeProvider.notifier)
                .select(dark ? ThemeMode.light : ThemeMode.dark),
          ),
          const SizedBox(width: AppSpace.xs),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.xs,
          AppSpace.gutter,
          AppSpace.xxl,
        ),
        children: [
          Text('Sistema de diseño', style: context.text.headlineSmall),
          const SizedBox(height: AppSpace.xxs),
          Text(
            'Calma verde · componentes de Qullqi',
            style: AppTypography.body.copyWith(color: c.inkMuted),
          ),
          const _Gap(),
          const SectionHeader('Vista'),
          const SizedBox(height: AppSpace.xs),
          ScopeSwitcher(
            value: _scope,
            onChanged: (s) => setState(() => _scope = s),
          ),
          const SizedBox(height: AppSpace.md),
          HeroBalance(
            label: 'Disponible para gastar',
            value: _available,
            caption: 'Ya descontamos lo que pagas en los próximos 30 días',
            onInfo: () => showQSheet<void>(
              context,
              title: 'Cómo calculamos tu disponible',
              builder: (context) => Text(
                'Es lo que tienes en tus cuentas menos lo que ya debes pagar '
                'pronto: tarjetas, arriendo e impuestos.',
                style: AppTypography.body.copyWith(
                  color: context.colors.inkMuted,
                ),
              ),
            ),
            shares: _scope == Scope.all
                ? [
                    BalanceShare('Personal', 1910000, c.heroAccent),
                    const BalanceShare('Negocio', 1330000, Color(0xFF86C3DE)),
                  ]
                : const [],
          ),
          const _Gap(),
          const SectionHeader('Botones'),
          const SizedBox(height: AppSpace.xs),
          QButton(
            label: 'Mover plata',
            icon: Icons.swap_horiz_rounded,
            loading: _loading,
            loadingLabel: 'Moviendo tu plata',
            onPressed: () async {
              setState(() => _loading = true);
              await Future<void>.delayed(const Duration(milliseconds: 1400));
              if (!context.mounted) return;
              setState(() => _loading = false);
              showQToast(context, r'Listo: moviste $300.000 a Nequi');
            },
          ),
          const SizedBox(height: AppSpace.xs),
          QButton.secondary(label: 'Registrar gasto', onPressed: () {}),
          const SizedBox(height: AppSpace.xs),
          const QButton(label: 'Guardar (deshabilitado)', onPressed: null),
          const SizedBox(height: AppSpace.xs),
          Row(
            children: [
              QButton.text(label: 'Ver todo', onPressed: () {}),
              const Spacer(),
              QButton.text(
                label: 'Eliminar',
                icon: Icons.delete_outline_rounded,
                onPressed: () => confirmDestructive(
                  context,
                  title: '¿Eliminar este movimiento?',
                  message:
                      'Se quita de tu historial y el saldo de Nequi vuelve a '
                      'como estaba. No se puede deshacer.',
                  confirmLabel: 'Eliminar Éxito Chapinero',
                ),
              ),
            ],
          ),
          const _Gap(),
          const SectionHeader('Campos'),
          const SizedBox(height: AppSpace.xs),
          const TextField(
            decoration: InputDecoration(
              labelText: 'Comercio o persona',
              hintText: 'Ej. Éxito Calle 80',
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          const TextField(
            decoration: InputDecoration(
              labelText: 'Correo electrónico',
              errorText: 'Revisa el correo: falta algo como @correo.com.',
            ),
          ),
          const _Gap(),
          const SectionHeader('Filtros, interruptor y etiquetas'),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              for (final (i, l) in [
                'Todos',
                'Gastos',
                'Ingresos',
                'Traslados',
              ].indexed)
                ChoiceChip(
                  label: Text(l),
                  selected: _chip == i,
                  onSelected: (_) => setState(() => _chip = i),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Avisarme antes de cada pago'),
            subtitle: const Text('Te escribimos 3 días antes'),
            value: _switch,
            onChanged: (v) => setState(() => _switch = v),
          ),
          const Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              StatusPill('Personal'),
              StatusPill('Negocio', tone: PillTone.business),
              StatusPill('Por revisar', tone: PillTone.transfer),
              StatusPill('Vence en 3 días', tone: PillTone.warning),
              StatusPill('Vencida', tone: PillTone.danger),
              StatusPill(
                'Al día',
                tone: PillTone.primary,
                icon: Icons.check_rounded,
              ),
            ],
          ),
          const _Gap(),
          SectionHeader(
            'Cuentas',
            action: 'Ver todas',
            onAction: () {},
            actionSemantics: 'Ver todas tus cuentas',
          ),
          const SizedBox(height: AppSpace.xs),
          AccountTile(
            initials: 'BC',
            name: 'Bancolombia',
            detail: 'Ahorros •• 4521',
            balance: 1200000,
            syncLabel: 'Actualizada hace 5 min',
            ownership: _scope == Scope.all
                ? const StatusPill('Personal')
                : null,
            onTap: () {},
          ),
          const SizedBox(height: AppSpace.xs),
          AccountTile(
            initials: 'DV',
            name: 'Davivienda',
            detail: 'Corriente •• 7710',
            balance: 2300000,
            sync: SyncState.reconnect,
            syncLabel: 'Reconecta para ver el saldo de hoy',
            ownership: _scope == Scope.all
                ? const StatusPill('Negocio', tone: PillTone.business)
                : null,
            onTap: () {},
          ),
          const _Gap(),
          const SectionHeader('Movimientos'),
          TransactionRow(
            icon: Icons.shopping_basket_rounded,
            title: 'Éxito Chapinero',
            subtitle: 'Mercado · Nequi · 14:32',
            amount: 85400,
            kind: FlowKind.expense,
            onTap: () {},
          ),
          TransactionRow(
            icon: Icons.payments_rounded,
            title: 'Anticipo proyecto UX',
            subtitle: 'Honorarios · Davivienda · 11:15',
            amount: 2500000,
            kind: FlowKind.income,
            pill: const StatusPill('Negocio', tone: PillTone.business),
            onTap: () {},
          ),
          TransactionRow(
            icon: Icons.swap_horiz_rounded,
            title: 'Bancolombia → Nequi',
            subtitle: 'Traslado entre tus cuentas · 09:14',
            amount: 300000,
            kind: FlowKind.transfer,
            pill: const StatusPill('Por revisar', tone: PillTone.transfer),
            onTap: () {},
          ),
          const _Gap(),
          const SectionHeader('Progreso'),
          const SizedBox(height: AppSpace.sm),
          const QProgressBar(value: 0.54, semanticLabel: 'Transporte'),
          const SizedBox(height: AppSpace.sm),
          const QProgressBar(
            value: 0.82,
            tone: ProgressTone.warning,
            semanticLabel: 'Mercado',
          ),
          const SizedBox(height: AppSpace.sm),
          const QProgressBar(
            value: 1.1,
            tone: ProgressTone.danger,
            semanticLabel: 'Salidas',
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              QProgressRing(
                value: 0.62,
                semanticLabel: 'Fondo de emergencia',
                child: Text(
                  '62 %',
                  style: AppTypography.label.copyWith(color: c.ink),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fondo de emergencia', style: context.text.titleSmall),
                    MoneyText(
                      3720000,
                      style: AppTypography.body.copyWith(color: c.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const _Gap(),
          const SectionHeader('Monto'),
          const SizedBox(height: AppSpace.sm),
          AmountDisplay(digits: _digits, label: '¿Cuánto fue?'),
          const SizedBox(height: AppSpace.sm),
          AmountKeypad(
            digits: _digits,
            onChanged: (d) => setState(() => _digits = d),
          ),
          const _Gap(),
          const SectionHeader('Hojas'),
          const SizedBox(height: AppSpace.xs),
          QButton.secondary(
            label: 'Elegir cuenta',
            icon: Icons.account_balance_wallet_outlined,
            onPressed: () async {
              final picked = await pickFromSheet<String>(
                context,
                title: 'Desde qué cuenta',
                selected: _account,
                options: const [
                  PickOption(
                    value: 'bancolombia',
                    title: 'Bancolombia',
                    subtitle: 'Ahorros •• 4521',
                    trailing: r'$1.200.000',
                    leading: InitialsAvatar('BC'),
                  ),
                  PickOption(
                    value: 'nequi',
                    title: 'Nequi',
                    subtitle: 'Billetera •• 8901',
                    trailing: r'$850.000',
                    leading: InitialsAvatar('NQ'),
                  ),
                ],
              );
              if (picked != null) setState(() => _account = picked);
            },
          ),
          const _Gap(),
          const SectionHeader('Estados'),
          const EmptyState(
            icon: Icons.receipt_long_rounded,
            title: 'Aún no hay movimientos',
            message:
                'Conecta un banco o registra tu primer gasto y lo verás aquí.',
            actionLabel: 'Conectar un banco',
            secondaryLabel: 'Registrar un gasto',
          ),
          const SkeletonBlock(height: 64, radius: AppRadius.card),
          const SizedBox(height: AppSpace.xs),
          const SkeletonBlock(width: 180),
        ],
      ),
    );
  }
}

class _Gap extends StatelessWidget {
  const _Gap();

  @override
  Widget build(BuildContext context) => const SizedBox(height: AppSpace.xl);
}
