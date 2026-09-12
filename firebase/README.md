# VOXON en Firebase

Aquí viven las **reglas de seguridad** de la plataforma multi-tenant y sus pruebas. El modelo completo
está en [`docs/arquitectura.md`](../docs/arquitectura.md).

| | |
| --- | --- |
| Proyecto | `voxon360-8349a` (nombre visible: voxon360) |
| Base de datos | `(default)`, Firestore edición Standard, región `nam5`, con protección contra borrado |
| Entrada | Firebase Auth: Google y correo/contraseña |

> El proyecto también tiene una base llamada `voxon360`, pero se creó en modo compatible con MongoDB:
> tiene apagados el acceso de Firestore y el tiempo real, así que ni la app ni las funciones pueden
> usarla, y Google no deja cambiar ese modo. Por eso VOXON usa la base principal `(default)`.

## Quién puede qué

```text
accounts/{cuenta}                 quien paga: plan, topes, uso y facturación
accounts/{cuenta}/members/{uid}   dueño o administrador de la cuenta
instances/{instancia}             un negocio o sucursal, con su modo
instances/{instancia}/members     empleados: owner, manager, cashier, waiter, kitchen
instances/{instancia}/…           products, customers, tables, settings, sales, cashSessions, orders, days
invites/{código}                  invitación para que un empleado entre a una instancia
```

Lo que garantizan las reglas ([`firestore.rules`](firestore.rules)):

- **Nadie ve ni escribe fuera de su instancia.** La membresía manda, no la cuenta.
- **El dinero es del servidor**: `plan`, `limits`, `usage` y `billing` solo los escriben las Cloud
  Functions. Una cuenta nueva nace en prueba (`v45`, `trial`) y nadie se asciende solo.
- **Una venta cobrada no cambia**: solo se anula (dueño o gerente) y nunca se borra. La caja cerrada
  tampoco se toca.
- **Cocina solo mueve su comanda**; el salón la abre y la cobra.
- **Las invitaciones caducan** (máximo 7 días) y no sirven para darse un rol mayor al invitado.
- Los **resúmenes diarios** (`days/`) son de solo lectura para la app: los arma el servidor.

Los **topes del plan** (instancias, usuarios, productos, dispositivos) los aplicarán las Cloud Functions,
porque las reglas no pueden contar documentos. La tabla de planes vive en
[`shared/plans.json`](../shared/plans.json) y la leen tanto la app como las funciones.

## Probar y publicar

Los emuladores necesitan **JDK 21 o superior**:

```bash
cd firebase
npm install
JAVA_HOME=$(brew --prefix openjdk@21) npm test        # 13 pruebas de reglas
```

```bash
firebase deploy --only firestore --project voxon360-8349a   # reglas e índices de la base (default)
firebase deploy --only functions --project voxon360-8349a
```

## Estado del proyecto

- **Authentication:** Google y correo/contraseña activos (el correo se comprobó con un usuario de prueba).
- **Plan Blaze:** activo; las Cloud Functions están instaladas en `us-central1`.
- **Apps:** la web está registrada. Android e iOS se registran cuando se defina el identificador de la app.
- **Stripe:** las funciones de cobro están instaladas con claves provisionales y responden «no configurado»
  hasta cargar las reales con `firebase functions:secrets:set STRIPE_SECRET_KEY` y `STRIPE_WEBHOOK_SECRET`.
  El webhook es `https://us-central1-voxon360-8349a.cloudfunctions.net/stripeWebhook`.
