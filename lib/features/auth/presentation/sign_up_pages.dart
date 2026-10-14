import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:inti/app/routes.dart';
import 'package:inti/core/security/biometrics_pref.dart';
import 'package:inti/core/security/identity.dart';
import 'package:inti/core/security/pin_widgets.dart';
import 'package:inti/core/session/session.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/widgets.dart';
import 'package:inti/features/auth/data/auth_repository.dart';
import 'package:inti/features/auth/presentation/validators.dart';

/// Persona ya verificada que aún no crea su PIN (registro o nuevo teléfono).
final pendingUserProvider = NotifierProvider<PendingUserNotifier, AppUser?>(
  PendingUserNotifier.new,
);

class PendingUserNotifier extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  // Los notifiers de Riverpod exponen el cambio como método, no como setter.
  // ignore: use_setters_to_change_properties
  void set(AppUser? u) => state = u;
}

/// Encabezado de cada paso del acceso: "Paso 1 de 3" + título + ayuda.
class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.title, required this.text, this.step});

  final String title;
  final String text;
  final int? step;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (step != null)
          Text('Paso $step de 3', style: context.text.bodySmall),
        Semantics(
          header: true,
          child: Text(title, style: context.text.headlineSmall),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(text, style: AppTypography.body.copyWith(color: c.inkMuted)),
        const SizedBox(height: AppSpace.lg),
      ],
    );
  }
}

/// Paso 1: nombre, correo, contraseña y si tiene negocio.
class SignUpPage extends ConsumerStatefulWidget {
  const SignUpPage({super.key});

  @override
  ConsumerState<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends ConsumerState<SignUpPage> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _show = false;
  bool _business = false;
  bool _accepted = false;
  bool _tried = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _valid =>
      Validate.name(_name.text) == null &&
      Validate.email(_email.text) == null &&
      Validate.password(_password.text) == null &&
      _accepted;

  Future<void> _continue() async {
    setState(() {
      _tried = true;
      _error = null;
    });
    if (!_valid) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .startSignUp(
            fullName: _name.text,
            email: _email.text,
            password: _password.text,
            hasBusiness: _business,
          );
      if (mounted) await context.push(Routes.signUpPhone);
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } on Object {
      // Una falla de conexión es un aviso pasajero, como en el resto de la
      // app; en la página quedan solo las respuestas sobre los datos.
      if (mounted) {
        showQToast(context, 'Se perdió la conexión. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strength = PasswordStrength.of(_password.text);
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: AutofillGroup(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.xs,
              AppSpace.gutter,
              AppSpace.xl,
            ),
            children: [
              const _StepHeader(
                step: 1,
                title: 'Cuéntanos de ti',
                text: 'Con esto creamos tu cuenta. Tus datos son tuyos.',
              ),
              if (_error != null) ...[
                QBanner(
                  tone: BannerTone.danger,
                  title: 'No pudimos crear la cuenta',
                  message: _error!,
                ),
                const SizedBox(height: AppSpace.md),
              ],
              TextField(
                controller: _name,
                autofillHints: const [AutofillHints.name],
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Nombre y apellido',
                  errorText: _tried ? Validate.name(_name.text) : null,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _email,
                autofillHints: const [AutofillHints.email],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Correo',
                  hintText: 'tu@correo.com',
                  errorText: _tried ? Validate.email(_email.text) : null,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _password,
                autofillHints: const [AutofillHints.newPassword],
                obscureText: !_show,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  helperText: _password.text.isEmpty
                      ? 'Mínimo 8 caracteres.'
                      : 'Seguridad: ${strength.label}',
                  errorText: _tried ? Validate.password(_password.text) : null,
                  suffixIcon: IconButton(
                    tooltip: _show
                        ? 'Ocultar contraseña'
                        : 'Mostrar contraseña',
                    icon: Icon(
                      _show
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () => setState(() => _show = !_show),
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              QCard(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
                child: SwitchRow(
                  title: 'También tengo negocio o soy independiente',
                  subtitle: 'Separamos tu plata personal de la del negocio.',
                  value: _business,
                  onChanged: (v) => setState(() => _business = v),
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              CheckRow(
                value: _accepted,
                onChanged: (v) => setState(() => _accepted = v),
                label:
                    'Acepto los términos y autorizo el tratamiento de mis '
                    'datos según la Ley 1581 de Habeas Data.',
              ),
              if (_tried && !_accepted)
                Text(
                  'Acepta los términos para continuar.',
                  style: AppTypography.label.copyWith(
                    color: context.colors.onDangerContainer,
                  ),
                ),
              const SizedBox(height: AppSpace.lg),
              QButton(
                label: 'Continuar',
                loading: _busy,
                loadingLabel: 'Creando tu cuenta',
                onPressed: _continue,
              ),
              const SizedBox(height: AppSpace.xs),
              Center(
                child: QButton.text(
                  label: 'Ya tengo cuenta',
                  onPressed: () => context.pushReplacement(Routes.signIn),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paso 2: celular para el código por SMS.
class PhonePage extends ConsumerStatefulWidget {
  const PhonePage({super.key});

  @override
  ConsumerState<PhonePage> createState() => _PhonePageState();
}

class _PhonePageState extends ConsumerState<PhonePage> {
  final _phone = TextEditingController();
  bool _tried = false;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _tried = true);
    if (Validate.phone(_phone.text) != null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(authRepositoryProvider)
          .sendCode(Validate.formatPhone(_phone.text));
      if (mounted) {
        await context.push(
          Routes.signUpCode,
          extra: Validate.formatPhone(_phone.text),
        );
      }
    } on Object {
      if (mounted) {
        showQToast(context, 'No pudimos enviar el SMS. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.xs,
            AppSpace.gutter,
            AppSpace.xl,
          ),
          children: [
            const _StepHeader(
              step: 2,
              title: 'Tu celular',
              text:
                  'Te enviamos un código por SMS para confirmar que eres tú. '
                  'Lo usamos para proteger tu cuenta.',
            ),
            TextField(
              controller: _phone,
              autofocus: true,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Celular',
                prefixText: '+57 ',
                hintText: '310 555 0142',
                errorText: _tried ? Validate.phone(_phone.text) : null,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            QButton(
              label: 'Enviar código',
              loading: _busy,
              loadingLabel: 'Enviando',
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}

/// Segundos para poder pedir otro código.
const int _resendSeconds = 30;

/// Paso 3: el código de 6 dígitos que llegó por SMS.
/// Espacio entre las cifras del código SMS: se leen de a una.
const double _codeTracking = 8;

class CodePage extends ConsumerStatefulWidget {
  const CodePage({required this.phone, super.key});

  final String phone;

  @override
  ConsumerState<CodePage> createState() => _CodePageState();
}

class _CodePageState extends ConsumerState<CodePage> {
  final _code = TextEditingController();
  String? _error;
  bool _busy = false;
  int _wait = _resendSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _wait = _resendSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_code.text.length != 6) {
      setState(() => _error = 'El código tiene 6 dígitos.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .verifyCode(_code.text);
      ref.read(pendingUserProvider.notifier).set(user);
      if (mounted) await context.push(Routes.createPin);
    } on AuthFailure catch (e) {
      setState(() => _error = e.message);
    } on Object {
      // Una falla de conexión es un aviso pasajero, como en el resto de la
      // app; en la página quedan solo las respuestas sobre los datos.
      if (mounted) {
        showQToast(context, 'Se perdió la conexión. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    try {
      await ref.read(authRepositoryProvider).sendCode(widget.phone);
      if (!mounted) return;
      showQToast(context, 'Te enviamos un código nuevo');
      _startTimer();
    } on Object {
      if (!mounted) return;
      showQToast(context, 'No pudimos enviarlo. Inténtalo de nuevo.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.xs,
            AppSpace.gutter,
            AppSpace.xl,
          ),
          children: [
            _StepHeader(
              step: 3,
              title: 'Escribe el código',
              text: 'Lo enviamos por SMS al +57 ${widget.phone}.',
            ),
            TextField(
              controller: _code,
              autofocus: true,
              autofillHints: const [AutofillHints.oneTimeCode],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: AppTypography.title.copyWith(letterSpacing: _codeTracking),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onChanged: (v) {
                setState(() => _error = null);
                if (v.length == 6) unawaited(_verify());
              },
              decoration: InputDecoration(
                labelText: 'Código de 6 dígitos',
                errorText: _error,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            QButton(
              label: 'Verificar',
              loading: _busy,
              loadingLabel: 'Verificando',
              onPressed: _verify,
            ),
            const SizedBox(height: AppSpace.xs),
            Center(
              child: QButton.text(
                label: _wait > 0
                    ? 'Pedir otro código en $_wait s'
                    : 'Pedir otro código',
                onPressed: _wait > 0 ? null : _resend,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Crear el PIN (dos veces) y activar la huella o Face ID.
class CreatePinPage extends ConsumerStatefulWidget {
  const CreatePinPage({super.key});

  @override
  ConsumerState<CreatePinPage> createState() => _CreatePinPageState();
}

class _CreatePinPageState extends ConsumerState<CreatePinPage> {
  String _first = '';
  String _pin = '';
  bool _confirming = false;
  String? _error;

  Future<void> _key(String k) async {
    setState(() {
      _error = null;
      if (k == 'del') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < pinLength) {
        _pin += k;
      }
    });
    if (_pin.length < pinLength) return;
    if (!_confirming) {
      setState(() {
        _first = _pin;
        _pin = '';
        _confirming = true;
      });
      return;
    }
    if (_pin != _first) {
      unawaited(HapticFeedback.heavyImpact());
      setState(() {
        _pin = '';
        _first = '';
        _confirming = false;
        _error = 'Los PIN no coinciden. Créalo de nuevo.';
      });
      return;
    }
    await _finish();
  }

  Future<void> _finish() async {
    final identity = ref.read(identityVerifierProvider);
    await identity.setPin(_pin);
    final user = ref.read(pendingUserProvider);
    if (!mounted || user == null) return;
    if (await identity.hasBiometrics() && mounted) {
      final enable = await showQSheet<bool>(
        context,
        title: '¿Entras con tu huella o Face ID?',
        builder: (context) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Es más rápido que el PIN y igual de seguro. Puedes cambiarlo '
              'en tu perfil.',
              style: AppTypography.body.copyWith(
                color: context.colors.inkMuted,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            QButton(
              label: 'Activar huella o Face ID',
              icon: Icons.fingerprint_rounded,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: AppSpace.xs),
            QButton.secondary(
              label: 'Ahora no',
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      );
      await ref
          .read(biometricsEnabledProvider.notifier)
          .set(enabled: enable ?? false);
    }
    ref.read(pendingUserProvider.notifier).set(null);
    await ref.read(sessionProvider.notifier).open(user);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Crea tu PIN')),
      body: SafeArea(
        child: KeypadLayout(
          fields: [
            Text(
              _confirming
                  ? 'Escríbelo otra vez para confirmar.'
                  : 'Con estos 6 dígitos abres la app y confirmas cuando '
                        'mueves plata.',
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: AppSpace.lg),
            PinDots(filled: _pin.length, error: _error != null),
            const SizedBox(height: AppSpace.sm),
            PinError(_error),
          ],
          keypad: NumberPad(label: 'Teclado del PIN', onKey: _key),
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
