# VOXON · El sistema

Dos programas, un solo backend. El dueño instala primero **VOXON 360** en su computadora. Desde ahí crea
su negocio con un asistente visual y, según su plan, vende desde el mismo programa o instala **VOXON POS**
en todas sus cajas.

```text
                       ┌──────────────────────────── Firebase (voxon360-8349a) ───────────────────────────┐
                       │  Auth · Firestore (default) · Cloud Functions · reglas · Stripe                 │
                       └───────────────▲───────────────────────────────────────────────▲─────────────────┘
                                       │ Google o correo                               │ caja vinculada
┌──────────────────────────────────────┴───────────┐                ┌──────────────────┴──────────────────────┐
│ VOXON 360  (apps/voxon360)                        │   código o     │ VOXON POS  (apps/voxon_pos)             │
│ computadora del admin: Windows, macOS, web, móvil │ ─ archivo ───▶ │ cada caja: Windows, Android, macOS, iPad│
│ · crear cuenta e instancias (asistente visual)    │   de caja      │ · se vincula una vez a una instancia    │
│ · modo, logo, colores, impuestos, mesas, catálogo │                │ · se ve con el logo y colores del negocio│
│ · empleados y PIN, cajas, planes y pagos          │                │ · empleados entran con PIN              │
│ · reportes · y vender (plan 45)                   │                │ · vende, cobra, caja, mesas, cocina     │
└───────────────────────────────────────────────────┘                └─────────────────────────────────────────┘
                 └────────────── packages/: voxon_domain · voxon_data · voxon_ui ──────────────┘
```

## Los dos programas

| | VOXON 360 | VOXON POS |
| --- | --- | --- |
| Quién lo usa | Dueño y administradores | Cajeros, meseros, cocina |
| Entrada | Google o correo | La caja se vincula una vez; cada empleado entra con su PIN |
| Qué hace | Crea y configura instancias, administra todo, ve reportes. Puede vender. | Solo operar: vender, cobrar, caja, mesas, comandas, cocina |
| Aspecto | Marca VOXON | **Marca del negocio**: nombre, logo y colores |
| Plan | Todos | 90, 180 y 360 (el 45 vende desde el 360, en un solo equipo) |

**El POS es uno solo, ya hecho.** No se compila un programa por cliente: lo que cambia es la configuración
que la caja descarga al vincularse. Por eso cualquier arreglo del POS llega a todos los negocios a la vez.

## Vincular una caja: QR y doble código

1. Se instala VOXON POS en la caja (el enlace de descarga está en VOXON 360 → **Cajas**). Al abrirlo sin
   vincular, muestra un **código QR** que vence en 10 minutos.
2. En el celular, con VOXON 360: **Cajas → Vincular con QR**. Se escanea, se elige el negocio y el nombre de
   la caja. Aquí se revisa el tope de cajas del plan.
3. El celular muestra un **código de 6 números**: se escribe en la caja.
4. La caja responde con **otro código de 6 números**: se escribe en el celular.
5. Listo: la caja queda vinculada, descarga logo, colores, modo, catálogo y empleados, y pide el PIN.

```text
 VOXON POS (caja)                          VOXON 360 (celular del dueño)
 ─────────────────                         ─────────────────────────────
 startPairing ──► muestra QR ───────────►  escanea · claimPairing
                                           ◄── muestra código A
 escribe código A · confirmPairingOnDevice
 muestra código B ──────────────────────►  escribe código B · completePairing
 ◄──────────────────── caja vinculada ────────────────────────────────►
```

El doble código prueba que quien tiene el celular está frente a la caja: una foto del QR sola no alcanza.
Cada paso admite 5 intentos, todo vence a los 10 minutos y los códigos se guardan con hash.

**Sin celular a mano:** VOXON 360 en la computadora genera un **código de caja** de 8 caracteres (dura 24 h)
que se escribe en la caja. El dueño puede desactivar cualquier caja desde **Cajas**.

## Servicios (Cloud Functions)

| Función | Qué hace |
| --- | --- |
| `createAccount` | Cuenta nueva en prueba con su primer negocio ✅ |
| `createInstance` | Otro negocio, si el plan lo permite ✅ |
| `createInvite` | Invitar a un administrador por correo ✅ |
| `startPairing` → `claimPairing` → `confirmPairingOnDevice` → `completePairing` | Vincular una caja con QR y doble código, con tope por plan |
| `createDeviceCode` / `enrollDevice` | Vincular una caja con un código escrito (sin celular) |
| `revokeDevice` | Desactivar una caja |
| `setStaffPin` / `posLogin` | PIN de empleados guardado con hash; la caja valida el PIN en el servidor |
| `onSaleCreated` / `onSaleVoided` | Resumen del día ✅ y descuento de inventario |
| `createCheckoutSession` / `stripeWebhook` | Planes con Stripe ✅ (esperando claves reales) |

## Código

```text
packages/voxon_domain   Dart puro: dinero, ITBIS 18/16/0, propina legal, carrito, modos y planes
packages/voxon_data     Firebase: sesión, cuentas, instancias, catálogo, ventas, caja, mesas, cajas
packages/voxon_ui       Tema con la marca del negocio y pantallas de operación compartidas
apps/voxon360           Programa del admin
apps/voxon_pos          Programa de las cajas
firebase/               Reglas, índices, funciones y sus pruebas
shared/plans.json       Planes 45/90/180/360
shared/modes.json       Los 20 modos de negocio y sus módulos
```

Las pantallas de operación (vender, mesas, cocina) viven en `voxon_ui`, así VOXON 360 vende con las mismas
pantallas que el POS.

## Modos de negocio

Un modo es configuración, no código aparte: enciende **módulos** (mesas, balanza, fiao, tallas,
vencimientos, citas…), trae categorías y ejemplos, y fija reglas como el ITBIS incluido o la propina legal.
La lista está en [`shared/modes.json`](../shared/modes.json). Orden de trabajo:

1. **Supermercado**: lector de código primero, balanza, varias cajas, ofertas, recepción de mercancía.
2. **Colmado**: botones grandes, fracciones y detalle, fiao, delivery.
3. **Restaurante**: mapa de mesas, comandas por estación, pantalla de cocina, propina legal, dividir cuenta.
4. **Tienda**: tallas y colores, números de serie, garantías, separados.
5. Los otros 16, uno por uno.

## Plataformas

VOXON 360 y VOXON POS se compilan para Windows, macOS, Android e iOS, y 360 también para web. Linux queda
para después: los paquetes oficiales de Firebase para Flutter no lo soportan.
