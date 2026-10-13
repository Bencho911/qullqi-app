import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/app/quick_actions_service.dart';
import 'package:qullqi/app/router.dart';
import 'package:qullqi/app/shortcuts.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/core/storage/prefs.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/theme_mode.dart';
import 'package:qullqi/features/reminders/data/local_notifier.dart';
import 'package:qullqi/features/widgets/data/widget_bridge.dart';

/// Tiempo en segundo plano tras el cual la app pide desbloquear.
const Duration lockAfter = Duration(minutes: 1);

class QullqiApp extends ConsumerStatefulWidget {
  const QullqiApp({super.key});

  @override
  ConsumerState<QullqiApp> createState() => _QullqiAppState();
}

class _QullqiAppState extends ConsumerState<QullqiApp> {
  late final AppLifecycleListener _lifecycle;
  DateTime? _hiddenAt;

  /// Firma de lo último programado, para no reprogramar lo mismo.
  String? _lastPlan;

  @override
  void initState() {
    super.initState();
    // Al salir de la app se anota la hora; al volver después de [lockAfter]
    // se bloquea (protege la plata si alguien toma el teléfono).
    _lifecycle = AppLifecycleListener(
      onHide: () => _hiddenAt = DateTime.now(),
      onResume: () => unawaited(_openPendingShortcut()),
      onShow: () {
        final hidden = _hiddenAt;
        _hiddenAt = null;
        if (hidden != null && DateTime.now().difference(hidden) > lockAfter) {
          ref.read(sessionProvider.notifier).lock();
        }
      },
    );

    // Lo que ven los widgets sigue a lo que ve la persona.
    ref
      ..listenManual(widgetSnapshotProvider, (_, next) {
        if (next == null) return;
        unawaited(ref.read(widgetBridgeProvider).publish(next));
      }, fireImmediately: true)
      // Sin sesión abierta los widgets no muestran nada.
      ..listenManual(sessionProvider, (_, next) {
        if (next.status != SessionStatus.unlocked) {
          unawaited(ref.read(widgetBridgeProvider).clear());
        }
      })
      ..listenManual(reminderPlanProvider, (_, plan) {
        if (plan == null) return;
        final signature = [for (final r in plan) '${r.id}@${r.when}'].join(',');
        if (signature == _lastPlan) return;
        _lastPlan = signature;
        unawaited(ref.read(localNotifierProvider).replaceAll(plan));
      }, fireImmediately: true);

    WidgetsBinding.instance.addPostFrameCallback((_) => _bootNative());
  }

  /// Prepara lo que depende del teléfono: notificaciones, atajos del ícono
  /// y atajos pendientes de Siri.
  Future<void> _bootNative() async {
    final router = ref.read(routerProvider);
    try {
      await ref
          .read(localNotifierProvider)
          .init(onOpen: (route) => openFromOutside(router, route));
      await ref.read(quickActionsProvider).init((id) {
        final route = AppShortcuts.routeFor(id);
        if (route != null) openFromOutside(router, route);
      });
    } on Object {
      // Sin soporte en esta plataforma: la app funciona igual.
    }
    await _openPendingShortcut();
  }

  /// Siri y la app Atajos dejan anotado qué abrir; aquí se lee y se abre.
  Future<void> _openPendingShortcut() async {
    final prefs = ref.read(sharedPreferencesProvider);
    try {
      await prefs.reload();
    } on Object {
      return;
    }
    final id = prefs.getString(pendingShortcutKey);
    if (id == null) return;
    await prefs.remove(pendingShortcutKey);
    final route = AppShortcuts.routeFor(id);
    if (route != null && mounted) {
      openFromOutside(ref.read(routerProvider), route);
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Qullqi',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
