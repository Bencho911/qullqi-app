import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:inti/core/security/confirm_identity.dart';
import 'package:inti/core/security/identity.dart';
import 'package:inti/core/session/session.dart';
import 'package:inti/core/widgets/widgets.dart';

/// Eliminar la cuenta: confirma la decisión, pide el PIN y cierra la sesión.
/// Lo usan Perfil y "Mis datos".
Future<void> deleteAccountFlow(BuildContext context, WidgetRef ref) async {
  final sure = await confirmDestructive(
    context,
    title: '¿Eliminar tu cuenta de Inti?',
    message:
        'Borramos tus datos, revocamos los permisos con tus bancos y '
        'cerramos tu sesión. No se puede deshacer.',
    confirmLabel: 'Eliminar mi cuenta',
    cancelLabel: 'Conservar mi cuenta',
  );
  if (!sure || !context.mounted) return;
  final ok = await confirmIdentity(
    context,
    reason: 'Confirma que quieres eliminar tu cuenta.',
    pinOnly: true,
  );
  if (!ok) return;
  await ref.read(identityVerifierProvider).clearPin();
  await ref.read(sessionProvider.notifier).signOut();
}
