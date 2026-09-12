# VOXON90 Dueño

App móvil (Android e iOS) para que el dueño vea su negocio desde el celular. **Solo lee**: los datos los
sube la caja principal a Firebase cuando hay internet; vender y cobrar siguen siendo cosa de la caja.

| Pestaña | Qué muestra |
| --- | --- |
| Hoy | Ventas del día, ITBIS, efectivo en caja, cobros por método, lo más vendido y las últimas ventas |
| Días | Los últimos días con sus totales, cobros, productos y anulaciones |
| Atención | Productos bajo el mínimo, clientes que deben y las últimas cajas con su cuadre |
| Cajas | Código para vincular una caja principal y las cajas ya vinculadas (se pueden quitar) |

## Configurar

Necesita el proyecto de Firebase que se prepara en [`../../firebase/README.md`](../../firebase/README.md)
(Firestore, *Authentication* con correo y anónimo, y las reglas publicadas). Los datos del proyecto se pasan
al compilar, no se guardan en el repositorio:

```bash
flutter run \
  --dart-define=FIREBASE_PROJECT_ID=<tu-proyecto> \
  --dart-define=FIREBASE_API_KEY=<clave-web> \
  --dart-define=FIREBASE_APP_ID=<app-id> \
  --dart-define=FIREBASE_SENDER_ID=<sender-id>
```

Los cuatro valores salen de la consola de Firebase: *Configuración del proyecto → Tus apps → Web*. Con
`--dart-define=FIREBASE_EMULATOR=127.0.0.1` la app usa los emuladores en vez del proyecto real.

```bash
flutter test      # no necesita Firebase: usa un repositorio falso
flutter analyze
flutter build apk --release --dart-define=...
```

## Cómo se vincula una caja

1. En esta app: **Cajas → Vincular una caja**. Aparece un código de 8 caracteres que dura 15 minutos.
2. En la caja principal: **Ajustes → App del dueño → Vincular**, y se escribe ese código.
3. Desde ahí la caja sube su resumen sola. Para revocarla, se quita desde **Cajas**.

## Cómo está hecho

```text
lib/
├── main.dart                     Arranque: Firebase con los --dart-define
├── app.dart                      Sesión → negocio → resumen
├── firebase_config.dart          Datos del proyecto
├── format.dart                   Pesos, cantidades y fechas en español
├── domain/link_code.dart         Código de vínculo (mismo alfabeto que el servidor)
├── data/owner_repository.dart    Lo que la app necesita (interfaz)
├── data/firebase_owner_repository.dart   Implementación con Firestore y Firebase Auth
├── providers.dart                Riverpod
└── screens/                      Entrar, negocios y resumen
```

La app no conoce Firestore fuera de `data/`: las pruebas usan un repositorio falso
([`test/support/fake_owner_repository.dart`](test/support/fake_owner_repository.dart)).

**Pendiente:** está solo en español (la app de la caja tiene español e inglés) y no envía notificaciones.
