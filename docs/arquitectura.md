# VOXON · Arquitectura multi-tenant

Un solo programa para toda la línea (**45, 90, 180, 360**). El cliente crea una **cuenta**, dentro de
ella una o varias **instancias** (cada negocio o sucursal), y cada instancia tiene un **modo** que decide
qué pantallas y reglas aplican. El **plan** de la suscripción abre funciones y pone topes.

```text
[App VOXON (Flutter: Android, iOS, web, escritorio)]
        │  Google o correo (Firebase Auth)
        ▼
[Firestore  proyecto voxon360-8349a · base principal (default), Standard]
  cuentas · instancias · empleados · catálogo · ventas · caja · resúmenes
        ▲                         ▲
        │ reglas de seguridad     │ Cloud Functions
        │ (quién ve y escribe)    │ (Stripe, límites, resúmenes, invitaciones)
        └─────────────────────────┴──► [Stripe / PayPal]
```

## Decisiones

| Tema | Decisión |
| --- | --- |
| Fuente de la verdad | Firestore. La app guarda copia local (persistencia offline) para seguir vendiendo en cortes cortos. |
| Entrada | Firebase Auth con **Google** y **correo/contraseña**. |
| Unidad de trabajo | **Instancia**: un negocio o sucursal. Una cuenta puede tener varias, según el plan. |
| Modos | **colmado**, **restaurante**, **supermercado**, **tienda**. Cada uno trae catálogo de ejemplo, pantallas y reglas propias. |
| Planes | Abren **funciones** y ponen **topes** (instancias, usuarios, productos, dispositivos). |
| Cobro | **Stripe** (tarjeta internacional y local) con PayPal como segunda opción; webhooks en Cloud Functions. |
| Reglas del negocio | Se conserva `packages/voxon_domain` (Dart puro, probado): ITBIS 18/16/0, propina legal, descuentos, redondeos. El motor C++/Java local queda archivado. |

## Datos (Firestore)

```text
accounts/{accountId}
  name, ownerUid, createdAt
  plan: { tier: "v45"|"v90"|"v180"|"v360", status, currentPeriodEnd, source: "stripe"|"manual" }
  limits: { instances, users, products, devices }          ← copiados del plan por Functions
  usage:  { instances, users }                             ← contadores que mantienen las Functions
  billing: { stripeCustomerId, stripeSubscriptionId }      ← solo lo escriben las Functions

accounts/{accountId}/members/{uid}        rol en la cuenta: owner | admin
instances/{instanceId}
  accountId, name, mode, active, createdAt
  fiscal: { rnc, priceMode, legalTip }                     ← reglas dominicanas
instances/{instanceId}/members/{uid}      rol en la instancia: owner | manager | cashier | waiter | kitchen
instances/{instanceId}/products/{id}
instances/{instanceId}/customers/{id}     fiao: límite y balance
instances/{instanceId}/sales/{id}         venta cerrada (inmutable; anular crea el movimiento contrario)
instances/{instanceId}/cashSessions/{id}
instances/{instanceId}/tables/{id}        solo modo restaurante
instances/{instanceId}/orders/{id}        comandas, solo modo restaurante
instances/{instanceId}/days/{AAAA-MM-DD}  resumen del día (lo arma una Function)
invites/{code}                            invitar empleados a una instancia
```

**Por qué instancias en la raíz y no dentro de la cuenta:** un empleado pertenece a una instancia, no a la
cuenta del dueño. Así las reglas y las consultas de la app no tienen que atravesar la cuenta, y mover una
instancia de cuenta (por ejemplo, al vender el negocio) es cambiar un campo.

## Quién puede qué

- **Dueño de la cuenta:** paga, crea instancias, invita, ve todo.
- **Administrador de la cuenta:** todo menos la facturación.
- **Roles por instancia:** dueño, gerente, cajero, mesero, cocina (los mismos que ya estaban probados).
- Las reglas leen la membresía (`instances/{id}/members/{uid}`) y el plan de la cuenta. Lo que cuesta caro
  de verificar en reglas (topes, contadores) lo hacen las Functions, que son las únicas que escriben
  `plan`, `limits`, `usage` y `billing`.

## Planes

| | **45** | **90** | **180** | **360** |
| --- | --- | --- | --- | --- |
| Para | Vender en el celular | Negocio completo | Varias sucursales | Cadena / empresa |
| Instancias | 1 | 2 | 5 | Sin tope |
| Usuarios | 2 | 5 | 20 | Sin tope |
| Productos | 300 | 5,000 | 50,000 | Sin tope |
| Dispositivos | 1 | 3 | 10 | Sin tope |
| Funciones | Ventas, caja, clientes, reportes del día | + Inventario, fiao, restaurante, compras, respaldos, comprobantes NCF | + Sucursales, empleados por turno, reportes comparativos, costos | + API, multi-empresa, integraciones, soporte |

El plan vive en la cuenta; la app pregunta `plan.tier` y `limits` para encender funciones, y las Functions
vuelven a validar cada operación sensible (nunca se confía solo en la app).

## Cobro

1. La app llama una Function `createCheckoutSession` con el plan elegido.
2. Stripe cobra y avisa por **webhook** (`checkout.session.completed`, `customer.subscription.updated`,
   `customer.subscription.deleted`).
3. La Function actualiza `accounts/{id}.plan` y `limits`. La app reacciona sola porque escucha ese documento.
4. **Prueba gratis** y activación manual (transferencia) quedan como estados del mismo campo `plan.source`.

> Cloud Functions y los webhooks necesitan el plan **Blaze** de Firebase (pago por uso, con capa gratuita).

## Trabajo por fases

| Fase | Qué entra |
| --- | --- |
| 0 | Proyecto listo: proveedores de entrada, reglas base, índices, emuladores, repo y CI |
| 1 | Cuentas, instancias, modos, invitaciones y roles, con reglas y pruebas |
| 2 | Vender: catálogo, carrito, cobro, caja, ticket. Offline de Firestore |
| 3 | Inventario, fiao y clientes; mesas y cocina en modo restaurante |
| 4 | Stripe: checkout, portal del cliente, webhooks y topes por plan |
| 5 | Resúmenes diarios, reportes, exportables DGII (606/607) y respaldos |

## Lo que se conserva del trabajo anterior

- `packages/voxon_domain`: dinero en centavos, ITBIS por tasa, propina legal, descuentos. Ya probado.
- Las **reglas del negocio** escritas en SQL y C++ (caja, fiao, costo promedio, numeración, inmutabilidad
  de ventas) se vuelven a implementar en Functions y reglas, usando las mismas pruebas como guía.
- La app Flutter: pantallas de vender, mesas, cocina y resumen sirven de base para las nuevas.
- El motor local (C++/Java/SQLite) queda en el historial de git como punto de partida archivado.
