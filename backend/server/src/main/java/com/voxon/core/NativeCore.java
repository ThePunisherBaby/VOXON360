package com.voxon.core;

/**
 * Métodos nativos de libvoxoncore (ver backend/core/src/jni_bridge.cpp).
 *
 * <p>Los textos viajan como UTF-8 en {@code byte[]} para no depender del
 * "UTF-8 modificado" de JNI.
 */
final class NativeCore {
    private NativeCore() {
    }

    static native byte[] version();

    /** Devuelve el identificador del motor o lanza IllegalStateException con el error en JSON. */
    static native long open(byte[] pathUtf8, byte[] optionsUtf8);

    static native byte[] execute(long handle, byte[] requestUtf8);

    static native void close(long handle);
}
