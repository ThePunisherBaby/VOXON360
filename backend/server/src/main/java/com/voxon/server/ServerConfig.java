package com.voxon.server;

import com.voxon.server.cloud.FirebaseSettings;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

/**
 * Configuración del servidor. Cada opción se toma, en orden, del argumento
 * ({@code --port=8090} o {@code --port 8090}), de la variable de entorno y del
 * valor por defecto.
 */
public record ServerConfig(
        Path databasePath,
        String bindAddress,
        int port,
        Path webDir,
        Path backupDir,
        Path coreLibrary,
        boolean discovery,
        int discoveryPort,
        int pinIterations,
        String firebaseProjectId,
        String firebaseApiKey,
        String firebaseEmulatorHost,
        int cloudIntervalSeconds) {

    /** Proyecto que usan los emuladores cuando no se indica otro. */
    public static final String EMULATOR_PROJECT = "demo-voxon90";

    public static final String USAGE = """
            Uso: voxon-server [opciones]
              --db <archivo>             Base de datos (VOXON_DB). Por defecto ~/VOXON90/voxon90.db
              --bind <ip>                Dirección de escucha (VOXON_BIND). Por defecto 0.0.0.0
              --port <puerto>            Puerto HTTP (VOXON_PORT). Por defecto 8090
              --web-dir <carpeta>        Cliente web a servir (VOXON_WEB_DIR)
              --backup-dir <carpeta>     Carpeta de respaldos (VOXON_BACKUP_DIR). Por defecto ~/VOXON90/respaldos
              --core-lib <archivo>       Ruta de libvoxoncore (VOXON_CORE_LIBRARY)
              --discovery-port <p>       Puerto UDP de descubrimiento (VOXON_DISCOVERY_PORT). Por defecto 47800
              --no-discovery             No responder a la búsqueda en la red local
              --pin-iterations <n>       Iteraciones PBKDF2 de los PIN nuevos. Por defecto 20000

            App del dueño (opcional, necesita internet solo para subir el resumen):
              --firebase-project <id>    Proyecto de Firebase (VOXON_FIREBASE_PROJECT)
              --firebase-api-key <clave> Clave web del proyecto (VOXON_FIREBASE_API_KEY)
              --firebase-emulator <host> Usa los emuladores de Firebase de ese equipo (VOXON_FIREBASE_EMULATOR)
              --cloud-interval <seg>     Cada cuánto revisar si hay algo que subir (VOXON_CLOUD_INTERVAL). Por defecto 60

              --help                     Muestra esta ayuda
            """;

    public static ServerConfig fromArgs(String[] args, Map<String, String> env) {
        Arguments arguments = new Arguments(args);
        Path home = Path.of(System.getProperty("user.home"), "VOXON90");

        Path database = Path.of(arguments.value("--db", env.getOrDefault("VOXON_DB", home.resolve("voxon90.db").toString())));
        String bind = arguments.value("--bind", env.getOrDefault("VOXON_BIND", "0.0.0.0"));
        int port = parsePort(arguments.value("--port", env.getOrDefault("VOXON_PORT", "8090")), "--port");
        String web = arguments.value("--web-dir", env.getOrDefault("VOXON_WEB_DIR", System.getProperty("voxon.web.dir", "")));
        Path backups = Path.of(arguments.value("--backup-dir",
                env.getOrDefault("VOXON_BACKUP_DIR", home.resolve("respaldos").toString())));
        String library = arguments.value("--core-lib", env.getOrDefault("VOXON_CORE_LIBRARY", ""));
        int discoveryPort = parsePort(arguments.value("--discovery-port",
                env.getOrDefault("VOXON_DISCOVERY_PORT", String.valueOf(Discovery.DEFAULT_PORT))), "--discovery-port");
        int iterations = parsePositive(arguments.value("--pin-iterations", "20000"), "--pin-iterations");
        boolean discovery = !arguments.flag("--no-discovery");
        String firebaseProject = blankToNull(arguments.value("--firebase-project",
                env.getOrDefault("VOXON_FIREBASE_PROJECT", "")));
        String firebaseApiKey = blankToNull(arguments.value("--firebase-api-key",
                env.getOrDefault("VOXON_FIREBASE_API_KEY", "")));
        String firebaseEmulator = blankToNull(arguments.value("--firebase-emulator",
                env.getOrDefault("VOXON_FIREBASE_EMULATOR", "")));
        int cloudInterval = parsePositive(arguments.value("--cloud-interval",
                env.getOrDefault("VOXON_CLOUD_INTERVAL", "60")), "--cloud-interval");
        arguments.requireAllUsed();

        Path webDir = web.isBlank() ? null : Path.of(web);
        if (webDir != null && !Files.isDirectory(webDir)) {
            throw new IllegalArgumentException("La carpeta web no existe: " + webDir);
        }
        if (firebaseEmulator != null && firebaseProject == null) {
            firebaseProject = EMULATOR_PROJECT;
        }
        if (firebaseProject != null && firebaseEmulator == null && firebaseApiKey == null) {
            throw new IllegalArgumentException("Falta --firebase-api-key para el proyecto " + firebaseProject);
        }
        if (firebaseApiKey != null && firebaseProject == null) {
            throw new IllegalArgumentException("Falta --firebase-project para la clave de Firebase");
        }
        if (cloudInterval < 5) {
            throw new IllegalArgumentException("--cloud-interval debe ser de al menos 5 segundos");
        }
        return new ServerConfig(database, bind, port, webDir, backups, library.isBlank() ? null : Path.of(library),
                discovery, discoveryPort, iterations, firebaseProject, firebaseApiKey, firebaseEmulator, cloudInterval);
    }

    /** Hay un proyecto de Firebase configurado para la app del dueño. */
    public boolean cloudEnabled() {
        return firebaseProjectId != null;
    }

    public FirebaseSettings firebaseSettings() {
        if (!cloudEnabled()) {
            throw new IllegalStateException("No hay proyecto de Firebase configurado");
        }
        return firebaseEmulatorHost != null
                ? FirebaseSettings.emulator(firebaseEmulatorHost, firebaseProjectId)
                : FirebaseSettings.production(firebaseProjectId, firebaseApiKey);
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }

    private static int parsePort(String value, String option) {
        int port = parsePositive(value, option);
        if (port > 65535) {
            throw new IllegalArgumentException(option + " debe estar entre 0 y 65535");
        }
        return port;
    }

    private static int parsePositive(String value, String option) {
        try {
            int number = Integer.parseInt(value.trim());
            if (number < 0) {
                throw new NumberFormatException();
            }
            return number;
        } catch (NumberFormatException e) {
            throw new IllegalArgumentException(option + " debe ser un número entero válido: " + value);
        }
    }

    /** Lectura simple de argumentos con detección de opciones desconocidas. */
    private static final class Arguments {
        private final String[] args;
        private final boolean[] used;

        Arguments(String[] args) {
            this.args = args;
            this.used = new boolean[args.length];
        }

        String value(String name, String fallback) {
            for (int i = 0; i < args.length; i++) {
                if (args[i].startsWith(name + "=")) {
                    used[i] = true;
                    return args[i].substring(name.length() + 1);
                }
                if (args[i].equals(name)) {
                    if (i + 1 >= args.length) {
                        throw new IllegalArgumentException("Falta el valor de " + name);
                    }
                    used[i] = true;
                    used[i + 1] = true;
                    return args[i + 1];
                }
            }
            return fallback;
        }

        boolean flag(String name) {
            for (int i = 0; i < args.length; i++) {
                if (args[i].equals(name)) {
                    used[i] = true;
                    return true;
                }
            }
            return false;
        }

        void requireAllUsed() {
            for (int i = 0; i < args.length; i++) {
                if (!used[i]) {
                    throw new IllegalArgumentException("Opción desconocida: " + args[i]);
                }
            }
        }
    }
}
