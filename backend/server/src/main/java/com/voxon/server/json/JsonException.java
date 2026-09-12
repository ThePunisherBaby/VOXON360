package com.voxon.server.json;

/** JSON inválido o un valor que no se puede representar en JSON. */
public final class JsonException extends RuntimeException {
    private static final long serialVersionUID = 1L;

    public JsonException(String message) {
        super(message);
    }
}
