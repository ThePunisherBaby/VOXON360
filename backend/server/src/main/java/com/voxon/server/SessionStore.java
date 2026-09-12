package com.voxon.server;

import java.security.SecureRandom;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Sesiones abiertas con PIN. Cada uso extiende la sesión; tras {@code ttl} sin
 * actividad expira. Viven en memoria: reiniciar el servidor pide el PIN de nuevo.
 */
public final class SessionStore {
    public record Session(String token, String userId, String name, String role, Instant expiresAt) {
    }

    private final ConcurrentHashMap<String, Session> sessions = new ConcurrentHashMap<>();
    private final SecureRandom random = new SecureRandom();
    private final Duration ttl;
    private final Clock clock;

    public SessionStore(Duration ttl, Clock clock) {
        this.ttl = ttl;
        this.clock = clock;
    }

    public Session create(String userId, String name, String role) {
        byte[] bytes = new byte[32];
        random.nextBytes(bytes);
        String token = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
        Session session = new Session(token, userId, name, role, clock.instant().plus(ttl));
        sessions.put(token, session);
        return session;
    }

    /** Sesión vigente del token, extendiendo su vencimiento. */
    public Optional<Session> resolve(String token) {
        if (token == null || token.isEmpty()) {
            return Optional.empty();
        }
        Session updated = sessions.computeIfPresent(token, (key, session) -> {
            if (!clock.instant().isBefore(session.expiresAt())) {
                return null;
            }
            return new Session(key, session.userId(), session.name(), session.role(), clock.instant().plus(ttl));
        });
        return Optional.ofNullable(updated);
    }

    public void revoke(String token) {
        if (token != null) {
            sessions.remove(token);
        }
    }

    /** Cierra todas las sesiones de un empleado, p. ej. al desactivarlo. */
    public void revokeUser(String userId) {
        sessions.values().removeIf(session -> session.userId().equals(userId));
    }

    public int size() {
        return sessions.size();
    }
}
