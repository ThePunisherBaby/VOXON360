package com.voxon.server.cloud;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import com.voxon.server.json.Json;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class FirestoreValuesTest {
    @Test
    void codificaCadaTipoComoLoEsperaFirestore() {
        Map<String, Object> encoded = FirestoreValues.encodeFields(Json.object(
                "totalCents", 5900L,
                "name", "Refresco",
                "open", true,
                "closedAt", null,
                "ratio", 0.18,
                "syncedAt", new FirestoreValues.Timestamp(Instant.parse("2026-09-11T15:00:00Z")),
                "payments", List.of(Json.object("method", "cash"))));

        assertEquals("{\"totalCents\":{\"integerValue\":\"5900\"},"
                + "\"name\":{\"stringValue\":\"Refresco\"},"
                + "\"open\":{\"booleanValue\":true},"
                + "\"closedAt\":{\"nullValue\":null},"
                + "\"ratio\":{\"doubleValue\":0.18},"
                + "\"syncedAt\":{\"timestampValue\":\"2026-09-11T15:00:00Z\"},"
                + "\"payments\":{\"arrayValue\":{\"values\":[{\"mapValue\":{\"fields\":{\"method\":{\"stringValue\":\"cash\"}}}}]}}}",
                Json.stringify(encoded));
    }

    @Test
    void loQueSeSubeSeLeeIgual() {
        Map<String, Object> original = Json.object(
                "day", "2026-09-11",
                "sales", Json.object("count", 2L, "totalCents", 17700L),
                "hourly", List.of(Json.object("hour", 9L, "count", 2L)),
                "openCashSession", null,
                "ratio", 1.5,
                "voided", false,
                "empty", List.of());

        Map<String, Object> roundTrip = FirestoreValues.decodeFields(
                Json.parseObject(Json.stringify(FirestoreValues.encodeFields(original))));

        assertEquals(original, roundTrip);
    }

    @Test
    void rechazaArreglosDentroDeArreglos() {
        assertThrows(IllegalArgumentException.class, () -> FirestoreValues.encode(List.of(List.of(1L))));
    }
}
