import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:qullqi/app/router.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:qullqi/core/theme/theme_mode.dart';

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

  @override
  void initState() {
    super.initState();
    // Al salir de la app se anota la hora; al volver después de [lockAfter]
    // se bloquea (protege la plata si alguien toma el teléfono).
    _lifecycle = AppLifecycleListener(
      onHide: () => _hiddenAt = DateTime.now(),
      onShow: () {
        final hidden = _hiddenAt;
        _hiddenAt = null;
        if (hidden != null && DateTime.now().difference(hidden) > lockAfter) {
          ref.read(sessionProvider.notifier).lock();
        }
      },
    );
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
