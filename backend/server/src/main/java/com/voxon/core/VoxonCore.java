package com.voxon.core;

import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.Objects;

/**
 * Motor local de VOXON90 cargado por JNI.
 *
 * <p>Seguro para varios hilos: las solicitudes se atienden de una en una.
 */
public final class VoxonCore implements CoreGateway, AutoCloseable {
    private static boolean libraryLoaded;

    private long handle;

    private VoxonCore(long handle) {
        this.handle = handle;
    }

    /**
     * Carga libvoxoncore desde {@code explicitPath}, desde la propiedad
     * {@code voxon.core.library} o, si no hay ninguna, desde {@code java.library.path}.
     */
    public static synchronized void loadLibrary(Path explicitPath) {
        if (libraryLoaded) {
            return;
        }
        String configured = explicitPath != null ? explicitPath.toString() : System.getProperty("voxon.core.library");
        if (configured != null && !configured.isBlank()) {
            System.load(Path.of(configured).toAbsolutePath().toString());
        } else {
            System.loadLibrary("voxoncore");
        }
        libraryLoaded = true;
    }

    /**
     * Abre o crea la base de datos y aplica migraciones.
     *
     * @param optionsJson opciones del motor, p. ej. {@code {"pinIterations": 20000}}; puede ser null
     * @throws IllegalStateException con la respuesta de error en JSON si no se puede abrir
     */
    public static VoxonCore open(String databasePath, String optionsJson) {
        Objects.requireNonNull(databasePath, "databasePath");
        loadLibrary(null);
        long handle = NativeCore.open(utf8(databasePath), utf8(optionsJson == null ? "" : optionsJson));
        return new VoxonCore(handle);
    }

    public static String version() {
        loadLibrary(null);
        return new String(NativeCore.version(), StandardCharsets.UTF_8);
    }

    @Override
    public synchronized String execute(String requestJson) {
        Objects.requireNonNull(requestJson, "requestJson");
        if (handle == 0) {
            throw new IllegalStateException("El motor está cerrado");
        }
        return new String(NativeCore.execute(handle, utf8(requestJson)), StandardCharsets.UTF_8);
    }

    @Override
    public synchronized void close() {
        if (handle != 0) {
            NativeCore.close(handle);
            handle = 0;
        }
    }

    private static byte[] utf8(String text) {
        return text.getBytes(StandardCharsets.UTF_8);
    }
}
