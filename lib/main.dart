import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qullqi/app/app.dart';
import 'package:qullqi/app/quick_actions_service.dart';
import 'package:qullqi/core/storage/prefs.dart';
import 'package:qullqi/features/reminders/data/local_notifier.dart';
import 'package:qullqi/features/widgets/data/widget_bridge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widgets, avisos y atajos del ícono existen en el teléfono; en otras
/// plataformas (escritorio, web) la app usa versiones que no hacen nada.
bool get _hasPhoneFeatures =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        if (_hasPhoneFeatures) ...[
          widgetBridgeProvider.overrideWithValue(HomeWidgetBridge(prefs)),
          localNotifierProvider.overrideWithValue(FlutterLocalNotifier()),
          quickActionsProvider.overrideWithValue(PluginQuickActions()),
        ],
      ],
      child: const QullqiApp(),
    ),
  );
}
