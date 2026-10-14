# Widgets, notificaciones y atajos

Qué hay, cómo se instala y qué límites tiene. Lo nativo de iOS **no se pudo
compilar ni ver en Windows**: está escrito con cuidado, pero la primera corrida
en Codemagic puede pedir 1–3 ajustes mirando el log.

## Qué incluye

| Pieza | Dónde | Estado de la verificación |
| --- | --- | --- |
| Foto de datos para widgets (`WidgetSnapshot`) | `lib/features/widgets/` | Pruebas Dart ✔ |
| Recordatorios locales con diseño y acciones | `lib/features/reminders/` | Pruebas Dart ✔ |
| Atajos del ícono (mantener pulsado) | `lib/app/quick_actions_service.dart` | Pruebas Dart ✔ |
| Enlaces `inti:///atajo/<id>` | `lib/app/shortcuts.dart` | Pruebas Dart ✔ |
| Widgets SwiftUI (3) | `ios/IntiWidget/` | **Sin compilar** |
| Atajos de Siri / app Atajos (App Intents) | `ios/Runner/IntiShortcuts.swift` | **Sin compilar** |
| Script que añade la extensión al proyecto | `ios/scripts/add_widget_extension.rb` | **Sin ejecutar** |

## Widgets

- **Disponible para gastar**: pequeño y mediano (inicio) + rectangular,
  circular y en línea (pantalla de bloqueo).
- **Próximos pagos**: mediano y grande.
- **Atajos**: mediano, con Gasto / Mover / Escanear / Avisos.

Privacidad: si ocultas los montos en la app (Perfil → "Mostrar montos en los
widgets"), los widgets muestran "Abre Inti". Los montos usan
`.privacySensitive()`, así que iOS los oculta también en la pantalla de bloqueo
cuando corresponde.

## Atajos de Siri

Frases (di "Oye Siri, …"): "Cuánto puedo gastar en Inti", "Registrar un gasto
en Inti", "Mover plata en Inti", "Escanear una factura en Inti", "Mis
próximos pagos en Inti". También aparecen en la app Atajos y en Spotlight.

"¿Cuánto puedo gastar?" responde en voz alta sin abrir la app, leyendo la
última foto que la app dejó. Los demás abren la app en la pantalla pedida.

## Instalar (con widgets)

1. Sube el repo a GitHub (ya está conectado a Codemagic).
2. En Codemagic elige el flujo **"iPhone con widgets y atajos (experimental)"**.
3. Descarga `Inti-widgets.ipa` e instálalo con Sideloadly.
4. Mantén pulsada la pantalla de inicio → `+` → Inti para añadir widgets.

Si ese flujo falla o Sideloadly rechaza el paquete, usa **"iPhone (sin
firmar)"**: es la app completa, sin widgets ni atajos de Siri (los atajos del
ícono y las notificaciones locales sí funcionan).

## Límites que debes conocer

- **Apple ID gratuito + Sideloadly**: los App Groups y las extensiones pueden
  fallar al firmar o consumir más de tu cupo de App IDs (límite semanal). Es la
  causa más probable de problemas, no el código.
- **Notificaciones push remotas** (desde un servidor) requieren cuenta de
  Apple Developer de pago. Las **locales programadas** (vencimientos, avisos
  diarios) no la necesitan y ya funcionan.
- Los widgets no se actualizan en tiempo real: la app los refresca cuando
  cambian los datos y iOS los relee cada ~30 minutos como máximo.
- Los atajos de Siri necesitan iOS 16 o superior.
- Las notificaciones con imágenes o botones personalizados remotos necesitan
  una *Notification Service Extension* y APNs: pendiente hasta tener backend.

## Si algo falla

- *"No such module 'WidgetKit'"*, o error de firma en la extensión → pega el
  log de Codemagic y lo ajusto.
- El widget sale en blanco → abre la app una vez (deja la primera foto).
- Siri dice "abre Inti una vez" → igual: abre la app y vuelve a intentarlo.
