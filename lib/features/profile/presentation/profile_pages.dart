
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inti/app/routes.dart';
import 'package:inti/core/security/identity.dart';
import 'package:inti/core/security/pin_widgets.dart';
import 'package:inti/core/session/session.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/auth/presentation/validators.dart';
import 'package:inti/features/profile/data/notification_prefs.dart';
import 'package:inti/features/profile/data/push_prefs.dart';
import 'package:inti/features/profile/presentation/profile_page.dart';
import 'package:inti/features/reminders/data/local_notifier.dart';
import 'package:inti/features/reminders/domain/reminders.dart';

/// Editar nombre y celular. El correo es el usuario de la cuenta: se cambia
/// con ayuda (para evitar robos de cuenta).
class EditProfilePage extends ConsumerStatefulWidget {
  const EditProfilePage({super.key});

  @override
  ConsumerState<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends ConsumerState<EditProfilePage> {
  late final AppUser _user = ref.read(currentUserProvider);
  late final _name = TextEditingController(text: _user.fullName);
  late final _phone = TextEditingController(
    text: _user.phone.replaceAll(RegExp(r'^\+57\s*'), '').replaceAll(' ', ''),
  );
  late final _email = TextEditingController(text: _user.email);
  bool _tried = false;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _tried = true);
    if (Validate.name(_name.text) != null ||
        Validate.phone(_phone.text) != null) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(sessionProvider.notifier)
          .update(
            _user.copyWith(
              fullName: _name.text.trim(),
              phone: '+57 ${Validate.formatPhone(_phone.text)}',
            ),
          );
      if (!mounted) return;
      showQToast(context, 'Guardamos tus datos');
      Navigator.of(context).pop();
    } on Object {
      if (!mounted) return;
      setState(() => _saving = false);
      showQToast(context, 'No pudimos guardarlos. Inténtalo de nuevo.');
    }
  }

  /// Si el nombre o el celular cambiaron respecto a lo guardado.
  bool get _changed =>
      _name.text.trim() != _user.fullName ||
      '+57 ${Validate.formatPhone(_phone.text)}' != _user.phone;

  @override
  Widget build(BuildContext context) {
    return DiscardGuard(
      dirty: !_saving && _changed,
      title: '¿Descartar los cambios?',
      confirmLabel: 'Descartar cambios',
      message: 'Tus datos quedan como estaban.',
      child: Scaffold(
        appBar: AppBar(
          leading: const CloseButton(),
          title: const Text('Tus datos'),
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
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.name],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Nombre y apellido',
                  errorText: _tried ? Validate.name(_name.text) : null,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Celular',
                  prefixText: '+57 ',
                  errorText: _tried ? Validate.phone(_phone.text) : null,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              // Solo lectura: el correo largo se lee entero y en su sitio.
              TextField(
                controller: _email,
                readOnly: true,
                enableInteractiveSelection: false,
                maxLines: null,
                decoration: InputDecoration(
                  labelText: 'Correo',
                  suffixIcon: Icon(
                    Icons.lock_outline_rounded,
                    size: AppSize.iconSm,
                    color: context.colors.inkSubtle,
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                'Para cambiar el correo escríbenos a $supportEmail: así '
                'protegemos tu cuenta.',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: AppSpace.xl),
              QButton(
                label: 'Guardar datos',
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

enum _PinStep { current, fresh, confirm }

/// Cambiar el PIN: el actual, el nuevo y confirmarlo.
class ChangePinPage extends ConsumerStatefulWidget {
  const ChangePinPage({super.key});

  @override
  ConsumerState<ChangePinPage> createState() => _ChangePinPageState();
}

class _ChangePinPageState extends ConsumerState<ChangePinPage> {
  _PinStep _step = _PinStep.current;
  String _pin = '';
  String _fresh = '';
  String? _error;
  bool _busy = false;
  int _failed = 0;

  Future<void> _key(String k) async {
    if (_busy) return;
    setState(() {
      _error = null;
      if (k == 'del') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < pinLength) {
        _pin += k;
      }
    });
    if (_pin.length < pinLength) return;
    final identity = ref.read(identityVerifierProvider);
    switch (_step) {
      case _PinStep.current:
        setState(() => _busy = true);
        final ok = await identity.checkPin(_pin);
        if (!mounted) return;
        if (ok) {
          setState(() {
            _busy = false;
            _pin = '';
            _step = _PinStep.fresh;
          });
        } else {
          _failed++;
          unawaited(HapticFeedback.heavyImpact());
          final left = maxPinAttempts - _failed;
          if (left <= 0) {
            showQToast(
              context,
              'Por seguridad pausamos los intentos. Vuelve en unos minutos.',
            );
            Navigator.of(context).pop();
            return;
          }
          setState(() {
            _busy = false;
            _pin = '';
            _error = left == 1
                ? 'PIN incorrecto. Te queda 1 intento.'
                : 'PIN incorrecto. Te quedan $left intentos.';
          });
        }
      case _PinStep.fresh:
        setState(() {
          _fresh = _pin;
          _pin = '';
          _step = _PinStep.confirm;
        });
      case _PinStep.confirm:
        if (_pin != _fresh) {
          unawaited(HapticFeedback.heavyImpact());
          setState(() {
            _pin = '';
            _fresh = '';
            _step = _PinStep.fresh;
            _error = 'Los PIN no coinciden. Escribe el nuevo otra vez.';
          });
          return;
        }
        await identity.setPin(_pin);
        if (!mounted) return;
        showQToast(context, 'Cambiamos tu PIN');
        Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Cambiar PIN')),
      body: SafeArea(
        child: KeypadLayout(
          fields: [
            Text(
              switch (_step) {
                _PinStep.current => 'Escribe tu PIN actual.',
                _PinStep.fresh => 'Escribe tu PIN nuevo.',
                _PinStep.confirm => 'Escríbelo otra vez para confirmar.',
              },
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: AppSpace.lg),
            PinDots(filled: _pin.length, error: _error != null),
            const SizedBox(height: AppSpace.sm),
            PinError(_error),
          ],
          keypad: NumberPad(
            label: 'Teclado del PIN',
            onKey: _key,
            enabled: !_busy,
          ),
          action: Text(
            'Evita fechas o números seguidos como 123456.',
            textAlign: TextAlign.center,
            style: context.text.bodySmall,
          ),
        ),
      ),
    );
  }
}

/// Dispositivos con sesión abierta. La lista real llega del backend.
class DevicesPage extends ConsumerStatefulWidget {
  const DevicesPage({super.key});

  @override
  ConsumerState<DevicesPage> createState() => _DevicesPageState();
}

class _DevicesPageState extends ConsumerState<DevicesPage> {
  bool _othersClosed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dispositivos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.xs,
          AppSpace.gutter,
          AppSpace.xl,
        ),
        children: [
          Text(
            'Si no reconoces alguno, cierra su sesión y cambia tu contraseña.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: AppSpace.md),
          QCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: Column(
              children: [
                const SettingsRow(
                  icon: Icons.smartphone_rounded,
                  title: 'Este teléfono',
                  subtitle: 'Bogotá · ahora',
                  trailing: StatusPill('Activo', tone: PillTone.primary),
                ),
                if (!_othersClosed) ...[
                  const Divider(),
                  const SettingsRow(
                    icon: Icons.tablet_mac_rounded,
                    title: 'iPad',
                    subtitle: 'Medellín · hace 3 días',
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          if (!_othersClosed)
            QButton.secondary(
              label: 'Cerrar sesión en los demás',
              icon: Icons.logout_rounded,
              onPressed: () async {
                final ok = await confirmDestructive(
                  context,
                  title: '¿Cerrar sesión en los demás dispositivos?',
                  message: 'Este teléfono sigue con tu sesión abierta.',
                  confirmLabel: 'Cerrar sesión en los demás',
                );
                if (!ok || !context.mounted) return;
                setState(() => _othersClosed = true);
                showQToast(context, 'Cerramos la sesión en los demás');
              },
            )
          else
            const SectionNote('Solo este teléfono tiene tu sesión abierta.'),
        ],
      ),
    );
  }
}

/// Qué avisos recibir. Los de seguridad siempre llegan.
class NotificationSettingsPage extends ConsumerWidget {
  const NotificationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(noticePrefsProvider);
    final push = ref.watch(pushPrefsProvider);
    final pushNotifier = ref.read(pushPrefsProvider.notifier);

    Future<void> togglePush({required bool enabled}) async {
      if (!enabled) {
        await pushNotifier.setEnabled(enabled: false);
        return;
      }
      final allow = await showQSheet<bool>(
        context,
        title: '¿Recibir avisos en tu teléfono?',
        builder: (sheet) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Te avisamos de pagos, cobros y cosas de seguridad aunque '
              'no tengas Inti abierta. Solo lo que elijas abajo.',
              style: AppTypography.body.copyWith(color: sheet.colors.inkMuted),
            ),
            const SizedBox(height: AppSpace.lg),
            QButton(
              label: 'Permitir avisos',
              onPressed: () => Navigator.of(sheet).pop(true),
            ),
            const SizedBox(height: AppSpace.xs),
            QButton.text(
              label: 'Ahora no',
              onPressed: () => Navigator.of(sheet).pop(false),
            ),
          ],
        ),
      );
      if (!(allow ?? false) || !context.mounted) return;
      final granted = await ref.read(localNotifierProvider).requestPermission();
      await pushNotifier.setEnabled(enabled: granted);
      if (!granted && context.mounted) {
        showQToast(
          context,
          'Activa los avisos de Inti en los ajustes del teléfono.',
        );
      }
    }

    Future<void> sendTest() async {
      final notifier = ref.read(localNotifierProvider);
      final granted = await notifier.requestPermission();
      if (!context.mounted) return;
      if (!granted) {
        showQToast(
          context,
          'Activa los avisos de Inti en los ajustes del teléfono.',
        );
        return;
      }
      await notifier.showNow(
        Reminder(
          id: 1,
          when: DateTime.now(),
          title: 'Paga tu tarjeta Visa en 3 días',
          subtitle: 'Vence en 3 días',
          body: r'Tarjeta Visa •• 4521 · $1.320.000. Así te avisaríamos.',
          route: Routes.home,
          kind: NoticeKind.payments,
        ),
      );
      if (context.mounted) {
        showQToast(context, 'Listo: te enviamos una notificación de prueba.');
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Avisos')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.xs,
          AppSpace.gutter,
          AppSpace.xl,
        ),
        children: [
          const SectionHeader('En tu teléfono'),
          const SizedBox(height: AppSpace.xs),
          QCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchRow(
                  title: 'Avisos como notificación',
                  subtitle: push.enabled
                      ? 'Te llegan aunque no tengas la app abierta.'
                      : 'Actívalos para no perderte un pago.',
                  value: push.enabled,
                  onChanged: (v) => togglePush(enabled: v),
                ),
                if (push.enabled) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No molestar', style: context.text.titleSmall),
                        const SizedBox(height: AppSpace.xs),
                        Wrap(
                          spacing: AppSpace.xs,
                          runSpacing: AppSpace.xs,
                          children: [
                            for (final q in QuietHours.values)
                              ChoiceChip(
                                label: Text(q.label),
                                selected: push.quiet == q,
                                onSelected: (_) => pushNotifier.setQuiet(q),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          push.quiet == QuietHours.off
                              ? 'Te avisamos a cualquier hora.'
                              : 'En ese horario los avisos esperan; los '
                                    'de seguridad siempre suenan.',
                          style: context.text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  QButton.text(
                    label: 'Enviarme una notificación de prueba',
                    icon: Icons.notifications_active_outlined,
                    onPressed: () => unawaited(sendTest()),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          const SectionHeader('Qué avisos quieres'),
          const SizedBox(height: AppSpace.xs),
          QCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
            child: Column(
              children: [
                for (final (i, k) in NoticeKind.values.indexed) ...[
                  if (i > 0) const Divider(),
                  SwitchRow(
                    title: k.title,
                    subtitle: k.description,
                    value: on.contains(k),
                    onChanged: (v) =>
                        ref.read(noticePrefsProvider.notifier).toggle(k, on: v),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpace.md),
          const TrustNote(
            'Los avisos de seguridad (inicios de sesión y movimientos de '
            'plata) siempre llegan.',
          ),
        ],
      ),
    );
  }
}
