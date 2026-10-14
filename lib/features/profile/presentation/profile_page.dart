import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';
import 'package:inti/core/scope/scope.dart';
import 'package:inti/core/scope/scope_provider.dart';
import 'package:inti/core/security/biometrics_pref.dart';
import 'package:inti/core/security/identity.dart';
import 'package:inti/core/session/session.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/theme/theme_mode.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/accounts/data/accounts_repository.dart';
import 'package:inti/features/accounts/domain/account.dart';
import 'package:inti/features/profile/data/notification_prefs.dart';
import 'package:inti/features/profile/presentation/account_actions.dart';
import 'package:inti/features/rules/data/rules_provider.dart';
import 'package:inti/features/widgets/data/widget_bridge.dart';

/// Versión que se muestra al final del perfil.
const String appVersion = '0.1.0';

/// Correo de ayuda.
const String supportEmail = 'ayuda@inti.app';

/// Perfil y ajustes. Se abre desde el avatar, encima de las pestañas.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final mode = ref.watch(themeModeProvider);
    final biometrics = ref.watch(biometricsEnabledProvider);
    final notices = ref.watch(noticePrefsProvider);
    final rules = ref.watch(categoryRulesProvider);
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final c = context.colors;
    final toReconnect = accounts
        .where((a) => a.status == ConnectionStatus.needsReconnect)
        .length;

    Future<void> toggleBiometrics({required bool on}) async {
      if (on) {
        final identity = ref.read(identityVerifierProvider);
        if (!await identity.hasBiometrics()) {
          if (context.mounted) {
            showQToast(
              context,
              'Tu teléfono no tiene huella ni Face ID configurados.',
            );
          }
          return;
        }
        final ok = await identity.verifyBiometrics(
          'Confirma para entrar con tu huella o Face ID',
        );
        if (!ok) return;
      }
      await ref.read(biometricsEnabledProvider.notifier).set(enabled: on);
    }

    Future<void> toggleBusiness({required bool on}) async {
      await ref
          .read(sessionProvider.notifier)
          .update(user.copyWith(hasBusiness: on));
      // Sin negocio, la app vuelve a ser solo personal.
      if (!on) await ref.read(scopeProvider.notifier).select(Scope.personal);
    }

    Future<void> signOut() async {
      final ok = await confirmDestructive(
        context,
        title: '¿Cerrar sesión?',
        message:
            'Para volver a entrar necesitas tu correo y contraseña. '
            'Borramos el PIN de este teléfono.',
        confirmLabel: 'Cerrar sesión',
        cancelLabel: 'Seguir en Inti',
      );
      if (!ok) return;
      await ref.read(identityVerifierProvider).clearPin();
      await ref.read(sessionProvider.notifier).signOut();
    }

    Widget group(String title, List<Widget> rows) => Padding(
      padding: const EdgeInsets.only(top: AppSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title),
          const SizedBox(height: AppSpace.xs),
          QCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: Column(
              children: [
                for (final (i, r) in rows.indexed) ...[
                  if (i > 0) const Divider(),
                  r,
                ],
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Tu perfil')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.xs,
          AppSpace.gutter,
          AppSpace.xxl,
        ),
        children: [
          QCard(
            onTap: () => context.push(Routes.editProfile),
            semanticLabel:
                '${user.fullName}. ${user.email}. ${user.phone}. Editar datos',
            child: ExcludeSemantics(
              child: Row(
                children: [
                  InitialsAvatar(
                    user.initials,
                    size: AppSize.avatarLg,
                    background: c.primaryContainer,
                    foreground: c.onPrimaryContainer,
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.fullName, style: context.text.titleMedium),
                        Text(user.email, style: context.text.bodySmall),
                        Text(user.phone, style: context.text.bodySmall),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.inkSubtle),
                ],
              ),
            ),
          ),
          group('Seguridad', [
            SwitchRow(
              title: 'Entrar con huella o Face ID',
              subtitle: 'También para confirmar cuando mueves plata.',
              value: biometrics,
              onChanged: (v) => toggleBiometrics(on: v),
            ),
            SettingsRow(
              icon: Icons.pin_outlined,
              title: 'Cambiar PIN',
              onTap: () => context.push(Routes.changePin),
            ),
            SettingsRow(
              icon: Icons.devices_outlined,
              title: 'Dispositivos con tu cuenta',
              onTap: () => context.push(Routes.devices),
            ),
          ]),
          group('Tu plata', [
            SettingsRow(
              icon: Icons.account_balance_outlined,
              title: 'Conexiones con bancos',
              subtitle: toReconnect == 0
                  ? '${accounts.length} cuentas'
                  : '${accounts.length} cuentas · $toReconnect por reconectar',
              onTap: () => context.go(Routes.accounts),
            ),
            if (user.hasBusiness)
              SettingsRow(
                icon: Icons.storefront_outlined,
                title: 'Herramientas del negocio',
                subtitle: 'Facturas, cotizaciones, enlaces de pago e IVA',
                onTap: () => context.push(Routes.businessHub),
              ),
            SettingsRow(
              icon: Icons.groups_2_outlined,
              title: 'Compartir con otros',
              subtitle: 'Grupos, cuentas divididas, deudas y metas',
              onTap: () => context.push(Routes.sharingHub),
            ),
            SettingsRow(
              icon: Icons.event_note_outlined,
              title: 'Impuestos y obligaciones',
              subtitle: 'Tus fechas, el 4x1000 y el resumen para la renta',
              onTap: () => context.push(Routes.taxes),
            ),
            SettingsRow(
              icon: Icons.rule_rounded,
              title: 'Reglas de categorías',
              subtitle: rules.isEmpty
                  ? 'Que la app clasifique sola lo que repites'
                  : '${rules.length} '
                        '${rules.length == 1 ? 'regla' : 'reglas'}',
              onTap: () => context.push(Routes.rules),
            ),
            SwitchRow(
              title: 'Tengo negocio o soy independiente',
              subtitle: 'Muestra la vista Negocio con utilidad, cobros e IVA.',
              value: user.hasBusiness,
              onChanged: (v) => toggleBusiness(on: v),
            ),
          ]),
          group('Preferencias', [
            SwitchRow(
              title: 'Mostrar montos en los widgets',
              subtitle:
                  'Si lo apagas, los widgets dicen "Abre Inti" en vez '
                  'de tus cifras.',
              value: ref.watch(widgetAmountsProvider),
              onChanged: (v) =>
                  ref.read(widgetAmountsProvider.notifier).set(show: v),
            ),
            SettingsRow(
              icon: Icons.notifications_none_rounded,
              title: 'Avisos',
              subtitle:
                  '${notices.length} de ${NoticeKind.values.length} encendidos',
              onTap: () => context.push(Routes.notificationSettings),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Apariencia', style: context.text.titleSmall),
                  const SizedBox(height: AppSpace.xs),
                  SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    // Con texto grande las opciones no caben en una fila.
                    direction: isLargeText(context)
                        ? Axis.vertical
                        : Axis.horizontal,
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('Automático'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Claro'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Oscuro'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) =>
                        ref.read(themeModeProvider.notifier).select(s.first),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    'Automático sigue el tema de tu teléfono.',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
          ]),
          group('Privacidad y datos', [
            SettingsRow(
              icon: Icons.shield_outlined,
              title: 'Mis datos',
              subtitle: 'Mira qué guardamos, llévate una copia o bórralos.',
              onTap: () => context.push(Routes.myData),
            ),
            SettingsRow(
              icon: Icons.mail_outline_rounded,
              title: 'Escribirnos',
              subtitle: supportEmail,
              onTap: () async {
                await Clipboard.setData(
                  const ClipboardData(text: supportEmail),
                );
                if (context.mounted) {
                  showQToast(context, 'Copiamos $supportEmail');
                }
              },
            ),
          ]),
          const SizedBox(height: AppSpace.xl),
          QButton.secondary(
            label: 'Cerrar sesión',
            icon: Icons.logout_rounded,
            onPressed: signOut,
          ),
          const SizedBox(height: AppSpace.xs),
          QButton.text(
            label: 'Eliminar mi cuenta',
            icon: Icons.delete_outline_rounded,
            color: c.danger,
            onPressed: () => deleteAccountFlow(context, ref),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            'Inti $appVersion · Hecho en Colombia',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: c.inkSubtle),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: AppSpace.xl),
            const SectionHeader('Desarrollo'),
            SettingsRow(
              icon: Icons.palette_outlined,
              title: 'Sistema de diseño',
              subtitle: 'Galería de componentes',
              onTap: () => context.push(Routes.gallery),
            ),
          ],
        ],
      ),
    );
  }
}
