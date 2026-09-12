package com.voxon.server.cloud;

import com.voxon.core.CoreGateway;
import com.voxon.server.json.Json;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.HexFormat;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.logging.Level;
import java.util.logging.Logger;
import java.util.regex.Pattern;

/**
 * Sube a Firestore el resumen del negocio para la app del dueño.
 *
 * <p>Vender nunca depende de la nube: el resumen sale del motor ({@code cloud.snapshot}) y se sube cuando
 * hay internet. Solo se escriben los documentos que cambiaron, para gastar pocas escrituras.
 *
 * <pre>
 * businesses/{negocio}/snapshots/status        caja abierta, órdenes, fiao y ventas de hoy
 * businesses/{negocio}/days/{AAAA-MM-DD}       resumen de hoy y de ayer
 * businesses/{negocio}/snapshots/cash          últimas cajas con su cuadre
 * businesses/{negocio}/snapshots/inventory     productos bajo el mínimo
 * businesses/{negocio}/snapshots/receivables   clientes que deben
 * businesses/{negocio}/devices/{uid}           esta caja principal (se crea al vincular)
 * </pre>
 */
public final class CloudSync implements CloudService, AutoCloseable {
    private static final Logger LOG = Logger.getLogger(CloudSync.class.getName());

    /** Código que genera la app del dueño: 8 caracteres sin 0, O, 1 ni I para dictarlo sin errores. */
    static final Pattern LINK_CODE = Pattern.compile("[A-HJ-NP-Z2-9]{8}");

    private static final Pattern DOCUMENT_ID = Pattern.compile("[A-Za-z0-9_-]{1,128}");
    private static final int SNAPSHOT_DAYS = 2;
    private static final Duration HEARTBEAT = Duration.ofMinutes(15);
    private static final long MAX_BACKOFF_SECONDS = Duration.ofMinutes(15).toSeconds();
    private static final int MAX_WRITES_PER_COMMIT = 400;
    private static final String STATUS_DOCUMENT = "/snapshots/status";

    private record Pending(String path, Map<String, Object> fields, String hash) {
    }

    private final CoreGateway core;
    private final FirebaseClient firebase;
    private final CloudLinkStore store;
    private final Clock clock;
    private final Duration interval;
    private final ScheduledExecutorService scheduler;
    private final Object syncLock = new Object();

    // Protegidos por this.
    private CloudLinkStore.CloudLink link;
    private FirebaseClient.AuthTokens tokens;
    private final Map<String, String> pushedHashes = new HashMap<>();
    private Instant lastStatusWrite = Instant.EPOCH;
    private Instant lastSyncAt;
    private Instant nextAttemptAt = Instant.EPOCH;
    private boolean dirty = true;
    private int failures;
    private String state;
    private String lastError;

    public CloudSync(CoreGateway core, FirebaseClient firebase, CloudLinkStore store, Clock clock, Duration interval) {
        this.core = core;
        this.firebase = firebase;
        this.store = store;
        this.clock = clock;
        this.interval = interval;
        this.link = store.load().orElse(null);
        this.state = link == null ? "unlinked" : "pending";
        this.scheduler = Executors.newSingleThreadScheduledExecutor(runnable -> {
            Thread thread = new Thread(runnable, "voxon-cloud-sync");
            thread.setDaemon(true);
            return thread;
        });
    }

    /** Revisa cada {@code interval} si hay algo que subir. */
    public void start() {
        long seconds = Math.max(5, interval.toSeconds());
        scheduler.scheduleWithFixedDelay(this::tick, Math.min(seconds, 10), seconds, TimeUnit.SECONDS);
    }

    @Override
    public void close() {
        scheduler.shutdownNow();
    }

    @Override
    public synchronized Map<String, Object> status() {
        return Json.object(
                "configured", true,
                "linked", link != null,
                "businessId", link == null ? null : link.businessId(),
                "state", state,
                "lastError", lastError,
                "lastSyncAt", lastSyncAt == null ? null : lastSyncAt.toString(),
                "pending", link != null && dirty);
    }

    @Override
    public synchronized void markDirty() {
        dirty = true;
    }

    @Override
    public Map<String, Object> link(String rawCode, String ownerUserId) {
        String code = rawCode == null ? "" : rawCode.replaceAll("[\\s-]", "").toUpperCase(Locale.ROOT);
        if (!LINK_CODE.matcher(code).matches()) {
            throw new CloudException("validation_failed",
                    "El código tiene 8 letras y números, tal como aparece en la app del dueño");
        }
        synchronized (syncLock) {
            FirebaseClient.AuthTokens session = firebase.signUpAnonymously();
            String businessId = businessForCode(session, code);
            try {
                firebase.commit(session.idToken(), List.of(new FirebaseClient.DocumentWrite(
                        "businesses/" + businessId + "/devices/" + session.uid(),
                        Json.object("linkCode", code, "name", "Caja principal",
                                "linkedAt", new FirestoreValues.Timestamp(clock.instant())))));
            } catch (CloudException e) {
                throw invalidCodeIfDenied(e);
            }

            CloudLinkStore.CloudLink created = new CloudLinkStore.CloudLink(businessId, session.uid(),
                    session.refreshToken(), ownerUserId, clock.instant().toString());
            store.save(created);
            synchronized (this) {
                link = created;
                tokens = session;
                pushedHashes.clear();
                lastStatusWrite = Instant.EPOCH;
                lastSyncAt = null;
                nextAttemptAt = Instant.EPOCH;
                dirty = true;
                failures = 0;
                state = "pending";
                lastError = null;
            }
        }
        LOG.info("Negocio vinculado con la app del dueño en Firebase");
        return syncNow();
    }

    @Override
    public Map<String, Object> unlink() {
        synchronized (syncLock) {
            CloudLinkStore.CloudLink current;
            synchronized (this) {
                current = link;
            }
            if (current != null) {
                try {
                    firebase.deleteDocument(idToken(current),
                            "businesses/" + current.businessId() + "/devices/" + current.deviceUid());
                } catch (CloudException e) {
                    LOG.info("No se pudo quitar el equipo en Firebase; se desvincula solo aquí: " + e.getMessage());
                }
            }
            store.delete();
            synchronized (this) {
                link = null;
                tokens = null;
                pushedHashes.clear();
                lastSyncAt = null;
                dirty = false;
                failures = 0;
                state = "unlinked";
                lastError = null;
            }
        }
        return status();
    }

    /** Sincroniza ya, sin esperar al siguiente turno. Devuelve el estado resultante. */
    public Map<String, Object> syncNow() {
        synchronized (syncLock) {
            CloudLinkStore.CloudLink current;
            synchronized (this) {
                current = link;
                dirty = false;
            }
            if (current == null) {
                return status();
            }
            try {
                Map<String, Object> snapshot = snapshot(current.ownerUserId());
                Instant now = clock.instant();
                List<Pending> pending = changedDocuments(current, snapshot, now);
                if (!pending.isEmpty()) {
                    String idToken = idToken(current);
                    for (int start = 0; start < pending.size(); start += MAX_WRITES_PER_COMMIT) {
                        List<FirebaseClient.DocumentWrite> batch = new ArrayList<>();
                        for (Pending item : pending.subList(start, Math.min(pending.size(), start + MAX_WRITES_PER_COMMIT))) {
                            batch.add(new FirebaseClient.DocumentWrite(item.path(), item.fields()));
                        }
                        firebase.commit(idToken, batch);
                    }
                }
                synchronized (this) {
                    for (Pending item : pending) {
                        pushedHashes.put(item.path(), item.hash());
                        if (item.path().endsWith(STATUS_DOCUMENT)) {
                            lastStatusWrite = now;
                        }
                    }
                    lastSyncAt = now;
                    failures = 0;
                    nextAttemptAt = Instant.EPOCH;
                    state = "ok";
                    lastError = null;
                }
            } catch (CloudException e) {
                synchronized (this) {
                    dirty = true;
                    failures++;
                    state = e.isOffline() ? "offline" : "error";
                    lastError = e.getMessage();
                    long backoff = Math.min(MAX_BACKOFF_SECONDS, 30L << Math.min(failures - 1, 10));
                    nextAttemptAt = clock.instant().plusSeconds(backoff);
                }
                LOG.log(e.isOffline() ? Level.FINE : Level.WARNING, "No se pudo sincronizar con la nube: " + e.getMessage());
            }
            return status();
        }
    }

    /** Turno periódico: sincroniza si hubo cambios o toca avisar que la caja sigue en línea. */
    void tick() {
        try {
            boolean due;
            synchronized (this) {
                Instant now = clock.instant();
                due = link != null && !now.isBefore(nextAttemptAt)
                        && (dirty || now.isAfter(lastStatusWrite.plus(HEARTBEAT)));
            }
            if (due) {
                syncNow();
            }
        } catch (RuntimeException e) {
            LOG.log(Level.WARNING, "Error inesperado sincronizando con la nube", e);
        }
    }

    private String businessForCode(FirebaseClient.AuthTokens session, String code) {
        Map<String, Object> linkCode;
        try {
            linkCode = firebase.getDocument(session.idToken(), "linkCodes/" + code);
        } catch (CloudException e) {
            throw invalidCodeIfDenied(e);
        }
        if (linkCode == null) {
            throw invalidCode();
        }
        String businessId = Json.stringOrNull(linkCode, "businessId");
        if (businessId == null || !DOCUMENT_ID.matcher(businessId).matches()) {
            throw invalidCode();
        }
        if (linkCode.get("expiresAt") instanceof String expiresAt) {
            try {
                if (Instant.parse(expiresAt).isBefore(clock.instant())) {
                    throw invalidCode();
                }
            } catch (DateTimeParseException e) {
                // Las reglas de Firestore también revisan el vencimiento.
                LOG.log(Level.FINE, "Vencimiento del código ilegible: " + expiresAt, e);
            }
        }
        return businessId;
    }

    private static CloudException invalidCode() {
        return new CloudException("invalid_link_code", "Ese código no existe o ya venció; genera otro en la app del dueño");
    }

    private static CloudException invalidCodeIfDenied(CloudException e) {
        return "cloud_permission_denied".equals(e.code()) ? invalidCode() : e;
    }

    private Map<String, Object> snapshot(String ownerUserId) {
        String request = Json.stringify(Json.object("method", "cloud.snapshot", "actor", ownerUserId,
                "params", Json.object("days", (long) SNAPSHOT_DAYS)));
        Map<String, Object> response = Json.parseObject(core.execute(request));
        if (Boolean.TRUE.equals(response.get("ok"))) {
            return Json.objectOrEmpty(response, "result");
        }
        Map<String, Object> error = Json.objectOrEmpty(response, "error");
        String code = Json.stringOrNull(error, "code");
        if ("unauthorized".equals(code) || "forbidden".equals(code)) {
            throw new CloudException("cloud_owner_inactive",
                    "Quien vinculó la nube ya no es un dueño activo; vuelve a vincular desde Ajustes");
        }
        throw new CloudException("cloud_snapshot_failed",
                "El motor no pudo preparar el resumen: " + Json.stringOrNull(error, "message"));
    }

    private String idToken(CloudLinkStore.CloudLink current) {
        FirebaseClient.AuthTokens cached;
        synchronized (this) {
            cached = tokens;
        }
        if (cached != null && cached.uid().equals(current.deviceUid()) && !cached.expiresSoon(clock.instant())) {
            return cached.idToken();
        }
        FirebaseClient.AuthTokens fresh;
        try {
            fresh = firebase.refresh(current.refreshToken());
        } catch (CloudException e) {
            if (e.isOffline()) {
                throw e;
            }
            throw new CloudException("cloud_link_revoked",
                    "Firebase ya no acepta la sesión de esta caja; vuelve a vincular desde Ajustes", e);
        }
        CloudLinkStore.CloudLink updated = current;
        if (!fresh.refreshToken().equals(current.refreshToken())) {
            updated = new CloudLinkStore.CloudLink(current.businessId(), current.deviceUid(), fresh.refreshToken(),
                    current.ownerUserId(), current.linkedAt());
            store.save(updated);
        }
        synchronized (this) {
            if (link == current) {
                link = updated;
            }
            tokens = fresh;
        }
        return fresh.idToken();
    }

    private List<Pending> changedDocuments(CloudLinkStore.CloudLink current, Map<String, Object> snapshot, Instant now) {
        String base = "businesses/" + current.businessId();
        FirestoreValues.Timestamp syncedAt = new FirestoreValues.Timestamp(now);
        List<Object> days = listOrEmpty(snapshot.get("days"));
        Map<String, Object> business = Json.objectOrEmpty(snapshot, "business");
        Map<String, Object> today = days.isEmpty() ? Json.object() : Json.asObject(days.get(0));

        List<Pending> pending = new ArrayList<>();
        boolean heartbeat;
        synchronized (this) {
            heartbeat = now.isAfter(lastStatusWrite.plus(HEARTBEAT));
        }
        addIfChanged(pending, base + STATUS_DOCUMENT, Json.object(
                "businessName", business.get("name"),
                "businessType", business.get("businessType"),
                "day", today.get("day"),
                "todaySales", today.get("sales"),
                "openCashSession", snapshot.get("openCashSession"),
                "openOrders", snapshot.get("openOrders"),
                "lowStockCount", snapshot.get("lowStockCount"),
                "receivablesCents", snapshot.get("receivablesCents"),
                "syncedAt", syncedAt), heartbeat);

        Set<String> dayPaths = new HashSet<>();
        for (Object item : days) {
            Map<String, Object> summary = new LinkedHashMap<>(Json.asObject(item));
            String day = Json.stringOrNull(summary, "day");
            if (day == null || !DOCUMENT_ID.matcher(day).matches()) {
                continue;
            }
            summary.put("syncedAt", syncedAt);
            String path = base + "/days/" + day;
            dayPaths.add(path);
            addIfChanged(pending, path, summary, false);
        }
        addIfChanged(pending, base + "/snapshots/cash",
                Json.object("sessions", listOrEmpty(snapshot.get("cashSessions")), "syncedAt", syncedAt), false);
        addIfChanged(pending, base + "/snapshots/inventory",
                Json.object("lowStock", listOrEmpty(snapshot.get("lowStock")), "syncedAt", syncedAt), false);
        addIfChanged(pending, base + "/snapshots/receivables", Json.object(
                "totalCents", snapshot.get("receivablesCents"),
                "customers", listOrEmpty(snapshot.get("receivables")),
                "syncedAt", syncedAt), false);

        // Los días que ya no están en el resumen no se vuelven a comparar.
        synchronized (this) {
            pushedHashes.keySet().removeIf(path -> path.contains("/days/") && !dayPaths.contains(path));
        }
        return pending;
    }

    private void addIfChanged(List<Pending> pending, String path, Map<String, Object> fields, boolean force) {
        Map<String, Object> compared = new LinkedHashMap<>(fields);
        compared.remove("syncedAt");
        String hash = sha256(Json.stringify(compared));
        String previous;
        synchronized (this) {
            previous = pushedHashes.get(path);
        }
        if (force || !hash.equals(previous)) {
            pending.add(new Pending(path, fields, hash));
        }
    }

    @SuppressWarnings("unchecked")
    private static List<Object> listOrEmpty(Object value) {
        return value instanceof List ? (List<Object>) value : List.of();
    }

    private static String sha256(String text) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8)));
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 no disponible", e);
        }
    }
}
