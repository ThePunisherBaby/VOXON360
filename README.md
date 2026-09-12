# VOXON90

Punto de venta para negocios que venden de todo: colmados, tiendas y restaurantes de República Dominicana.
Funciona en **Android, Linux (Debian), macOS y Windows** con Flutter.

VOXON es una línea de programas por grados: **45** (móvil), **90** (este, nivel medio), **180** y **360**.

VOXON90 trabaja **local primero**: vender, cobrar y cerrar la caja nunca dependen de internet. Lo único
opcional que sale a la red es el resumen que el dueño ve en su celular.

## Piezas

| Pieza | Lenguaje | Qué hace |
| --- | --- | --- |
| [`lib/`](lib) | Dart / Flutter | La app del negocio: vender, mesas, cocina, resumen y ajustes |
| [`backend/sql`](backend/sql) | SQL | Esquema SQLite, triggers de integridad y vistas de reportes |
| [`backend/core`](backend/core) | C++17 | Motor con SQLite embebido y todas las reglas (ITBIS, propina, fiao, caja, inventario, restaurante) |
| [`backend/server`](backend/server) | Java 17 | Servidor para la red del negocio: PIN, API HTTP, eventos en vivo, descubrimiento en el WiFi y nube opcional |
| [`backend/web`](backend/web) | JavaScript | Cliente web para cualquier equipo con navegador |
| [`packages/voxon_domain`](packages/voxon_domain) | Dart puro | Dinero en centavos, ITBIS y propina legal, compartido por la app |
| [`apps/voxon90_owner`](apps/voxon90_owner/README.md) | Dart / Flutter | App móvil del dueño: mira el negocio desde el celular (solo lectura) |
| [`firebase/`](firebase/README.md) | Reglas de Firestore | Servicio opcional: el resumen del negocio para la app del dueño |

El backend se compila y prueba con `scripts/build-backend.sh` (o `scripts/build-backend.ps1` en Windows).
Detalles de la API, permisos y reglas: [`backend/README.md`](backend/README.md).

## Cómo se usa

```text
[Caja principal] ──► servidor local (Java + motor C++) ──► voxon90.db
        ▲                      │
        │  WiFi del negocio    │ eventos en vivo
[Teléfono del mesero]  [Pantalla de cocina]  [Otra caja]     ──(opcional)──► [Firebase] ◄── app del dueño
```

1. En la caja principal corre el servidor; la primera vez se configura el negocio y el PIN del dueño.
2. Los demás equipos abren la app, **buscan la caja en el WiFi** (o se escribe su dirección) y entran con PIN.
3. Cada empleado ve solo lo suyo: el mesero mesas y cocina, el cajero vender, el dueño además el resumen.

## Por qué Flutter

| | Flutter | Tauri 2 | Compose Multiplatform | React Native | .NET MAUI |
| --- | --- | --- | --- | --- | --- |
| Android | Sí | Reciente | Sí | Sí | Sí |
| Windows y macOS | Sí | Sí | Sí (JVM) | Proyectos aparte | Sí |
| Linux | Sí | Sí | Sí (JVM) | No | No |
| Una sola UI nativa compilada | Sí | Web embebida | Sí | No | Sí |

Flutter es la única opción madura que cubre las cuatro plataformas con un solo código y una sola UI,
compilada a código nativo.

## Requisitos

- Flutter 3.44 (stable), Dart 3.12
- Android: Android SDK (Android Studio)
- macOS: Xcode + CocoaPods
- Windows: Visual Studio 2022 con "Desarrollo de escritorio con C++"
- Linux: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev`
- Backend: JDK 17 y CMake (ver [`backend/README.md`](backend/README.md))

`flutter doctor` indica qué falta en cada máquina.

## Desarrollo

```bash
flutter pub get                 # dependencias; también genera las traducciones
flutter devices                 # dispositivos disponibles
flutter run -d macos   --dart-define-from-file=config/dev.json
flutter run -d windows --dart-define-from-file=config/dev.json
flutter run -d linux   --dart-define-from-file=config/dev.json
flutter run -d <id-android> --dart-define-from-file=config/dev.json

flutter analyze
flutter test
dart format lib test
```

Para probar con datos reales, arranca el servidor local en otra terminal:

```bash
(cd backend/server && ./gradlew installDist)
backend/server/build/install/voxon-server/bin/voxon-server
```

En VS Code, las configuraciones **VOXON90 (dev)** y **VOXON90 (prod, release)** ya están en `.vscode/launch.json`.

## Compilar para distribuir

Cada escritorio solo compila en su propio sistema operativo. Android compila desde cualquiera.

| Plataforma | Comando | Salida |
| --- | --- | --- |
| Android | `flutter build apk --release --dart-define-from-file=config/prod.json` | `build/app/outputs/flutter-apk/app-release.apk` |
| Android (Play Store) | `flutter build appbundle --release --dart-define-from-file=config/prod.json` | `build/app/outputs/bundle/release/app-release.aab` |
| macOS | `flutter build macos --release --dart-define-from-file=config/prod.json` | `build/macos/Build/Products/Release/VOXON90.app` |
| Windows | `flutter build windows --release --dart-define-from-file=config/prod.json` | `build/windows/x64/runner/Release/` |
| Linux (.deb) | `flutter build linux --release --dart-define-from-file=config/prod.json && scripts/build_deb.sh` | `build/deb/voxon90_<versión>_<arch>.deb` |

### CI

`.github/workflows/build.yml` ejecuta formato, análisis y tests (app, `voxon_domain` y backend en Linux,
macOS y Windows), y después compila las cuatro plataformas en cada push a `main`. Los binarios quedan como
*artifacts* del workflow. Es la forma práctica de obtener builds de Linux y Windows sin tener esas máquinas.

El build de Linux se hace en Ubuntu 22.04 (glibc 2.35), así el `.deb` funciona en Debian 12 o superior.

## Estructura

```text
lib/
├── main.dart                  Punto de entrada
├── bootstrap.dart             Inicialización previa a runApp (errores, almacenamiento)
├── app/
│   ├── app.dart               MaterialApp: tema, idioma y router
│   ├── router.dart            Rutas, secciones por rol y marco de navegación
│   ├── routes.dart            Constantes de rutas
│   └── labels.dart            Nombres de roles y secciones
├── core/                      Código compartido, sin lógica de negocio
│   ├── backend/               Cliente del servidor local, descubrimiento y sesión
│   ├── config/                Entorno (dev / prod)
│   ├── format/                Dinero y cantidades (RD$1,250.75)
│   ├── logging/               Logger central
│   ├── storage/               Almacenamiento clave-valor (interfaz + implementaciones)
│   ├── theme/                 Tema Material 3 claro y oscuro
│   └── widgets/               AdaptiveScaffold: barra inferior en móvil, rail lateral en escritorio
├── features/                  Una carpeta por funcionalidad
│   ├── connection/            Conectar con la caja, PIN y configuración inicial
│   ├── sell/                  Venta rápida con carrito, cobro y fiao
│   ├── tables/                Mesas, órdenes y cobro de la cuenta
│   ├── kitchen/               Pantalla de cocina y bar
│   ├── summary/               Resumen del día, cierre de caja y respaldo
│   └── settings/              Sesión, caja principal, app del dueño, tema e idioma
└── l10n/                      Traducciones (.arb) y código generado
backend/                       Motor C++, servidor Java, SQL y cliente web
apps/voxon90_owner/            App móvil del dueño (Android e iOS)
firebase/                      Reglas de Firestore para la app del dueño
config/                        Variables por entorno (dev.json, prod.json)
scripts/                       build-backend.sh, build_deb.sh y demás
test/                          Tests, con la misma estructura que lib/
```

### Paquetes

| Pieza | Paquete | Uso |
| --- | --- | --- |
| Estado e inyección de dependencias | `flutter_riverpod` | Providers y Notifiers; fácil de sobrescribir en tests |
| Navegación | `go_router` | Rutas declarativas con secciones según el rol |
| Ajustes locales | `shared_preferences` | Detrás de la interfaz `KeyValueStore` |
| Traducciones | `flutter_localizations` + `intl` | Español (plantilla) e inglés |

La app **no** guarda datos del negocio: todo vive en la caja principal y se consulta por HTTP, con eventos
en vivo para refrescar lo que cambió en otro equipo.

## Cómo añadir una funcionalidad

1. Crea `lib/features/<nombre>/` con las capas que necesite (`domain/`, `application/`, `presentation/`).
2. Registra la ruta en `lib/app/routes.dart` y `lib/app/router.dart`. Si va en la navegación principal,
   añádela a `appSections` con los roles que la ven.
3. Añade los textos a `lib/l10n/app_es.arb` y `lib/l10n/app_en.arb` y ejecuta `flutter pub get`.
4. Si necesita datos nuevos, agrega el método en el motor ([`backend/core/src/services`](backend/core/src/services))
   con sus pruebas, y documéntalo en `backend/README.md`.
5. Añade los tests en `test/features/<nombre>/`.

## Pendiente antes de publicar

- **Identificador de la app** `com.voxon90.voxon90` (Android, macOS, Linux). Si tienes dominio propio,
  cámbialo ya: una vez publicada la app no se puede cambiar.
- **Firma de Android**: el build release usa la clave de debug (`android/app/build.gradle.kts`).
- **Iconos** propios en todas las plataformas (por ejemplo con `flutter_launcher_icons`).
- **Maintainer** del paquete `.deb` en `scripts/build_deb.sh`.
- Firma y notarización en macOS; certificado de firma de código en Windows.
- Proyecto de Firebase propio si se va a usar la app del dueño ([`firebase/README.md`](firebase/README.md)).
- Para añadir iOS o web: `flutter create --platforms ios,web .`
