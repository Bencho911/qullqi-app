import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

import 'package:qullqi/app/shortcuts.dart';

/// Atajos que salen al mantener presionado el ícono de la app.
abstract interface class QuickActionsService {
  /// Los registra; [onAction] recibe el identificador del que se tocó.
  Future<void> init(void Function(String id) onAction);
}

/// No hace nada: pruebas y plataformas sin atajos.
class NoopQuickActions implements QuickActionsService {
  const NoopQuickActions();

  @override
  Future<void> init(void Function(String id) onAction) async {}
}

/// Con el paquete `quick_actions` (iOS y Android).
class PluginQuickActions implements QuickActionsService {
  @override
  Future<void> init(void Function(String id) onAction) async {
    const actions = QuickActions();
    await actions.initialize(onAction);
    await actions.setShortcutItems([
      for (final q in AppShortcuts.quickActions)
        ShortcutItem(type: q.id, localizedTitle: q.title),
    ]);
  }
}

/// El servicio real se pone en `main`; por defecto no hace nada.
final quickActionsProvider = Provider<QuickActionsService>(
  (ref) => const NoopQuickActions(),
);
