package com.voxon.server;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import com.voxon.core.VoxonCore;
import com.voxon.server.json.Json;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Clock;
import java.time.Duration;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

/** Pruebas de punta a punta con el motor C++ real y una base en memoria. */
class ApiServerTest {
    private static final String SETUP = """
            {"method":"business.setup","params":{
              "business":{"name":"Colmado La Esquina","businessType":"colmado"},
              "owner":{"name":"Ana","pin":"1111"}}}
            """;

    @TempDir
    Path temp;

    private VoxonCore core;
    private EventBus events;
    private SessionStore sessions;
    private ApiServer server;
    private HttpClient client;

    @BeforeEach
    void start() throws IOException {
        core = VoxonCore.open(":memory:", "{\"pinIterations\":1,\"loginMaxFailures\":5}");
        events = new EventBus(1);
        sessions = new SessionStore(Duration.ofHours(1), Clock.systemUTC());
        Path web = Files.createDirectories(temp.resolve("web"));
        Files.writeString(web.resolve("index.html"), "<h1>VOXON90</h1>");
        Files.writeString(temp.resolve("secreto.txt"), "no debe verse");
        server = new ApiServer(core, sessions, events, new InetSocketAddress("127.0.0.1", 0), web,
                temp.resolve("respaldos"));
        server.start();
        client = HttpClient.newHttpClient();
    }

    @AfterEach
    void stop() {
        events.close();
        server.close();
        core.close();
    }

    private URI uri(String path) {
        return URI.create("http://127.0.0.1:" + server.port() + path);
    }

    private HttpResponse<String> get(String path) throws Exception {
        return client.send(HttpRequest.newBuilder(uri(path)).GET().build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> post(String path, String body, String token) throws Exception {
        HttpRequest.Builder request = HttpRequest.newBuilder(uri(path)).POST(HttpRequest.BodyPublishers.ofString(body));
        if (token != null) {
            request.header("Authorization", "Bearer " + token);
        }
        return client.send(request.build(), HttpResponse.BodyHandlers.ofString());
    }

    private HttpResponse<String> call(String method, Map<String, Object> params, String token) throws Exception {
        return post("/api/call", Json.stringify(Json.object("method", method, "params", params)), token);
    }

    private static Map<String, Object> body(HttpResponse<String> response) {
        return Json.parseObject(response.body());
    }

    private static String errorCode(HttpResponse<String> response) {
        return Json.stringOrNull(Json.objectOrEmpty(body(response), "error"), "code");
    }

    private String login(String pin) throws Exception {
        HttpResponse<String> response = post("/api/login", Json.stringify(Json.object("pin", pin)), null);
        assertEquals(200, response.statusCode(), response.body());
        return Json.stringOrNull(Json.objectOrEmpty(body(response), "result"), "token");
    }

    private String setupAndLogin() throws Exception {
        assertEquals(200, post("/api/call", SETUP, null).statusCode());
        return login("1111");
    }

    @Test
    void saludYConfiguracionInicialSinSesion() throws Exception {
        HttpResponse<String> health = get("/api/health");
        assertEquals(200, health.statusCode());
        Map<String, Object> engine = Json.objectOrEmpty(body(health), "engine");
        assertEquals(3L, engine.get("schemaVersion"));
        assertFalse(engine.containsKey("databasePath"));

        HttpResponse<String> status = call("business.status", Json.object(), null);
        assertEquals(false, Json.objectOrEmpty(body(status), "result").get("configured"));
        assertEquals(200, post("/api/call", SETUP, null).statusCode());
    }

    @Test
    void elLoginDaUnTokenQueLosMetodosPrivadosExigen() throws Exception {
        String token = setupAndLogin();

        HttpResponse<String> withoutToken = call("users.list", Json.object(), null);
        assertEquals(401, withoutToken.statusCode());
        assertEquals("unauthorized", errorCode(withoutToken));

        HttpResponse<String> withToken = call("users.list", Json.object(), token);
        assertEquals(200, withToken.statusCode());
        assertEquals(1, ((List<?>) body(withToken).get("result")).size());

        assertEquals(401, post("/api/login", "{\"pin\":\"9999\"}", null).statusCode());
        assertEquals(200, post("/api/logout", "", token).statusCode());
        assertEquals(401, call("users.list", Json.object(), token).statusCode());
    }

    @Test
    void traduceLosErroresDelMotorAEstadosHttp() throws Exception {
        String token = setupAndLogin();
        assertEquals(404, call("no.existe", Json.object(), token).statusCode());

        HttpResponse<String> invalid = call("catalog.products.create", Json.object("priceCents", 100L), token);
        assertEquals(400, invalid.statusCode());
        assertEquals("validation_failed", errorCode(invalid));

        HttpResponse<String> closed = call("cash.movement",
                Json.object("kind", "cash_in", "amountCents", 100L, "reason", "Menudo"), token);
        assertEquals(409, closed.statusCode());
        assertEquals("cash_session_closed", errorCode(closed));

        assertEquals(400, call("users.login", Json.object("pin", "1111"), null).statusCode());
        assertEquals(405, get("/api/call").statusCode());
        assertEquals(400, post("/api/call", "{no es json", token).statusCode());
        assertEquals(404, get("/api/otra").statusCode());
    }

    @Test
    void losCambiosSeAvisanPorEventosEnVivo() throws Exception {
        String token = setupAndLogin();
        assertEquals(401, get("/api/events").statusCode());

        HttpRequest subscribe = HttpRequest.newBuilder(uri("/api/events?token=" + token)).GET().build();
        HttpResponse<Stream<String>> stream =
                client.sendAsync(subscribe, HttpResponse.BodyHandlers.ofLines()).get(3, TimeUnit.SECONDS);
        assertEquals(200, stream.statusCode());

        ExecutorService reader = Executors.newSingleThreadExecutor();
        try {
            Future<String> event = reader.submit(() -> {
                Iterator<String> lines = stream.body().iterator();
                while (lines.hasNext()) {
                    String line = lines.next();
                    if (line.contains("catalog.categories.create")) {
                        return line;
                    }
                }
                return null;
            });
            long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3);
            while (events.subscriberCount() == 0 && System.nanoTime() < deadline) {
                Thread.sleep(20);
            }
            assertEquals(200, call("catalog.categories.create", Json.object("name", "Bebidas"), token).statusCode());
            String line = event.get(3, TimeUnit.SECONDS);
            assertTrue(line.startsWith("data: "), line);
        } finally {
            reader.shutdownNow();
        }
    }

    @Test
    void sirveElClienteWebSinSalirDeSuCarpeta() throws Exception {
        HttpResponse<String> index = get("/");
        assertEquals(200, index.statusCode());
        assertTrue(index.body().contains("VOXON90"));
        assertTrue(index.headers().firstValue("Content-Type").orElse("").startsWith("text/html"));

        assertEquals(404, get("/%2e%2e/secreto.txt").statusCode());
        assertEquals(404, get("/no-existe.js").statusCode());
    }

    @Test
    void losRespaldosSoloSeGuardanEnLaCarpetaConfigurada() throws Exception {
        String token = setupAndLogin();
        HttpResponse<String> outside = call("system.backup", Json.object("path", "../fuera.db"), token);
        assertEquals(400, outside.statusCode());

        assertEquals(200, call("system.backup", Json.object("path", "cierre.db"), token).statusCode());
        assertTrue(Files.exists(temp.resolve("respaldos").resolve("cierre.db")));

        HttpResponse<String> automatic = call("system.backup", Json.object(), token);
        assertEquals(200, automatic.statusCode());
        String path = Json.stringOrNull(Json.objectOrEmpty(body(automatic), "result"), "path");
        assertTrue(Path.of(path).startsWith(temp.resolve("respaldos").toAbsolutePath()), path);
    }

    @Test
    void desactivarUnEmpleadoCierraSusSesiones() throws Exception {
        String owner = setupAndLogin();
        HttpResponse<String> created = call("users.create",
                Json.object("name", "Luis", "role", "cashier", "pin", "2222"), owner);
        String cashierId = Json.stringOrNull(Json.objectOrEmpty(body(created), "result"), "id");
        String cashier = login("2222");
        assertEquals(200, call("cash.current", Json.object(), cashier).statusCode());

        assertEquals(200, call("users.deactivate", Json.object("id", cashierId), owner).statusCode());
        assertEquals(401, call("cash.current", Json.object(), cashier).statusCode());
    }

    @Test
    void sinFirebaseLaAppDelDuenoSeIndicaApagada() throws Exception {
        String owner = setupAndLogin();

        HttpResponse<String> status = call("cloud.status", Json.object(), owner);
        assertEquals(200, status.statusCode());
        Map<String, Object> result = Json.objectOrEmpty(body(status), "result");
        assertEquals(false, result.get("configured"));
        assertEquals(false, result.get("linked"));

        HttpResponse<String> link = call("cloud.link", Json.object("code", "ABCD2345"), owner);
        assertEquals(409, link.statusCode());
        assertEquals("cloud_not_configured", errorCode(link));
    }

    @Test
    void soloElDuenoAdministraLaAppDelDueno() throws Exception {
        String owner = setupAndLogin();
        assertEquals(200, call("users.create",
                Json.object("name", "Luis", "role", "cashier", "pin", "2222"), owner).statusCode());
        String cashier = login("2222");

        HttpResponse<String> status = call("cloud.status", Json.object(), cashier);
        assertEquals(403, status.statusCode());
        assertEquals("forbidden", errorCode(status));
        assertEquals(403, call("cloud.unlink", Json.object(), cashier).statusCode());
        assertEquals(401, call("cloud.status", Json.object(), null).statusCode());
    }
}
