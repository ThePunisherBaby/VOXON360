package com.voxon.core;

/** Acceso al motor con solicitudes y respuestas JSON. Permite usar un motor falso en pruebas. */
@FunctionalInterface
public interface CoreGateway {
    String execute(String requestJson);
}
