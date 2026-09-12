# VOXON en Firebase

Aquí viven las **reglas de seguridad** de la plataforma multi-tenant y sus pruebas. El modelo completo
está en [`docs/arquitectura.md`](../docs/arquitectura.md).

| | |
| --- | --- |
| Proyecto | `voxon360-8349a` |
| Base de datos | `voxon360` (Firestore nativo, edición Enterprise, región `nam5`) |
| Entrada | Firebase Auth: Google y correo/contraseña |

> La edición Enterprise admite los SDK de cliente, reglas de seguridad, tiempo real y uso sin conexión.
> La compatibilidad con MongoDB es un modo aparte y está **apagada**: si se enciende, el paquete
> `cloud_firestore` de Flutter deja de funcionar contra esa base.

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
firebase deploy --only firestore --project voxon360-8349a   # reglas e índices de la base voxon360
```

## Pendiente en la consola de Firebase

1. **Authentication → Sign-in method:** activar *Google* y *Correo/contraseña*.
2. **Plan Blaze:** necesario para Cloud Functions (Stripe, topes por plan y resúmenes diarios).
3. Registrar las apps (web y Android) para obtener `apiKey` y `appId` de la app.
