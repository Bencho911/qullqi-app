import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:qullqi/app/app.dart';
import 'package:qullqi/core/clock/clock.dart';
import 'package:qullqi/core/data/latency.dart';
import 'package:qullqi/core/security/identity.dart';
import 'package:qullqi/core/session/session.dart';
import 'package:qullqi/core/storage/prefs.dart';
import 'package:qullqi/core/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'contrast.dart';
import 'fonts.dart';

/// Tamaño de un teléfono típico (iPhone 15 / Pixel 8): 390 × 844.
const phone = Size(390, 844);

/// Persona de prueba con sesión abierta.
const testUser = AppUser(
  fullName: 'Camilo Restrepo Gómez',
  email: 'camilo.restrepo@qullqi.app',
  phone: '+57 310 555 0142',
  hasBusiness: true,
);

/// "Hoy" en todas las pruebas: sábado 24 de octubre de 2026, 14:45.
final testNow = DateTime(2026, 10, 24, 14, 45);

Future<SharedPreferences> _prefs(Map<String, Object> values) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void _setView(WidgetTester tester, Size size) {
  tester.view
    ..devicePixelRatio = 2
    ..physicalSize = size * 2;
  addTearDown(tester.view.reset);
}

MediaQueryData _media(WidgetTester tester, double textScale) =>
    MediaQueryData.fromView(tester.view).copyWith(
      textScaler: TextScaler.linear(textScale),
      disableAnimations: true,
    );

/// Monta la app completa (router, pestañas) como en el teléfono.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
  Size size = phone,
  Map<String, Object> prefs = const {},
  List<Override> overrides = const [],
  bool settle = true,
  bool signedIn = true,
  bool lockOnStart = false,
}) async {
  await loadAppFonts();
  _setView(tester, size);
  final container = ProviderContainer(
    // Sin reintentos automáticos: un error queda a la vista de la prueba.
    retry: (_, _) => null,
    overrides: [
      sharedPreferencesProvider.overrideWithValue(
        await _prefs({
          'theme_mode': mode.name,
          if (signedIn) 'session_user': jsonEncode(testUser.toJson()),
          ...prefs,
        }),
      ),
      lockOnStartProvider.overrideWithValue(lockOnStart),
      identityVerifierProvider.overrideWithValue(
        MockIdentityVerifier(latency: Duration.zero),
      ),
      clockProvider.overrideWithValue(() => testNow),
      mockLatencyProvider.overrideWithValue(Duration.zero),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: _media(tester, textScale),
        child: const QullqiApp(),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
  return container;
}

/// Monta una sola pantalla con el tema de la app.
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
  Size size = phone,
}) async {
  await loadAppFonts();
  _setView(tester, size);
  final prefs = await _prefs(const {});
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MediaQuery(
        data: _media(tester, textScale),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          locale: const Locale('es', 'CO'),
          supportedLocales: const [Locale('es', 'CO')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: screen,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Revisa la accesibilidad de lo que hay en pantalla: áreas táctiles de iOS y
/// Android, controles con nombre y contraste de cada texto contra su fondo.
///
/// El contraste usa nuestro verificador (`contrast.dart`): la guía de Flutter
/// ubica mal los textos dentro de listas con barra superior y mide otro sitio.
Future<void> expectAccessible(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectTextContrast(tester);
}

/// Busca un widget `Semantics` por su etiqueta exacta.
Finder semanticsLabel(String label) => find.byWidgetPredicate(
  (w) => w is Semantics && w.properties.label == label,
);

/// Desplaza hasta que [f] quede en el centro de la pantalla (no escondido
/// bajo la barra superior fija) y espera a que termine.
Future<void> scrollIntoView(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await Scrollable.ensureVisible(tester.element(f.first), alignment: 0.5);
  await tester.pumpAndSettle();
}
