import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inti/core/security/identity.dart';
import 'package:inti/core/security/pin_widgets.dart';
import 'package:inti/core/theme/app_theme.dart';
import 'package:inti/core/theme/app_tokens.dart';
import 'package:inti/core/theme/app_typography.dart';
import 'package:inti/core/widgets/widgets.dart';

/// Pide confirmar la identidad antes de una acción sensible.
///
/// Ofrece huella o Face ID y, como respaldo, el PIN. Con [pinOnly] solo
/// acepta el PIN (montos altos). Devuelve `true` si se confirmó.
Future<bool> confirmIdentity(
  BuildContext context, {
  required String reason,
  bool pinOnly = false,
  String pinOnlyNote = 'Por seguridad, escribe tu PIN de Inti.',
}) async {
  final outcome = await showQSheet<_Outcome>(
    context,
    title: 'Confirma que eres tú',
    builder: (context) => _ConfirmBody(
      reason: reason,
      pinOnly: pinOnly,
      pinOnlyNote: pinOnlyNote,
    ),
  );
  if (outcome == _Outcome.locked && context.mounted) {
    showQToast(
      context,
      'Por seguridad pausamos los intentos. Espera unos minutos y vuelve a '
      'intentarlo.',
    );
  }
  return outcome == _Outcome.confirmed;
}

enum _Outcome { confirmed, locked }

class _ConfirmBody extends ConsumerStatefulWidget {
  const _ConfirmBody({
    required this.reason,
    required this.pinOnly,
    required this.pinOnlyNote,
  });

  final String reason;
  final bool pinOnly;

  /// Por qué solo se acepta el PIN (lo que lee la persona).
  final String pinOnlyNote;

  @override
  ConsumerState<_ConfirmBody> createState() => _ConfirmBodyState();
}

class _ConfirmBodyState extends ConsumerState<_ConfirmBody> {
  String _pin = '';
  int _failed = 0;
  bool _busy = false;
  String? _error;

  IdentityVerifier get _verifier => ref.read(identityVerifierProvider);

  Future<void> _biometrics() async {
    setState(() => _busy = true);
    final ok = await _verifier.verifyBiometrics(widget.reason);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      unawaited(HapticFeedback.mediumImpact());
      Navigator.of(context).pop(_Outcome.confirmed);
    } else {
      setState(() => _error = 'No te reconocimos. Usa tu PIN.');
    }
  }

  Future<void> _digit(String key) async {
    if (_busy) return;
    setState(() {
      _error = null;
      if (key == 'del') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
      } else if (_pin.length < pinLength) {
        _pin += key;
      }
    });
    unawaited(HapticFeedback.selectionClick());
    if (_pin.length < pinLength) return;

    setState(() => _busy = true);
    final ok = await _verifier.checkPin(_pin);
    if (!mounted) return;
    if (ok) {
      unawaited(HapticFeedback.mediumImpact());
      Navigator.of(context).pop(_Outcome.confirmed);
      return;
    }
    _failed++;
    unawaited(HapticFeedback.heavyImpact());
    final left = maxPinAttempts - _failed;
    if (left <= 0) {
      Navigator.of(context).pop(_Outcome.locked);
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

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.reason,
          style: AppTypography.body.copyWith(color: c.inkMuted),
        ),
        const SizedBox(height: AppSpace.lg),
        if (!widget.pinOnly) ...[
          QButton(
            label: 'Usar huella o Face ID',
            icon: Icons.fingerprint_rounded,
            loading: _busy && _pin.isEmpty,
            loadingLabel: 'Esperando tu huella',
            onPressed: _biometrics,
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            'O escribe tu PIN',
            textAlign: TextAlign.center,
            style: context.text.bodySmall,
          ),
        ] else
          Text(
            widget.pinOnlyNote,
            textAlign: TextAlign.center,
            style: context.text.bodySmall,
          ),
        const SizedBox(height: AppSpace.sm),
        PinDots(filled: _pin.length, error: _error != null),
        const SizedBox(height: AppSpace.sm),
        PinError(_error),
        const SizedBox(height: AppSpace.xs),
        NumberPad(label: 'Teclado del PIN', onKey: _digit, enabled: !_busy),
      ],
    );
  }
}
