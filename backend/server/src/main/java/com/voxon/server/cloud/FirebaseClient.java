package com.voxon.server.cloud;

import com.voxon.server.json.Json;
import com.voxon.server.json.JsonException;
import java.io.IOException;
import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * Cliente mínimo de Firebase Auth y Cloud Firestore por REST, solo con el JDK.
 *
 * <p>Las solicitudes a Firestore llevan el token de Firebase Auth del equipo, así que las reglas de
 * seguridad ({@code firebase/firestore.rules}) deciden qué puede escribir.
 */
public final class FirebaseClient {
    private static final Duration TIMEOUT = Duration.ofSeconds(20);

    /** Sesión de este equipo en Firebase Auth. */
    public record AuthTokens(String uid, String idToken, String refreshToken, Instant expiresAt) {
        /** El token vence en menos de un minuto. */
        public boolean expiresSoon(Instant now) {
            return now.isAfter(expiresAt.minusSeconds(60));
        }
    }

    /** Documento que se crea o se reemplaza completo. {@code path} va desde la raíz, p. ej. {@code businesses/b1/days/2026-09-11}. */
    public record DocumentWrite(String path, Map<String, Object> fields) {
    }

    private final FirebaseSettings settings;
    private final Clock clock;
    private final HttpClient http;

    public FirebaseClient(FirebaseSettings settings, Clock clock) {
        this.settings = settings;
        this.clock = clock;
        this.http = HttpClient.newBuilder().connectTimeout(TIMEOUT).build();
    }

    /** Crea un usuario anónimo: la identidad de esta caja principal en Firebase. */
    public AuthTokens signUpAnonymously() {
        HttpRequest.Builder request = HttpRequest.newBuilder(
                        URI.create(settings.identityToolkitUrl() + "/accounts:signUp?key=" + encode(settings.apiKey())))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(Json.stringify(Json.object("returnSecureToken", true))));
        Map<String, Object> body = send(request, null);
        return tokens(Json.stringOrNull(body, "localId"), Json.stringOrNull(body, "idToken"),
                Json.stringOrNull(body, "refreshToken"), Json.stringOrNull(body, "expiresIn"));
    }

    /** Cambia el token de renovación por un token de acceso nuevo. */
    public AuthTokens refresh(String refreshToken) {
        HttpRequest.Builder request = HttpRequest.newBuilder(
                        URI.create(settings.secureTokenUrl() + "/token?key=" + encode(settings.apiKey())))
                .header("Content-Type", "application/x-www-form-urlencoded")
                .POST(HttpRequest.BodyPublishers.ofString(
                        "grant_type=refresh_token&refresh_token=" + encode(refreshToken)));
        Map<String, Object> body = send(request, null);
        return tokens(Json.stringOrNull(body, "user_id"), Json.stringOrNull(body, "id_token"),
                Json.stringOrNull(body, "refresh_token"), Json.stringOrNull(body, "expires_in"));
    }

    /** Campos del documento, o null si no existe. */
    public Map<String, Object> getDocument(String idToken, String path) {
        try {
            Map<String, Object> document = send(HttpRequest.newBuilder(documentUri(path)).GET(), idToken);
            return FirestoreValues.decodeFields(Json.objectOrEmpty(document, "fields"));
        } catch (CloudException e) {
            if ("not_found".equals(e.code())) {
                return null;
            }
            throw e;
        }
    }

    /** Aplica todas las escrituras de forma atómica. */
    public void commit(String idToken, List<DocumentWrite> writes) {
        if (writes.isEmpty()) {
            return;
        }
        List<Object> encoded = new ArrayList<>();
        for (DocumentWrite write : writes) {
            encoded.add(Json.object("update", Json.object(
                    "name", settings.documentsRoot() + "/" + write.path(),
                    "fields", FirestoreValues.encodeFields(write.fields()))));
        }
        HttpRequest.Builder request = HttpRequest.newBuilder(
                        URI.create(settings.firestoreUrl() + "/" + settings.documentsRoot() + ":commit"))
                .header("Content-Type", "application/json")
                .POST(HttpRequest.BodyPublishers.ofString(Json.stringify(Json.object("writes", encoded))));
        send(request, idToken);
    }

    public void deleteDocument(String idToken, String path) {
        try {
            send(HttpRequest.newBuilder(documentUri(path)).DELETE(), idToken);
        } catch (CloudException e) {
            if (!"not_found".equals(e.code())) {
                throw e;
            }
        }
    }

    private URI documentUri(String path) {
        return URI.create(settings.firestoreUrl() + "/" + settings.documentsRoot() + "/" + path);
    }

    private Map<String, Object> send(HttpRequest.Builder builder, String idToken) {
        builder.timeout(TIMEOUT);
        if (idToken != null) {
            builder.header("Authorization", "Bearer " + idToken);
        }
        HttpResponse<String> response;
        try {
            response = http.send(builder.build(), HttpResponse.BodyHandlers.ofString(StandardCharsets.UTF_8));
        } catch (IOException e) {
            throw new CloudException(CloudException.OFFLINE, "Sin conexión con Firebase", e);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new CloudException(CloudException.OFFLINE, "Conexión con Firebase interrumpida", e);
        }

        Map<String, Object> body;
        try {
            body = response.body().isBlank() ? Json.object() : Json.parseObject(response.body());
        } catch (JsonException e) {
            body = Json.object();
        }
        int status = response.statusCode();
        if (status >= 200 && status < 300) {
            return body;
        }
        String detail = Json.stringOrNull(Json.objectOrEmpty(body, "error"), "message");
        String code = switch (status) {
            case 401, 403 -> "cloud_permission_denied";
            case 404 -> "not_found";
            case 408, 429 -> CloudException.OFFLINE;
            default -> status >= 500 ? CloudException.OFFLINE : "cloud_rejected";
        };
        throw new CloudException(code, "Firebase respondió " + status + (detail == null ? "" : ": " + detail));
    }

    private AuthTokens tokens(String uid, String idToken, String refreshToken, String expiresIn) {
        if (uid == null || idToken == null || refreshToken == null) {
            throw new CloudException("cloud_rejected", "Firebase Auth no devolvió una sesión válida");
        }
        long seconds;
        try {
            seconds = expiresIn == null ? 3600 : Long.parseLong(expiresIn);
        } catch (NumberFormatException e) {
            seconds = 3600;
        }
        return new AuthTokens(uid, idToken, refreshToken, clock.instant().plusSeconds(seconds));
    }

    private static String encode(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }
}
