package com.voxon.server;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Locale;
import java.util.Map;

/** Sirve el cliente web desde una carpeta, sin permitir salir de ella. */
final class StaticFiles implements HttpHandler {
    private static final Map<String, String> TYPES = Map.ofEntries(
            Map.entry(".html", "text/html; charset=utf-8"),
            Map.entry(".js", "text/javascript; charset=utf-8"),
            Map.entry(".mjs", "text/javascript; charset=utf-8"),
            Map.entry(".css", "text/css; charset=utf-8"),
            Map.entry(".json", "application/json; charset=utf-8"),
            Map.entry(".webmanifest", "application/manifest+json"),
            Map.entry(".svg", "image/svg+xml"),
            Map.entry(".png", "image/png"),
            Map.entry(".ico", "image/x-icon"),
            Map.entry(".woff2", "font/woff2"));

    private final Path root;

    StaticFiles(Path root) throws IOException {
        this.root = root.toRealPath();
    }

    @Override
    public void handle(HttpExchange exchange) throws IOException {
        try {
            String method = exchange.getRequestMethod();
            if (!"GET".equals(method) && !"HEAD".equals(method)) {
                sendPlain(exchange, 405, "Método no permitido");
                return;
            }
            String requestPath = exchange.getRequestURI().getPath();
            if (requestPath.endsWith("/")) {
                requestPath += "index.html";
            }
            Path file = root.resolve(requestPath.substring(1)).normalize();
            if (!file.startsWith(root) || !Files.isRegularFile(file) || !file.toRealPath().startsWith(root)) {
                sendPlain(exchange, 404, "No encontrado");
                return;
            }

            byte[] content = Files.readAllBytes(file);
            String name = file.getFileName().toString().toLowerCase(Locale.ROOT);
            int dot = name.lastIndexOf('.');
            String type = TYPES.getOrDefault(dot < 0 ? "" : name.substring(dot), "application/octet-stream");
            exchange.getResponseHeaders().set("Content-Type", type);
            exchange.getResponseHeaders().set("Cache-Control", "no-cache");
            exchange.getResponseHeaders().set("X-Content-Type-Options", "nosniff");
            // El cliente web no carga nada de internet.
            exchange.getResponseHeaders().set("Content-Security-Policy",
                    "default-src 'self'; connect-src 'self'; img-src 'self' data:; style-src 'self'; script-src 'self'");
            if ("HEAD".equals(method)) {
                exchange.sendResponseHeaders(200, -1);
            } else {
                exchange.sendResponseHeaders(200, content.length);
                exchange.getResponseBody().write(content);
            }
        } finally {
            exchange.close();
        }
    }

    private static void sendPlain(HttpExchange exchange, int status, String text) throws IOException {
        byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "text/plain; charset=utf-8");
        exchange.sendResponseHeaders(status, bytes.length);
        exchange.getResponseBody().write(bytes);
    }
}
