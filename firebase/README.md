# VOXON90 en la nube (opcional)

La caja principal funciona **sin internet**. Esta carpeta solo define el servicio opcional que sube un
**resumen del negocio** a Firebase para que el dueño lo vea en su celular.

```text
[Caja principal: motor C++ + servidor Java] ──(cuando hay internet)──► [Firestore] ◄── [App del dueño]
        cloud.snapshot cada 60 s                 solo lo que cambió           solo lectura
```

Lo que se sube (nada de PIN, costos por proveedor ni datos de empleados más allá del nombre):

| Documento | Contenido |
| --- | --- |
| `businesses/{negocio}/snapshots/status` | Nombre del negocio, ventas de hoy, caja abierta, órdenes abiertas, fiao por cobrar |
| `businesses/{negocio}/days/{AAAA-MM-DD}` | Totales, ITBIS, propina, cobros por método, lo más vendido, ventas por hora, cajeros y últimas 30 ventas |
| `businesses/{negocio}/snapshots/cash` | Últimas 10 cajas con su cuadre |
| `businesses/{negocio}/snapshots/inventory` | Productos bajo el mínimo |
| `businesses/{negocio}/snapshots/receivables` | Clientes que deben |
| `businesses/{negocio}/devices/{uid}` | Cajas vinculadas (el dueño puede quitar una para revocarla) |

## Cómo se vincula una caja

1. El dueño entra a la app del dueño con su cuenta y crea su negocio (`businesses/{id}` con su `uid` en
   `ownerUids`).
2. La app genera un **código de 8 caracteres** (`linkCodes/{código}`) que vence en 30 minutos o menos.
3. En la caja principal: **Ajustes → App del dueño → Vincular**. El servidor entra a Firebase como usuario
   anónimo, se registra en `devices/{uid}` con ese código y guarda su sesión en `vinculo-nube.json`, junto a
   la base de datos (solo lo lee el usuario del sistema).
4. Desde ahí la caja sube el resumen cada vez que cambia algo, y cada 15 minutos avisa que sigue en línea.

Las reglas ([`firestore.rules`](firestore.rules)) hacen que una caja **solo** pueda escribir `days` y
`snapshots` del negocio que la vinculó, y que **solo los dueños** lean. No hace falta Cloud Functions ni
guardar una clave de servicio en el negocio.

## Preparar el proyecto de Firebase

1. Crea un proyecto en [console.firebase.google.com](https://console.firebase.google.com) y una base de
   **Cloud Firestore**.
2. Activa **Authentication → Sign-in method**: *Anónimo* (para las cajas) y *Correo/contraseña* (para el dueño).
3. Publica las reglas: `firebase deploy --only firestore:rules --project <tu-proyecto>`.
4. Copia el **ID del proyecto** y la **clave web** (Configuración del proyecto → Tus apps → Web).
5. Arranca el servidor con la nube activada:

```bash
voxon-server --firebase-project <tu-proyecto> --firebase-api-key <clave-web>
# o con variables: VOXON_FIREBASE_PROJECT, VOXON_FIREBASE_API_KEY, VOXON_CLOUD_INTERVAL
```

Sin esas opciones el servidor funciona igual, solo que Ajustes muestra la app del dueño como apagada.

**Costo:** la capa gratuita de Firestore permite 20,000 escrituras por día en todo el proyecto. Cada caja
escribe solo los documentos que cambiaron (un negocio activo ronda las 600–1,500 escrituras diarias con el
intervalo por defecto), así que para varios negocios conviene el plan Blaze.

## Pruebas de las reglas

Los emuladores de Firebase necesitan **JDK 21 o superior** (el resto del backend usa JDK 17):

```bash
cd firebase
npm install
JAVA_HOME=$(brew --prefix openjdk@21) npm test     # macOS con Homebrew
```

Y la prueba de punta a punta del sincronizador Java contra los emuladores:

```bash
cd firebase
JAVA_HOME=$(brew --prefix openjdk@21) firebase emulators:exec --only auth,firestore --project demo-voxon90 \
  "cd ../backend/server && VOXON_FIREBASE_EMULATOR=127.0.0.1 ./gradlew test --tests '*CloudEmulatorTest'"
```
