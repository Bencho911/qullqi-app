# Inti: front completo antes del backend

Todo corre con datos de demostración detrás de las mismas interfaces
(`*Repository`) que usará el backend. Cada hito terminó con: pruebas,
capturas claro/oscuro, texto al 200 %, guías de accesibilidad y analizador
limpio.

## Hecho

| Hito | Qué |
|---|---|
| 0–10 | Sistema de diseño, cuentas, movimientos, mover plata, planes, negocio, avisos, extractos, seguridad |
| Inversiones | Resumen, registro manual y conectado, simulador y avisos de vencimiento |
| 11 | Pagos recurrentes, cómo va tu mes, reglas de categorías y cobros raros |
| 12 | Historial de patrimonio y plan de deudas |
| 13 | Calendario tributario de referencia, 4x1000 y resumen para la renta |
| 14 | Cotizaciones, facturas recurrentes, enlaces de pago, conciliación, cuentas por pagar y contador |
| 15 | Grupos con gastos compartidos, dividir una cuenta, deudas entre personas y metas compartidas |
| 16 | Mis datos (copia y borrado), resúmenes semanal y mensual, cuentas en otras monedas y avisos en el teléfono |

## Lo que el backend tiene que reemplazar (hoy es de demostración)

| Pieza | Hoy | Backend |
|---|---|---|
| Cuentas, movimientos, saldos | Repositorios en memoria | Agregador de datos bancarios y libro de movimientos |
| Tasas de cambio | Valores fijos (`ExchangeRates`) | TRM y tasas del día |
| Fechas de impuestos | Mecánica de referencia por documento | Calendario oficial de la DIAN por año |
| Enlaces de pago | Estados simulados | Aliado de pagos autorizado |
| Invitación al contador | Solo la lista | Correo, aceptación y permisos de solo lectura |
| Grupos, metas y deudas compartidas | Una sola persona anota todo | Usuarios reales, sincronización e invitaciones |
| Avisos | Calculados en el teléfono | Tareas programadas y notificaciones push (APNs/FCM) |
| Historial de patrimonio | Serie de demostración | Foto diaria guardada |
| Resúmenes | Texto para copiar | PDF generado (decidir librería o servidor) |

## Correr contra el backend

Sin configuración, la app usa los datos de demostración. Para usar el
backend ([`inti-backend`](https://github.com/Bencho911/inti-backend)):

```bash
flutter run --dart-define=INTI_API_URL=http://10.0.2.2:3000   # emulador Android
flutter run --dart-define=INTI_API_URL=http://localhost:3000  # simulador iOS
```

Con `INTI_API_URL` cambian a la versión real: registro e ingreso
(`ApiAuthRepository`), cuentas (`ApiAccountsRepository`) y movimientos
(`ApiTransactionsRepository`). Los tokens se guardan cifrados y se renuevan
solos. Fuera de producción el código SMS es `123456`.

Todavía de demostración aunque haya backend: planes, negocio, inversiones,
compartir y avisos. Con backend, conectar un banco, mover plata y recuperar
la contraseña muestran que aún no están disponibles, en lugar de simularlos.

## Decisiones que quedan abiertas
- **PDF:** hoy los resúmenes se copian como texto. Un PDF necesita un paquete
  (`pdf` más uno para compartir) o generarlo en el servidor.
- **Conexión de cuentas, pagos y facturación electrónica:** dependen de
  elegir aliados y de la regulación aplicable.
- **Asistente en lenguaje natural:** requiere backend y decidir qué datos
  salen a un modelo.
- **Widgets en la pantalla de inicio:** código nativo por plataforma.
- **Invertir desde la app:** regulado; la decisión es solo mostrar.
