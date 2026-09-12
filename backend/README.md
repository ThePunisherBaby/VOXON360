# Backend local de VOXON90

VOXON90 trabaja **local primero**: vender, cobrar, cerrar la caja y ver los reportes nunca dependen de
internet. Todos los datos viven en un archivo SQLite dentro del equipo del negocio, y los demás equipos
(teléfonos de meseros, pantalla de cocina, otras cajas) se conectan por el WiFi del local.

Lo único que sale a internet es **opcional**: el resumen que la caja sube a Firebase para que el dueño lo
vea en su celular ([`firebase/`](../firebase/README.md)). Si se apaga o no hay señal, el negocio sigue
funcionando igual.

```text
[Teléfonos y tablets: navegador] ──┐
[App VOXON90: Android / escritorio] ┼── WiFi local ──► [Servidor Java] ──JNI──► [Motor C++ libvoxoncore] ──► voxon90.db (SQLite)
[Pantalla de cocina] ───────────────┘       HTTP + eventos en vivo    │              reglas del negocio        migraciones incrustadas
                                                                      └──(opcional, si hay internet)──► [Firebase] ◄── app del dueño
```

| Carpeta | Lenguaje | Qué hace | Pruebas |
| --- | --- | --- | --- |
| [`sql/`](sql/) | SQL | Esquema, triggers de integridad y vistas de reportes | `sql/tests/run.sh` (sqlite3) |
| [`core/`](core/) | C++17 | Motor: SQLite embebido, migraciones, reglas (ITBIS, propina, fiao, caja, inventario, restaurante), API en C | doctest (`voxon_core_tests`) |
| [`server/`](server/) | Java 17 | Servidor de red local: sesiones con PIN, API HTTP, eventos en vivo, descubrimiento UDP, cliente web y sincronización con Firebase | JUnit 5 |
| [`web/`](web/) | JavaScript | Cliente web sin dependencias: vender, mesas, cocina y resumen del dueño | `node --test` |
| [`../firebase/`](../firebase/README.md) | Reglas de Firestore | Servicio opcional: el resumen del negocio para la app del dueño | Emulador de Firebase (`npm test`) |

## Por qué así

- **SQL** guarda las reglas que nunca deben romperse aunque alguien toque la base directamente: una venta
  cobrada no se modifica (solo se anula), la caja cerrada no cambia, el fiao respeta el límite, el
  inventario se deriva de un libro de movimientos que solo acepta agregados.
- **C++** concentra la lógica del negocio en un solo lugar y compila en cualquier sistema
  (Windows, macOS, Linux, Android con el NDK). Su API en C recibe y devuelve JSON, así lo usan igual
  Java, Dart (FFI) o cualquier otro lenguaje.
- **Java** atiende la red del negocio: varios equipos a la vez, sesiones, eventos en vivo. Solo necesita
  el JDK, sin dependencias.
- **JS** da una interfaz a cualquier equipo con navegador, sin instalar nada.

## Requisitos

| Sistema | Para compilar | Para ejecutar el servidor |
| --- | --- | --- |
| Debian / Ubuntu | `sudo apt install build-essential cmake ninja-build openjdk-17-jdk` | `openjdk-17-jre` |
| macOS | Xcode Command Line Tools, `brew install cmake ninja openjdk@17` | JDK 17+ |
| Windows | Visual Studio 2022 (C++), CMake, JDK 17 | JDK 17+ |

Opcional: `sqlite3` para las pruebas SQL y Node.js 20+ para las pruebas del cliente web. SQLite, nlohmann/json
y doctest vienen incluidos en [`core/third_party`](core/third_party) (no se descarga nada al compilar).

## Compilar y probar

```bash
scripts/build-backend.sh              # Linux y macOS
powershell scripts/build-backend.ps1  # Windows
```

A mano:

```bash
cmake -S backend/core -B backend/core/build -DCMAKE_BUILD_TYPE=Release
cmake --build backend/core/build --parallel
ctest --test-dir backend/core/build --output-on-failure
backend/sql/tests/run.sh
(cd backend/server && ./gradlew test installDist)
(cd backend/web && npm test)
```

## Ejecutar

```bash
backend/server/build/install/voxon-server/bin/voxon-server
```

Al arrancar muestra las direcciones para abrir desde los equipos del negocio, por ejemplo
`http://192.168.1.10:8090/`. La primera vez pide configurar el negocio y el PIN del dueño.

| Opción | Variable | Por defecto |
| --- | --- | --- |
| `--db <archivo>` | `VOXON_DB` | `~/VOXON90/voxon90.db` |
| `--bind <ip>` | `VOXON_BIND` | `0.0.0.0` |
| `--port <puerto>` | `VOXON_PORT` | `8090` |
| `--web-dir <carpeta>` | `VOXON_WEB_DIR` | `backend/web` |
| `--backup-dir <carpeta>` | `VOXON_BACKUP_DIR` | `~/VOXON90/respaldos` |
| `--core-lib <archivo>` | `VOXON_CORE_LIBRARY` | se busca en `java.library.path` |
| `--discovery-port <puerto>` | `VOXON_DISCOVERY_PORT` | `47800` (UDP) |
| `--no-discovery` | | activo |
| `--pin-iterations <n>` | | `20000` |
| `--firebase-project <id>` | `VOXON_FIREBASE_PROJECT` | sin nube |
| `--firebase-api-key <clave>` | `VOXON_FIREBASE_API_KEY` | sin nube |
| `--firebase-emulator <host>` | `VOXON_FIREBASE_EMULATOR` | producción |
| `--cloud-interval <seg>` | `VOXON_CLOUD_INTERVAL` | `60` |

**Descubrimiento en la red:** un equipo envía por UDP (difusión, puerto 47800) el texto `VOXON90_DISCOVER` y
el servidor responde `{"service":"voxon90","name":"Colmado…","httpPort":8090,"version":"0.1.0"}`.

## La API

Toda operación es un **método** con parámetros JSON. Los montos van en **centavos** (`priceCents: 5900` =
RD$59.00) y las cantidades en **milésimas** (`quantityMilli: 500` = media libra).

### Por HTTP (servidor Java)

| Ruta | Uso |
| --- | --- |
| `GET /api/health` | Estado del servidor y del motor |
| `POST /api/login` `{"pin":"1234"}` | Devuelve `{"token","user"}` |
| `POST /api/logout` | Cierra la sesión |
| `POST /api/call` `{"method","params"}` | Cabecera `Authorization: Bearer <token>` |
| `GET /api/events?token=…` | Eventos en vivo (SSE): `event: change`, `data: {"method","userId","at"}` |

```bash
curl -X POST http://localhost:8090/api/call -H "Authorization: Bearer $TOKEN" \
  -d '{"method":"sales.quote","params":{"lines":[{"productId":"…","quantityMilli":2000}]}}'
```

### Directo al motor (C, Dart FFI, JNI o línea de comandos)

```c
voxon_engine* engine = voxon_open("voxon90.db", &error);
char* response = voxon_execute(engine, "{\"method\":\"sales.list\",\"actor\":\"<id>\",\"params\":{}}");
voxon_free(response);
voxon_close(engine);
```

```bash
voxon_cli voxon90.db info
voxon_cli voxon90.db call catalog.products.list '{"search":"cafe"}' --actor <id>
voxon_cli voxon90.db stdio     # una solicitud JSON por línea: útil desde cualquier lenguaje
```

Respuesta: `{"ok":true,"result":…}` o `{"ok":false,"error":{"code":"cash_session_closed","message":"…"}}`.

### Métodos y permisos

Roles: **D** dueño · **G** gerente · **C** cajero · **M** mesero · **K** cocina.

| Área | Métodos | Quién |
| --- | --- | --- |
| Sistema | `system.info` · `business.status` · `business.setup` (una sola vez) | Sin sesión |
| | `system.backup` | D |
| | `system.integrityCheck` | D G |
| Negocio | `business.get` | Todos |
| | `business.update` | D |
| Empleados | `users.list` `users.create` `users.update` `users.deactivate` `users.activate` | D G (el gerente no administra dueños ni gerentes) |
| | `users.setPin` | Todos (el propio, con el PIN actual) |
| Catálogo | `catalog.categories.list` `catalog.products.list` `catalog.products.get` | Todos |
| | `catalog.categories.create/update` `catalog.products.create/update/deactivate` | D G |
| Clientes y fiao | `customers.list` `customers.get` | D G C M |
| | `customers.create` `customers.update` `customers.statement` `customers.payment` | D G C (el límite de crédito solo D G) |
| Caja | `cash.current` `cash.open` `cash.movement` `cash.close` | D G C |
| | `cash.sessions` `cash.report` | D G |
| Ventas | `sales.quote` | D G C M |
| | `sales.complete` `sales.get` `sales.list` (el cajero ve solo su caja) | D G C |
| | `sales.void` | D G |
| Fiscal | `fiscal.sequences.list` `fiscal.salesReport` `fiscal.purchasesReport` | D G |
| | `fiscal.sequences.add` `fiscal.sequences.deactivate` | D |
| Inventario | `inventory.lowStock` `inventory.suppliers.list` | D G C |
| | `inventory.suppliers.create/update` `inventory.purchases.create/list/get` `inventory.adjust` `inventory.count` `inventory.movements` | D G |
| Restaurante | `restaurant.areas.list` `restaurant.tables.list` `restaurant.orders.list` `restaurant.orders.get` | Todos |
| | `restaurant.orders.open/addItems/updateItem/cancelItem/send/moveTable` | D G C M |
| | `restaurant.orders.checkout` | D G C |
| | `restaurant.areas.create` `restaurant.tables.create/update` `restaurant.orders.cancel` | D G |
| | `restaurant.kitchen.queue` `restaurant.kitchen.updateItem` | D G M K |
| Reportes | `reports.dashboard` `reports.salesByDay` `reports.productSales` `reports.paymentsByDay` `reports.cashiers` | D G |
| | `reports.receivables` | D G C |
| | `reports.audit` | D |
| App del dueño | `cloud.snapshot` (resumen que se sube a Firebase) | D |
| | `cloud.status` (lo atiende el servidor Java, no el motor) | D G |
| | `cloud.link` `cloud.unlink` | D |

### Códigos de error

| Código | HTTP | Significado |
| --- | --- | --- |
| `invalid_request`, `validation_failed` | 400 | Solicitud o datos inválidos (el mensaje indica el campo) |
| `unauthorized` | 401 | Falta sesión o el PIN es incorrecto |
| `forbidden` | 403 | El rol no permite la operación |
| `not_found`, `unknown_method` | 404 | No existe |
| `too_many_attempts` | 429 | Demasiados PIN incorrectos; espera unos segundos |
| `conflict`, `already_configured`, `not_configured`, `cash_session_closed`, `cash_session_already_open`, `insufficient_payment`, `credit_limit_exceeded`, `payment_exceeds_balance`, `customer_inactive`, `sale_immutable`, `append_only`, `order_not_open`, `fiscal_sequence_exhausted`, `purchase_requires_base_product` | 409 | Regla del negocio |
| `cloud_not_configured`, `invalid_link_code`, `cloud_permission_denied`, `cloud_rejected`, `cloud_owner_inactive`, `cloud_link_revoked`, `cloud_snapshot_failed` | 409 | Nube: falta configurarla o el vínculo no sirve |
| `cloud_offline` | 503 | Sin internet para subir el resumen; se reintenta solo |
| `database_busy` | 503 | Base ocupada; reintentar |
| `database_error`, `internal_error`, `backup_failed`, `cloud_link_unwritable` | 500 | Error inesperado |

## Reglas del negocio incluidas

- **ITBIS** 18 %, 16 % y exento por producto; precios con ITBIS incluido (colmado) o sin incluir (restaurante).
  El ITBIS se calcula por tasa sobre el total agrupado, igual que en `packages/voxon_domain` (Dart).
- **Propina legal 10 %** sobre la base sin ITBIS, solo en consumo dentro del local.
- **Venta al detalle:** una cajetilla descuenta 20 cigarrillos del producto base; venta por libra con decimales.
- **Caja:** fondo, entradas y salidas, abonos de fiao en efectivo y compras en efectivo; cuadre con sobrante o faltante.
- **Fiao:** límite de crédito autorizado por dueño o gerente, abonos, estado de cuenta; anular una venta revierte la deuda.
- **Inventario:** compras con costo promedio ponderado, mermas, conteo físico y alertas de mínimo.
- **Comprobantes:** rangos NCF/e-NCF autorizados por la DGII con numeración local sin retrocesos, y datos del
  período para preparar los formatos 606 y 607.
- **Bitácora** de acciones sensibles (anulaciones, cambios de precio y de límite de crédito, cierres de caja).

## App del dueño (Firebase, opcional)

El servidor puede subir a Firestore un resumen para que el dueño vea su negocio desde el celular. Nada de
esto afecta la venta: si no hay internet, el resumen queda pendiente y sube cuando vuelva la señal.

- `cloud.snapshot` (motor, solo dueño) arma en SQL el resumen: hoy y ayer con totales, ITBIS, propina, cobros
  por método, lo más vendido, ventas por hora, cajeros y las últimas 30 ventas; además caja abierta, últimas
  cajas, productos bajo el mínimo y clientes que deben.
- El servidor compara cada documento con lo último que subió (SHA-256) y **solo escribe lo que cambió**;
  cada 15 minutos escribe el estado aunque nada cambie, para avisar que la caja sigue en línea.
- Se vincula con un código de 8 caracteres que genera la app del dueño. El servidor entra a Firebase como
  usuario anónimo y guarda su sesión en `vinculo-nube.json`, junto a la base de datos.
- Las reglas de Firestore permiten a cada caja escribir **solo** su negocio, y leer **solo** a los dueños.

Detalles, costos y pruebas con el emulador: [`firebase/README.md`](../firebase/README.md).

## Seguridad

- El PIN se guarda con PBKDF2-HMAC-SHA256 y sal propia; tras 5 intentos fallidos en un minuto se bloquea el
  ingreso por 30 segundos.
- Las sesiones vencen tras 12 horas sin uso y se cierran al desactivar al empleado.
- Por la red, los respaldos solo se guardan en la carpeta configurada.
- El tráfico dentro del local va por HTTP sin cifrar: usa la red WiFi del negocio con contraseña (WPA2 o
  superior) y no la compartas con clientes.
- El vínculo con Firebase (`vinculo-nube.json`) contiene un token de sesión: queda con permisos solo para el
  usuario del sistema que corre el servidor.

## Límites de esta versión

- **Factura electrónica (e-CF):** enviarla a la DGII requiere internet, así que esta versión no la transmite.
  El motor numera los comprobantes con los rangos autorizados y deja listos los datos del período; el envío
  lo hace el contador o una versión conectada futura.
- **Una base de datos por negocio**, en el equipo donde corre el servidor. Los demás equipos dependen de que
  ese equipo esté encendido y en la misma red.
- **La nube es de solo lectura para el dueño:** la app del dueño muestra el resumen, no cambia datos ni
  reemplaza a la caja.
