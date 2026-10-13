import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/core/storage/prefs.dart';
import 'package:qullqi/features/home/domain/home_data.dart';
import 'package:qullqi/features/notifications/data/notices.dart';
import 'package:qullqi/features/widgets/domain/widget_snapshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Grupo de apps que comparten la app y sus widgets en iOS.
const String appGroupId = 'group.co.qullqi.qullqi';

/// Nombre del widget principal en iOS (el `kind` del código nativo).
const String iosWidgetKind = 'QullqiWidget';

/// Todos los `kind` de widgets de iOS: hay que refrescarlos juntos.
const List<String> iosWidgetKinds = [
  iosWidgetKind,
  'QullqiPaymentsWidget',
  'QullqiQuickActions',
];

/// Clave en las preferencias con la última foto para los widgets.
const String snapshotPrefsKey = 'widget_snapshot';

/// Puente hacia los widgets del teléfono.
abstract interface class WidgetBridge {
  /// Deja la foto disponible para los widgets y les pide refrescarse.
  Future<void> publish(WidgetSnapshot snapshot);

  /// Borra lo que ven los widgets (al cerrar sesión o bloquear).
  Future<void> clear();
}

/// No hace nada: pruebas y plataformas sin widgets.
class NoopWidgetBridge implements WidgetBridge {
  const NoopWidgetBridge();

  @override
  Future<void> publish(WidgetSnapshot snapshot) async {}

  @override
  Future<void> clear() async {}
}

/// Publica en el grupo compartido (widgets) y en las preferencias (atajos
/// de Siri, que corren dentro de la app y no necesitan el grupo).
class HomeWidgetBridge implements WidgetBridge {
  HomeWidgetBridge(this._prefs);

  final SharedPreferences _prefs;
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    await HomeWidget.setAppGroupId(appGroupId);
    _ready = true;
  }

  Future<void> _refreshAll() async {
    for (final kind in iosWidgetKinds) {
      await HomeWidget.updateWidget(iOSName: kind);
    }
  }

  @override
  Future<void> publish(WidgetSnapshot snapshot) async {
    final json = snapshot.encode();
    await _prefs.setString(snapshotPrefsKey, json);
    try {
      await _init();
      await HomeWidget.saveWidgetData<String>('snapshot', json);
      await _refreshAll();
    } on Object {
      // Sin widgets instalados o sin el grupo (firma gratuita): la app sigue.
    }
  }

  @override
  Future<void> clear() async {
    await _prefs.remove(snapshotPrefsKey);
    try {
      await _init();
      await HomeWidget.saveWidgetData<String>('snapshot', null);
      await _refreshAll();
    } on Object {
      // Igual que arriba.
    }
  }
}

/// El puente real se pone en `main`; por defecto no hace nada.
final widgetBridgeProvider = Provider<WidgetBridge>(
  (ref) => const NoopWidgetBridge(),
);

/// Si los widgets pueden mostrar montos. Se recuerda en el teléfono.
final widgetAmountsProvider = NotifierProvider<WidgetAmountsNotifier, bool>(
  WidgetAmountsNotifier.new,
);

class WidgetAmountsNotifier extends Notifier<bool> {
  static const _key = 'widget_amounts';

  @override
  bool build() => ref.read(sharedPreferencesProvider).getBool(_key) ?? true;

  Future<void> set({required bool show}) async {
    state = show;
    await ref.read(sharedPreferencesProvider).setBool(_key, show);
  }
}

/// La foto que deben ver los widgets ahora; `null` si no hay que mostrar
/// nada (sesión cerrada o bloqueada, o datos aún sin cargar).
final widgetSnapshotProvider = Provider<WidgetSnapshot?>((ref) {
  final status = ref.watch(sessionProvider).status;
  if (status != SessionStatus.unlocked) return null;
  final data = ref.watch(homeDataProvider).value;
  if (data == null) return null;
  return buildWidgetSnapshot(
    data: data,
    unread: ref.watch(unreadNotificationsProvider),
    firstName: ref.watch(currentUserProvider).firstName,
    showAmounts: ref.watch(widgetAmountsProvider),
  );
});
