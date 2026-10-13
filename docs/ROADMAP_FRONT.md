# Qullqi: completar el front antes del backend

Todo corre con datos de demostración detrás de las mismas interfaces
(`*Repository`) que usará el backend. Cada hito termina con: pruebas,
capturas claro/oscuro, texto al 200 %, guías de accesibilidad y analizador
limpio.

## Hito 11 — Inteligencia sobre tu plata
- Pagos recurrentes y suscripciones (detección, próximo cobro, subidas de
  precio).
- Cómo va tu mes: cifra diaria y pronóstico de fin de mes.
- Reglas de categorías (crear, aplicar a lo anterior, aprender de tus
  correcciones).
- Cobros raros: duplicados, montos fuera de lo normal y cobros del banco.

## Hito 12 — Patrimonio y deudas
- Historial de patrimonio (gráfica y variación).
- Plan de deudas: tarjetas por "bola de nieve" o "avalancha".

## Hito 13 — Colombia
- Calendario tributario según el documento (NIT o cédula).
- Seguimiento del 4x1000 (GMF).
- Independientes: recordatorios de PILA, prima y cesantías.
- Ayuda para la declaración de renta (resumen de ingresos, retenciones y
  deducciones).

## Hito 14 — Negocio avanzado
- Cotizaciones y facturas recurrentes.
- Enlaces de pago (pantalla y estados; el cobro real es del backend).
- Conciliación: cruzar cada cobro con el depósito que llegó.
- Cuentas por pagar a proveedores.
- Acceso del contador (invitar, permisos de solo lectura, exportar).

## Hito 15 — Compartir
- Hogar o pareja con gastos compartidos.
- Dividir una cuenta y deudas entre personas.
- Metas compartidas.

## Hito 16 — Confianza y retención
- Exportar y borrar mis datos.
- Resumen semanal y cierre mensual (PDF).
- Varias monedas.
- Centro de notificaciones listo para push real.

## Fuera del front (necesitan backend, aliado o regulación)
| Función | Por qué espera |
|---|---|
| Pagos Bre-B y pago de servicios | Requiere aliado y autorización |
| Facturación electrónica DIAN | Requiere proveedor tecnológico autorizado |
| Asistente en lenguaje natural | Requiere backend y decidir qué datos salen a un modelo |
| Notificaciones push reales | Requiere APNs/FCM desde el servidor |
| Widgets en la pantalla de inicio | Código nativo por plataforma; se evalúa al final |
| Invertir desde la app | Regulado (decidido: solo ver) |
