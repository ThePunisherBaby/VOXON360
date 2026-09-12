package com.voxon.server.cloud;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

import com.voxon.core.CoreGateway;
import com.voxon.server.json.Json;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.junit.jupiter.api.io.TempDir;

/**
 * Sincronización contra los emuladores reales de Firebase y las reglas de {@code firebase/firestore.rules}.
 *
 * <pre>
 * cd firebase && firebase emulators:exec --only auth,firestore \
 *   "cd ../backend/server && VOXON_FIREBASE_EMULATOR=127.0.0.1 ./gradlew test --tests '*CloudEmulatorTest'"
 * </pre>
 */
@EnabledIfEnvironmentVariable(named = "VOXON_FIREBASE_EMULATOR", matches = ".+")
class CloudEmulatorTest {
    /** Con el token "owner" el emulador de Firestore ignora las reglas: sirve para preparar y revisar datos. */
    private static final String ADMIN = "owner";
    private static final String ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private static final SecureRandom RANDOM = new SecureRandom();

    @TempDir
    Path temp;

    private final Clock clock = Clock.systemUTC();
    private final FirebaseSettings settings = FirebaseSettings.emulator(System.getenv("VOXON_FIREBASE_EMULATOR"),
            "demo-voxon90");
    private final FirebaseClient admin = new FirebaseClient(settings, clock);
    private final CoreGateway core = request -> Json.stringify(Json.object("ok", true,
            "result", CloudSyncTest.snapshot(17700L)));

    @Test
    void laCajaVinculadaEscribeSoloLosResumenesDeSuNegocio() {
        String businessId = "negocio-" + System.nanoTime();
        String code = newCode(businessId, 600);

        try (CloudSync sync = newSync("vinculo.json")) {
            Map<String, Object> status = sync.link(code, "u-owner");
            assertEquals("ok", status.get("state"), String.valueOf(status.get("lastError")));

            Map<String, Object> day = admin.getDocument(ADMIN, "businesses/" + businessId + "/days/2026-09-11");
            assertEquals(17700L, Json.objectOrEmpty(day, "sales").get("totalCents"));
            Map<String, Object> summary = admin.getDocument(ADMIN, "businesses/" + businessId + "/snapshots/status");
            assertEquals("Colmado La Esquina", summary.get("businessName"));

            // Otra caja que no se vinculó no puede escribir en ese negocio.
            FirebaseClient.AuthTokens intruder = admin.signUpAnonymously();
            CloudException denied = assertThrows(CloudException.class, () -> admin.commit(intruder.idToken(), List.of(
                    new FirebaseClient.DocumentWrite("businesses/" + businessId + "/days/2026-09-12",
                            Json.object("day", "2026-09-12")))));
            assertEquals("cloud_permission_denied", denied.code());

            Map<String, Object> unlinked = sync.unlink();
            assertEquals(false, unlinked.get("linked"));
        }
    }

    @Test
    void unCodigoVencidoNoVincula() {
        String businessId = "negocio-" + System.nanoTime();
        String expired = newCode(businessId, -60);

        try (CloudSync sync = newSync("vencido.json")) {
            CloudException error = assertThrows(CloudException.class, () -> sync.link(expired, "u-owner"));
            assertEquals("invalid_link_code", error.code());
        }
        assertNull(admin.getDocument(ADMIN, "businesses/" + businessId + "/snapshots/status"));
    }

    private CloudSync newSync(String linkFile) {
        return new CloudSync(core, new FirebaseClient(settings, clock), new CloudLinkStore(temp.resolve(linkFile)),
                clock, Duration.ofMinutes(1));
    }

    /** Negocio del dueño "dueno" y un código que vence en {@code seconds}. */
    private String newCode(String businessId, long seconds) {
        StringBuilder code = new StringBuilder();
        for (int i = 0; i < 8; i++) {
            code.append(ALPHABET.charAt(RANDOM.nextInt(ALPHABET.length())));
        }
        admin.commit(ADMIN, List.of(
                new FirebaseClient.DocumentWrite("businesses/" + businessId,
                        Json.object("name", "Colmado La Esquina", "ownerUids", List.of("dueno"))),
                new FirebaseClient.DocumentWrite("linkCodes/" + code, Json.object(
                        "businessId", businessId,
                        "ownerUid", "dueno",
                        "expiresAt", new FirestoreValues.Timestamp(clock.instant().plusSeconds(seconds))))));
        return code.toString();
    }
}
