package com.voxon.server;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import com.voxon.core.CoreGateway;
import com.voxon.server.cloud.CloudException;
import com.voxon.server.cloud.CloudService;
import com.voxon.server.json.Json;
import com.voxon.server.json.JsonException;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetSocketAddress;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * API HTTP local sobre el motor.
 *
 * <pre>
 * GET  /api/health            estado del servidor y del motor
 * POST /api/login             {"pin": "1234"} → {"token", "user"}
 * POST /api/logout            cierra la sesión del token
 * POST /api/call              {"method", "params"} con Authorization: Bearer &lt;token&gt;
 * GET  /api/events?token=...  eventos en vivo (Server-Sent Events)
 * GET  /...                   cliente web local
 * </pre>
 *
 * <p>{@code cloud.status}, {@code cloud.link} y {@code cloud.unlink} (vínculo con la app del dueño en
 * Firebase) los atiende este servidor; los demás métodos van al motor.
 */
public final class ApiServer implements AutoCloseable {
    private static final Logger LOG = Logger.getLogger(ApiServer.class.getName());
    private static final int MAX_BODY_BYTES = 1 << 20;

    /** Métodos que se usan antes de iniciar sesión. */
    private static final Set<String> PUBLIC_METHODS = Set.of("system.info", "business.status", "business.setup");

    /** Métodos del servicio en la nube que atiende el servidor. */
    private static final Set<String> CLOUD_METHODS = Set.of("cloud.status", "cloud.link", "cloud.unlink");

    /** Últimos segmentos de métodos que solo leen: no generan eventos. */
    private static final Set<String> READ_ONLY = Set.of("list", "get", "queue", "current", "status", "info",
            "statement", "quote", "report", "sessions", "dashboard", "salesByDay", "productSales", "paymentsByDay",
            "cashiers", "receivables", "audit", "lowStock", "movements", "integrityCheck", "salesReport",
            "purchasesReport", "backup", "snapshot");

    private final CoreGateway core;
    private final SessionStore sessions;
    private final EventBus events;
    private final Path backupDir;
    private final CloudService cloud;
    private final HttpServer http;
    private final ExecutorService executor;

    public ApiServer(CoreGateway core, SessionStore sessions, EventBus events, InetSocketAddress address, Path webDir,
            Path backupDir) throws IOException {
        this(core, sessions, events, address, webDir, backupDir, CloudService.disabled());
    }

    public ApiServer(CoreGateway core, SessionStore sessions, EventBus events, InetSocketAddress address, Path webDir,
            Path backupDir, CloudService cloud) throws IOException {
        this.core = core;
        this.sessions = sessions;
        this.events = events;
        this.backupDir = backupDir;
        this.cloud = cloud;
        AtomicInteger threads = new AtomicInteger();
        this.executor = Executors.newCachedThreadPool(runnable -> {
            Thread thread = new Thread(runnable, "voxon-http-" + threads.incrementAndGet());
            thread.setDaemon(true);
            return thread;
        });
        this.http = HttpServer.create(address, 64);
        http.setExecutor(executor);
        http.createContext("/api/", this::handleApi);
        if (webDir != null) {
            http.createContext("/", new StaticFiles(webDir));
        }
    }

    public void start() {
        http.start();
    }

    public int port() {
        return http.getAddress().getPort();
    }

    @Override
    public void close() {
        http.stop(0);
        executor.shutdownNow();
    }

    /** Error con estado HTTP y código estable, igual que los del motor. */
    private static final class HttpError extends RuntimeException {
        private static final long serialVersionUID = 1L;
        private final int status;
        private final String code;

        HttpError(int status, String code, String message) {
            super(message);
            this.status = status;
            this.code = code;
        }
    }

    private void handleApi(HttpExchange exchange) throws IOException {
        try {
            exchange.getResponseHeaders().set("X-Content-Type-Options", "nosniff");
            exchange.getResponseHeaders().set("Cache-Control", "no-store");
            String path = exchange.getRequestURI().getPath();
            switch (path) {
                case "/api/health" -> {
                    requireMethod(exchange, "GET");
                    health(exchange);
                }
                case "/api/login" -> {
                    requireMethod(exchange, "POST");
                    login(exchange);
                }
                case "/api/logout" -> {
                    requireMethod(exchange, "POST");
                    bearerToken(exchange).ifPresent(sessions::revoke);
                    sendJson(exchange, 200, Json.object("ok", true));
                }
                case "/api/call" -> {
                    requireMethod(exchange, "POST");
                    call(exchange);
                }
                case "/api/events" -> {
                    requireMethod(exchange, "GET");
                    subscribe(exchange);
                }
                default -> throw new HttpError(404, "not_found", "Ruta desconocida: " + path);
            }
        } catch (HttpError error) {
            sendError(exchange, error.status, error.code, error.getMessage());
        } catch (JsonException error) {
            sendError(exchange, 400, "invalid_request", "JSON inválido: " + error.getMessage());
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
        } catch (RuntimeException error) {
            LOG.log(Level.SEVERE, "Error atendiendo " + exchange.getRequestURI(), error);
            sendError(exchange, 500, "internal_error", "Error interno del servidor");
        } finally {
            exchange.close();
        }
    }

    private void health(HttpExchange exchange) throws IOException {
        Map<String, Object> info = Json.parseObject(core.execute("{\"method\":\"system.info\"}"));
        Map<String, Object> engine = Json.objectOrEmpty(info, "result");
        engine.remove("databasePath");
        sendJson(exchange, 200, Json.object("ok", true, "service", "voxon90", "engine", engine));
    }

    private void login(HttpExchange exchange) throws IOException {
        Map<String, Object> body = readJsonBody(exchange);
        String request = Json.stringify(Json.object("method", "users.login", "params", Json.object("pin", body.get("pin"))));
        Map<String, Object> response = Json.parseObject(core.execute(request));
        if (!Boolean.TRUE.equals(response.get("ok"))) {
            sendCoreError(exchange, response);
            return;
        }
        Map<String, Object> user = Json.objectOrEmpty(response, "result");
        SessionStore.Session session = sessions.create(Json.stringOrNull(user, "id"), Json.stringOrNull(user, "name"),
                Json.stringOrNull(user, "role"));
        sendJson(exchange, 200, Json.object("ok", true, "result", Json.object("token", session.token(), "user", user)));
    }

    private void call(HttpExchange exchange) throws IOException {
        Map<String, Object> body = readJsonBody(exchange);
        String method = Json.stringOrNull(body, "method");
        if (method == null || method.isBlank()) {
            throw new HttpError(400, "invalid_request", "Falta el campo 'method'");
        }
        if ("users.login".equals(method)) {
            throw new HttpError(400, "invalid_request", "Para iniciar sesión usa POST /api/login");
        }
        Map<String, Object> params = Json.objectOrEmpty(body, "params");
        Map<String, Object> request = Json.object("method", method, "params", params);

        Optional<SessionStore.Session> session = Optional.empty();
        if (!PUBLIC_METHODS.contains(method)) {
            Optional<String> token = bearerToken(exchange);
            session = token.flatMap(sessions::resolve);
            if (session.isEmpty()) {
                throw new HttpError(401, "unauthorized", "Inicia sesión con tu PIN");
            }
            request.put("actor", session.get().userId());
        }
        if (CLOUD_METHODS.contains(method)) {
            Map<String, Object> result = cloudCall(method, params, session.orElseThrow());
            if (!"cloud.status".equals(method)) {
                publishChange(method, session);
            }
            sendJson(exchange, 200, Json.object("ok", true, "result", result));
            return;
        }
        if ("system.backup".equals(method)) {
            params.put("path", backupPath(params.get("path")));
        }

        String responseText = core.execute(Json.stringify(request));
        Map<String, Object> response = Json.parseObject(responseText);
        if (!Boolean.TRUE.equals(response.get("ok"))) {
            if ("unauthorized".equals(Json.stringOrNull(Json.objectOrEmpty(response, "error"), "code"))) {
                bearerToken(exchange).ifPresent(sessions::revoke);
            }
            sendCoreError(exchange, response);
            return;
        }

        afterSuccess(method, params, session);
        sendText(exchange, 200, responseText);
    }

    /** El dueño vincula y desvincula; el gerente solo ve el estado. */
    private Map<String, Object> cloudCall(String method, Map<String, Object> params, SessionStore.Session session) {
        boolean owner = "owner".equals(session.role());
        boolean managerReading = "cloud.status".equals(method) && "manager".equals(session.role());
        if (!owner && !managerReading) {
            throw new HttpError(403, "forbidden", "Solo el dueño administra la app del dueño");
        }
        try {
            return switch (method) {
                case "cloud.link" -> cloud.link(Json.stringOrNull(params, "code"), session.userId());
                case "cloud.unlink" -> cloud.unlink();
                default -> cloud.status();
            };
        } catch (CloudException e) {
            throw new HttpError(statusFor(e.code()), e.code(), e.getMessage());
        }
    }

    private void afterSuccess(String method, Map<String, Object> params, Optional<SessionStore.Session> session) {
        if ("users.deactivate".equals(method) && params.get("id") instanceof String userId) {
            sessions.revokeUser(userId);
        }
        String verb = method.substring(method.lastIndexOf('.') + 1);
        if (!READ_ONLY.contains(verb)) {
            publishChange(method, session);
            cloud.markDirty();
        }
    }

    private void publishChange(String method, Optional<SessionStore.Session> session) {
        events.publish("change", Json.stringify(Json.object("method", method, "userId",
                session.map(SessionStore.Session::userId).orElse(null), "at", Instant.now().toString())));
    }

    // EventSource del navegador no permite cabeceras: el token viaja en ?token=.
    private void subscribe(HttpExchange exchange) throws IOException, InterruptedException {
        String token = queryParameter(exchange, "token");
        if (sessions.resolve(token).isEmpty()) {
            throw new HttpError(401, "unauthorized", "Inicia sesión con tu PIN");
        }
        exchange.getResponseHeaders().set("Content-Type", "text/event-stream; charset=utf-8");
        exchange.getResponseHeaders().set("Cache-Control", "no-cache");
        exchange.sendResponseHeaders(200, 0);
        events.subscribe(exchange.getResponseBody()).awaitClose();
    }

    /** Por la red solo se aceptan nombres de archivo .db dentro de la carpeta de respaldos. */
    private String backupPath(Object requested) {
        String name = requested instanceof String text ? text.trim() : "";
        if (name.isEmpty()) {
            name = "voxon90-" + LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss")) + ".db";
        }
        if (name.contains("/") || name.contains("\\") || name.contains("..") || !name.endsWith(".db")) {
            throw new HttpError(400, "validation_failed", "El respaldo debe ser un nombre de archivo .db, sin carpetas");
        }
        try {
            Files.createDirectories(backupDir);
        } catch (IOException e) {
            throw new HttpError(500, "backup_failed", "No se pudo crear la carpeta de respaldos");
        }
        return backupDir.resolve(name).toAbsolutePath().toString();
    }

    static int statusFor(String code) {
        if (code == null) {
            return 500;
        }
        return switch (code) {
            case "invalid_request", "validation_failed" -> 400;
            case "unauthorized" -> 401;
            case "forbidden" -> 403;
            case "not_found", "unknown_method" -> 404;
            case "too_many_attempts" -> 429;
            case "internal_error", "database_error", "backup_failed", "cloud_link_unwritable" -> 500;
            case "database_busy", "cloud_offline" -> 503;
            // Reglas del negocio: caja cerrada, límite de fiao, código de vínculo vencido...
            default -> 409;
        };
    }

    private static void requireMethod(HttpExchange exchange, String expected) {
        if (!expected.equals(exchange.getRequestMethod())) {
            exchange.getResponseHeaders().set("Allow", expected);
            throw new HttpError(405, "invalid_request", "Método HTTP no permitido; usa " + expected);
        }
    }

    private static Optional<String> bearerToken(HttpExchange exchange) {
        String header = exchange.getRequestHeaders().getFirst("Authorization");
        if (header == null || !header.startsWith("Bearer ")) {
            return Optional.empty();
        }
        String token = header.substring("Bearer ".length()).trim();
        return token.isEmpty() ? Optional.empty() : Optional.of(token);
    }

    private static String queryParameter(HttpExchange exchange, String name) {
        String query = exchange.getRequestURI().getRawQuery();
        if (query == null) {
            return null;
        }
        for (String pair : query.split("&")) {
            int separator = pair.indexOf('=');
            String key = separator < 0 ? pair : pair.substring(0, separator);
            if (name.equals(URLDecoder.decode(key, StandardCharsets.UTF_8))) {
                return separator < 0 ? "" : URLDecoder.decode(pair.substring(separator + 1), StandardCharsets.UTF_8);
            }
        }
        return null;
    }

    private static Map<String, Object> readJsonBody(HttpExchange exchange) throws IOException {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        try (InputStream in = exchange.getRequestBody()) {
            byte[] chunk = new byte[8192];
            int read;
            while ((read = in.read(chunk)) != -1) {
                if (buffer.size() + read > MAX_BODY_BYTES) {
                    throw new HttpError(413, "invalid_request", "La solicitud es demasiado grande");
                }
                buffer.write(chunk, 0, read);
            }
        }
        String text = buffer.toString(StandardCharsets.UTF_8);
        return text.isBlank() ? Json.object() : Json.parseObject(text);
    }

    private static void sendCoreError(HttpExchange exchange, Map<String, Object> response) throws IOException {
        String code = Json.stringOrNull(Json.objectOrEmpty(response, "error"), "code");
        sendText(exchange, statusFor(code), Json.stringify(response));
    }

    private static void sendError(HttpExchange exchange, int status, String code, String message) throws IOException {
        sendJson(exchange, status, Json.object("ok", false, "error", Json.object("code", code, "message", message)));
    }

    private static void sendJson(HttpExchange exchange, int status, Object body) throws IOException {
        sendText(exchange, status, Json.stringify(body));
    }

    private static void sendText(HttpExchange exchange, int status, String json) throws IOException {
        byte[] bytes = json.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        exchange.sendResponseHeaders(status, bytes.length);
        exchange.getResponseBody().write(bytes);
    }
}
