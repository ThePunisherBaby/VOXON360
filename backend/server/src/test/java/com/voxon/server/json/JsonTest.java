package com.voxon.server.json;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class JsonTest {
    @Test
    void leeYEscribeSinCambiarElTexto() {
        String text = "{\"a\":1,\"b\":[true,false,null],\"c\":\"Peña \\\"ñ\\\"\",\"d\":-2.5,\"e\":{}}";
        assertEquals(text, Json.stringify(Json.parse(text)));
    }

    @Test
    void conservaEnterosGrandesComoLong() {
        Map<String, Object> value = Json.parseObject("{\"cents\": 9007199254740993}");
        assertEquals(9007199254740993L, value.get("cents"));
    }

    @Test
    void entiendeEscapesUnicodeYEmojis() {
        assertEquals("é😀", Json.parse("\"\\u00e9\\ud83d\\ude00\""));
        assertEquals(List.of("a/b"), Json.parse("[\"a\\/b\"]"));
    }

    @Test
    void escapaCaracteresDeControl() {
        assertEquals("\"a\\nb\\u0001\"", Json.stringify("a\nb"));
    }

    @Test
    void rechazaJsonInvalido() {
        assertThrows(JsonException.class, () -> Json.parse("{\"a\":}"));
        assertThrows(JsonException.class, () -> Json.parse("[1,2"));
        assertThrows(JsonException.class, () -> Json.parse("{\"a\":1} extra"));
        assertThrows(JsonException.class, () -> Json.parse("\"sin cerrar"));
        assertThrows(JsonException.class, () -> Json.parseObject("[1]"));
        assertThrows(JsonException.class, () -> Json.parse("[".repeat(100) + "]".repeat(100)));
    }
}
