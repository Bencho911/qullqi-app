import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inti/app/app.dart';
import 'package:inti/app/quick_actions_service.dart';
import 'package:inti/core/storage/prefs.dart';
import 'package:inti/features/reminders/data/local_notifier.dart';
import 'package:inti/features/widgets/data/widget_bridge.dart';
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
      child: const IntiApp(),
    ),
  );
}
