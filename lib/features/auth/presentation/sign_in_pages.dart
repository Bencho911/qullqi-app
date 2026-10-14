import 'dart:async';

import 'package:flutter/material.dart';
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
import 'package:inti/features/auth/presentation/sign_up_pages.dart';
import 'package:inti/features/auth/presentation/validators.dart';

/// Ingresar con correo y contraseña.
class SignInPage extends ConsumerStatefulWidget {
  const SignInPage({super.key});

  @override
  ConsumerState<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends ConsumerState<SignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _show = false;
  bool _tried = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _tried = true;
      _error = null;
    });
    if (Validate.email(_email.text) != null || _password.text.isEmpty) return;
    setState(() => _busy = true);
    try {
      final user = await ref
          .read(authRepositoryProvider)
          .signIn(email: _email.text, password: _password.text);
      final identity = ref.read(identityVerifierProvider);
      if (await identity.hasPin()) {
        await ref.read(sessionProvider.notifier).open(user);
      } else {
        // Teléfono nuevo: primero crea su PIN.
        ref.read(pendingUserProvider.notifier).set(user);
        if (mounted) await context.push(Routes.createPin);
      }
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
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Ingresar')),
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
              Semantics(
                header: true,
                child: Text('Hola de nuevo', style: context.text.headlineSmall),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                'Ingresa con el correo de tu cuenta.',
                style: AppTypography.body.copyWith(color: c.inkMuted),
              ),
              const SizedBox(height: AppSpace.lg),
              if (_error != null) ...[
                QBanner(
                  tone: BannerTone.danger,
                  title: 'No pudimos ingresar',
                  message: _error!,
                ),
                const SizedBox(height: AppSpace.md),
              ],
              TextField(
                controller: _email,
                autofillHints: const [AutofillHints.email],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Correo',
                  errorText: _tried ? Validate.email(_email.text) : null,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _password,
                autofillHints: const [AutofillHints.password],
                obscureText: !_show,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _signIn(),
                decoration: InputDecoration(
                  labelText: 'Contraseña',
                  errorText: _tried && _password.text.isEmpty
                      ? 'Escribe tu contraseña.'
                      : null,
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
              Align(
                alignment: Alignment.centerRight,
                child: QButton.text(
                  label: '¿Olvidaste tu contraseña?',
                  onPressed: () => context.push(Routes.resetPassword),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              QButton(
                label: 'Ingresar',
                loading: _busy,
                loadingLabel: 'Ingresando',
                onPressed: _signIn,
              ),
              const SizedBox(height: AppSpace.xs),
              Center(
                child: QButton.text(
                  label: 'Crear cuenta',
                  onPressed: () => context.pushReplacement(Routes.signUp),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Recuperar la contraseña con un enlace al correo.
class ResetPasswordPage extends ConsumerStatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  ConsumerState<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends ConsumerState<ResetPasswordPage> {
  final _email = TextEditingController();
  bool _tried = false;
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() => _tried = true);
    if (Validate.email(_email.text) != null) return;
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(_email.text);
      if (mounted) setState(() => _sent = true);
    } on Object {
      if (mounted) {
        showQToast(context, 'No pudimos enviarlo. Inténtalo de nuevo.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Recuperar contraseña')),
      body: SafeArea(
        child: _sent
            ? MessageBody(
                child: EmptyState(
                  icon: Icons.mark_email_read_outlined,
                  title: 'Revisa tu correo',
                  message:
                      'Si hay una cuenta con ${_email.text.trim()}, te llega '
                      'un enlace para crear una contraseña nueva.',
                  actionLabel: 'Volver a ingresar',
                  onAction: () => context.pop(),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter,
                  AppSpace.xs,
                  AppSpace.gutter,
                  AppSpace.xl,
                ),
                children: [
                  Text(
                    'Escribe el correo de tu cuenta y te enviamos un enlace '
                    'para crear una contraseña nueva.',
                    style: AppTypography.body.copyWith(color: c.inkMuted),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  TextField(
                    controller: _email,
                    autofocus: true,
                    autofillHints: const [AutofillHints.email],
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Correo',
                      errorText: _tried ? Validate.email(_email.text) : null,
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  QButton(
                    label: 'Enviar enlace',
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

/// Desbloquear la app: huella o Face ID, o el PIN.
class LockPage extends ConsumerStatefulWidget {
  const LockPage({super.key});

  @override
  ConsumerState<LockPage> createState() => _LockPageState();
}

class _LockPageState extends ConsumerState<LockPage> {
  String _pin = '';
  int _failed = 0;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Si la persona activó la biometría, se pide al abrir.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(biometricsEnabledProvider)) {
        unawaited(_biometrics());
      }
    });
  }

  Future<void> _biometrics() async {
    final ok = await ref
        .read(identityVerifierProvider)
        .verifyBiometrics('Desbloquea Inti');
    if (ok && mounted) ref.read(sessionProvider.notifier).unlock();
  }

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
    setState(() => _busy = true);
    final ok = await ref.read(identityVerifierProvider).checkPin(_pin);
    if (!mounted) return;
    if (ok) {
      ref.read(sessionProvider.notifier).unlock();
      return;
    }
    _failed++;
    final left = maxPinAttempts - _failed;
    setState(() {
      _busy = false;
      _pin = '';
      _error = left <= 0
          ? 'Por seguridad, ingresa de nuevo con tu correo.'
          : left == 1
          ? 'PIN incorrecto. Te queda 1 intento.'
          : 'PIN incorrecto. Te quedan $left intentos.';
    });
    if (left <= 0) await _signOut();
  }

  Future<void> _signOut() async {
    await ref.read(identityVerifierProvider).clearPin();
    await ref.read(sessionProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final user = ref.watch(currentUserProvider);
    final biometrics = ref.watch(biometricsEnabledProvider);
    return Scaffold(
      body: SafeArea(
        child: KeypadLayout(
          fields: [
            const SizedBox(height: AppSpace.xl),
            const Center(child: IntiMark(size: AppSize.avatarLg)),
            const SizedBox(height: AppSpace.md),
            Semantics(
              header: true,
              child: Text(
                'Hola, ${user.firstName}',
                textAlign: TextAlign.center,
                style: context.text.headlineSmall,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Escribe tu PIN para entrar.',
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(color: c.inkMuted),
            ),
            const SizedBox(height: AppSpace.lg),
            PinDots(filled: _pin.length, error: _error != null),
            const SizedBox(height: AppSpace.sm),
            PinError(_error),
            if (biometrics)
              Center(
                child: QButton.text(
                  label: 'Usar huella o Face ID',
                  icon: Icons.fingerprint_rounded,
                  onPressed: _biometrics,
                ),
              ),
          ],
          keypad: NumberPad(
            label: 'Teclado del PIN',
            onKey: _key,
            enabled: !_busy,
          ),
          action: QButton.text(
            label: '¿No eres ${user.firstName}? Cerrar sesión',
            onPressed: _signOut,
          ),
        ),
      ),
    );
  }
}
