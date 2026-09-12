package com.voxon.server;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.Map;
import org.junit.jupiter.api.Test;

class ServerConfigTest {
    @Test
    void sinFirebaseLaNubeQuedaApagada() {
        ServerConfig config = ServerConfig.fromArgs(new String[0], Map.of());

        assertFalse(config.cloudEnabled());
        assertEquals(60, config.cloudIntervalSeconds());
    }

    @Test
    void proyectoYClaveActivanLaNube() {
        ServerConfig config = ServerConfig.fromArgs(new String[] {"--firebase-project", "voxon90-prod",
                "--cloud-interval=120"}, Map.of("VOXON_FIREBASE_API_KEY", "clave-web"));

        assertTrue(config.cloudEnabled());
        assertEquals(120, config.cloudIntervalSeconds());
        assertEquals("https://firestore.googleapis.com/v1", config.firebaseSettings().firestoreUrl());
        assertEquals("clave-web", config.firebaseSettings().apiKey());
    }

    @Test
    void losEmuladoresNoNecesitanClave() {
        ServerConfig config = ServerConfig.fromArgs(new String[] {"--firebase-emulator", "127.0.0.1"}, Map.of());

        assertEquals(ServerConfig.EMULATOR_PROJECT, config.firebaseProjectId());
        assertEquals("http://127.0.0.1:8080/v1", config.firebaseSettings().firestoreUrl());
        assertEquals("http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1",
                config.firebaseSettings().identityToolkitUrl());
    }

    @Test
    void faltaLaClaveOElProyecto() {
        assertThrows(IllegalArgumentException.class,
                () -> ServerConfig.fromArgs(new String[] {"--firebase-project", "voxon90-prod"}, Map.of()));
        assertThrows(IllegalArgumentException.class,
                () -> ServerConfig.fromArgs(new String[] {"--firebase-api-key", "clave"}, Map.of()));
        assertThrows(IllegalArgumentException.class,
                () -> ServerConfig.fromArgs(new String[] {"--firebase-emulator", "127.0.0.1", "--cloud-interval", "1"},
                        Map.of()));
    }
}
