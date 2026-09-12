package com.voxon.server;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import org.junit.jupiter.api.Test;

class SessionStoreTest {
    private static final class MutableClock extends Clock {
        private Instant now = Instant.parse("2026-09-11T12:00:00Z");

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

    @Test
    void creaTokensDistintosYLosResuelve() {
        SessionStore store = new SessionStore(Duration.ofHours(1), new MutableClock());
        SessionStore.Session first = store.create("u-1", "Ana", "owner");
        SessionStore.Session second = store.create("u-2", "Luis", "cashier");

        assertNotEquals(first.token(), second.token());
        assertEquals("Ana", store.resolve(first.token()).orElseThrow().name());
        assertTrue(store.resolve("inventado").isEmpty());
        assertTrue(store.resolve(null).isEmpty());
    }

    @Test
    void venceTrasInactividadYElUsoLaExtiende() {
        MutableClock clock = new MutableClock();
        SessionStore store = new SessionStore(Duration.ofHours(1), clock);
        String token = store.create("u-1", "Ana", "owner").token();

        clock.advance(Duration.ofMinutes(50));
        assertTrue(store.resolve(token).isPresent());
        clock.advance(Duration.ofMinutes(50));
        assertTrue(store.resolve(token).isPresent());
        clock.advance(Duration.ofMinutes(61));
        assertTrue(store.resolve(token).isEmpty());
        assertEquals(0, store.size());
    }

    @Test
    void cierraLasSesionesDeUnEmpleado() {
        SessionStore store = new SessionStore(Duration.ofHours(1), new MutableClock());
        String ana = store.create("u-1", "Ana", "owner").token();
        store.create("u-2", "Luis", "cashier");
        store.create("u-2", "Luis", "cashier");

        store.revokeUser("u-2");

        assertEquals(1, store.size());
        assertTrue(store.resolve(ana).isPresent());
    }
}
