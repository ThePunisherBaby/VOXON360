package com.voxon.server.cloud;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import com.voxon.core.CoreGateway;
import com.voxon.server.json.Json;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/** Sincronización contra un Firebase falso en localhost y un motor falso. */
class CloudSyncTest {
    private static final String ROOT = "/v1/projects/demo-voxon90/databases/(default)/documents";

    @TempDir
    Path temp;

    private final TestClock clock = new TestClock();
    private final List<String> commits = new CopyOnWriteArrayList<>();
    private final List<String> deletes = new CopyOnWriteArrayList<>();
    private final Map<String, Map<String, Object>> linkCodes = new ConcurrentHashMap<>();
    private final AtomicInteger signUps = new AtomicInteger();
    private final AtomicInteger refreshes = new AtomicInteger();
    private final List<CloudSync> created = new ArrayList<>();
    private volatile int commitStatus = 200;
    private volatile String coreResponse = ok(snapshot(17700L));
    private volatile String lastActor;
    private HttpServer firebase;

    private final CoreGateway core = request -> {
        lastActor = Json.stringOrNull(Json.parseObject(request), "actor");
        return coreResponse;
    };

    @BeforeEach
    void start() throws IOException {
        firebase = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        firebase.createContext("/auth/accounts:signUp", exchange -> {
            signUps.incrementAndGet();
            respond(exchange, 200, Json.object("localId", "caja-uid", "idToken", "token-1",
                    "refreshToken", "renovar-1", "expiresIn", "3600"));
        });
        firebase.createContext("/token", exchange -> {
            refreshes.incrementAndGet();
            respond(exchange, 200, Json.object("user_id", "caja-uid", "id_token", "token-2",
                    "refresh_token", "renovar-2", "expires_in", "3600"));
        });
        firebase.createContext("/v1/", exchange -> {
            String path = exchange.getRequestURI().getPath();
            String body = new String(exchange.getRequestBody().readAllBytes(), StandardCharsets.UTF_8);
            String auth = exchange.getRequestHeaders().getFirst("Authorization");
            if (path.equals(ROOT + ":commit")) {
                commits.add(body + " auth=" + auth);
                respond(exchange, commitStatus, commitStatus == 200
                        ? Json.object("commitTime", "2026-09-11T15:00:00Z")
                        : Json.object("error", Json.object("code", (long) commitStatus, "message", "UNAVAILABLE")));
            } else if (path.startsWith(ROOT + "/linkCodes/") && "GET".equals(exchange.getRequestMethod())) {
                Map<String, Object> fields = linkCodes.get(path.substring((ROOT + "/linkCodes/").length()));
                if (fields == null) {
                    respond(exchange, 404, Json.object("error", Json.object("code", 404L, "message", "NOT_FOUND")));
                } else {
                    respond(exchange, 200, Json.object("fields", FirestoreValues.encodeFields(fields)));
                }
            } else if ("DELETE".equals(exchange.getRequestMethod())) {
                deletes.add(path);
                respond(exchange, 200, Json.object());
            } else {
                respond(exchange, 404, Json.object());
            }
        });
        firebase.start();
    }

    @AfterEach
    void stop() {
        created.forEach(CloudSync::close);
        firebase.stop(0);
    }

    @Test
    void vinculaConElCodigoYSubeElResumen() throws IOException {
        addLinkCode("ABCD2345", clock.instant().plusSeconds(600));
        CloudSync sync = newSync();

        Map<String, Object> status = sync.link(" abcd-2345 ", "u-owner");

        assertEquals(true, status.get("linked"));
        assertEquals("ok", status.get("state"), String.valueOf(status.get("lastError")));
        assertEquals("negocio1", status.get("businessId"));
        assertEquals(1, signUps.get());
        assertEquals("u-owner", lastActor);
        assertEquals(2, commits.size());
        assertTrue(commits.get(0).contains("documents/businesses/negocio1/devices/caja-uid\""));
        assertTrue(commits.get(0).contains("\"linkCode\":{\"stringValue\":\"ABCD2345\"}"));
        String documents = commits.get(1);
        for (String document : List.of("snapshots/status", "days/2026-09-11", "days/2026-09-10", "snapshots/cash",
                "snapshots/inventory", "snapshots/receivables")) {
            assertTrue(documents.contains("documents/businesses/negocio1/" + document + "\""), document);
        }
        assertTrue(documents.contains("\"totalCents\":{\"integerValue\":\"17700\"}"));
        assertTrue(documents.endsWith("auth=Bearer token-1"));

        // El vínculo sobrevive a un reinicio del servidor.
        assertTrue(Files.readString(temp.resolve("vinculo-nube.json")).contains("renovar-1"));
        Map<String, Object> restarted = newSync().status();
        assertEquals(true, restarted.get("linked"));
        assertEquals("pending", restarted.get("state"));
    }

    @Test
    void soloSubeLosDocumentosQueCambiaron() {
        CloudSync sync = linkedSync();

        sync.syncNow();
        assertTrue(commits.isEmpty(), "sin cambios no se escribe nada");

        coreResponse = ok(snapshot(29500L));
        sync.markDirty();
        sync.syncNow();

        assertEquals(1, commits.size());
        String body = commits.get(0);
        assertTrue(body.contains("days/2026-09-11\""));
        assertTrue(body.contains("snapshots/status\""));
        assertFalse(body.contains("days/2026-09-10\""));
        assertFalse(body.contains("snapshots/cash\""));
        assertFalse(body.contains("snapshots/inventory\""));
    }

    @Test
    void avisaQueSigueEnLineaYRenuevaElToken() {
        CloudSync sync = linkedSync();

        clock.advance(Duration.ofMinutes(16));
        sync.tick();
        assertEquals(1, commits.size());
        assertTrue(commits.get(0).contains("snapshots/status\""));
        assertFalse(commits.get(0).contains("days/"));
        assertEquals(0, refreshes.get());

        clock.advance(Duration.ofHours(2));
        coreResponse = ok(snapshot(40000L));
        sync.markDirty();
        sync.tick();
        assertEquals(1, refreshes.get());
        assertTrue(commits.get(1).endsWith("auth=Bearer token-2"));
        assertTrue(readLink().contains("renovar-2"));
    }

    @Test
    void sinInternetQuedaPendienteYReintentaDespues() {
        CloudSync sync = linkedSync();

        commitStatus = 503;
        coreResponse = ok(snapshot(29500L));
        sync.markDirty();
        Map<String, Object> failed = sync.syncNow();
        assertEquals("offline", failed.get("state"));
        assertEquals(true, failed.get("pending"));

        commitStatus = 200;
        sync.tick();
        assertEquals(1, commits.size(), "espera antes de reintentar");

        clock.advance(Duration.ofSeconds(31));
        sync.tick();
        assertEquals(2, commits.size());
        assertEquals("ok", sync.status().get("state"));
        assertEquals(false, sync.status().get("pending"));
    }

    @Test
    void rechazaCodigosInvalidosOVencidos() {
        CloudSync sync = newSync();

        assertEquals("validation_failed",
                assertThrows(CloudException.class, () -> sync.link("123", "u-owner")).code());
        assertEquals("invalid_link_code",
                assertThrows(CloudException.class, () -> sync.link("ZZZZ9999", "u-owner")).code());
        addLinkCode("ABCD2345", clock.instant().minusSeconds(60));
        assertEquals("invalid_link_code",
                assertThrows(CloudException.class, () -> sync.link("ABCD2345", "u-owner")).code());

        assertEquals(false, sync.status().get("linked"));
        assertTrue(commits.isEmpty());
    }

    @Test
    void siElDuenoYaNoEstaActivoLoIndica() {
        CloudSync sync = linkedSync();
        coreResponse = "{\"ok\":false,\"error\":{\"code\":\"unauthorized\",\"message\":\"Empleado inactivo\"}}";

        Map<String, Object> status = sync.syncNow();

        assertEquals("error", status.get("state"));
        assertTrue(String.valueOf(status.get("lastError")).contains("vuelve a vincular"));
        assertTrue(commits.isEmpty());
    }

    @Test
    void desvincularQuitaElEquipoYElArchivo() {
        CloudSync sync = linkedSync();

        Map<String, Object> status = sync.unlink();

        assertEquals(false, status.get("linked"));
        assertEquals(List.of(ROOT + "/businesses/negocio1/devices/caja-uid"), deletes);
        assertFalse(Files.exists(temp.resolve("vinculo-nube.json")));
    }

    private CloudSync newSync() {
        String base = "http://127.0.0.1:" + firebase.getAddress().getPort();
        FirebaseSettings settings = new FirebaseSettings("demo-voxon90", "clave", base + "/auth", base, base + "/v1");
        CloudSync sync = new CloudSync(core, new FirebaseClient(settings, clock),
                new CloudLinkStore(temp.resolve("vinculo-nube.json")), clock, Duration.ofSeconds(60));
        created.add(sync);
        return sync;
    }

    /** Vinculada y con el primer resumen ya subido; las escrituras de ese paso no cuentan. */
    private CloudSync linkedSync() {
        addLinkCode("ABCD2345", clock.instant().plusSeconds(600));
        CloudSync sync = newSync();
        assertEquals("ok", sync.link("ABCD2345", "u-owner").get("state"));
        commits.clear();
        return sync;
    }

    private void addLinkCode(String code, Instant expiresAt) {
        linkCodes.put(code, Json.object("businessId", "negocio1", "ownerUid", "dueno",
                "expiresAt", new FirestoreValues.Timestamp(expiresAt)));
    }

    private String readLink() {
        try {
            return Files.readString(temp.resolve("vinculo-nube.json"));
        } catch (IOException e) {
            throw new AssertionError(e);
        }
    }

    private static String ok(Map<String, Object> result) {
        return Json.stringify(Json.object("ok", true, "result", result));
    }

    static Map<String, Object> snapshot(long todayTotalCents) {
        return Json.object(
                "generatedAt", "2026-09-11T15:00:00.000Z",
                "business", Json.object("name", "Colmado La Esquina", "businessType", "colmado", "rnc", null),
                "openCashSession", null,
                "openOrders", 0L,
                "lowStockCount", 0L,
                "receivablesCents", 5900L,
                "days", List.of(day("2026-09-11", todayTotalCents), day("2026-09-10", 0L)),
                "cashSessions", List.of(),
                "lowStock", List.of(),
                "receivables", List.of());
    }

    private static Map<String, Object> day(String day, long totalCents) {
        return Json.object("day", day, "sales", Json.object("count", totalCents > 0 ? 1L : 0L, "totalCents", totalCents));
    }

    private static void respond(HttpExchange exchange, int status, Object body) throws IOException {
        byte[] bytes = Json.stringify(body).getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json");
        exchange.sendResponseHeaders(status, bytes.length);
        try (OutputStream out = exchange.getResponseBody()) {
            out.write(bytes);
        }
    }

    private static final class TestClock extends Clock {
        private volatile Instant now = Instant.parse("2026-09-11T15:00:00Z");

        void advance(Duration duration) {
            now = now.plus(duration);
        }

        @Override
        public ZoneId getZone() {
            return ZoneOffset.UTC;
        }

        @Override
        public Clock withZone(ZoneId zone) {
            return this;
        }

        @Override
        public Instant instant() {
            return now;
        }
    }
}
