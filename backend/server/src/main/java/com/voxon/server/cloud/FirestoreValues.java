package com.voxon.server.cloud;

import com.voxon.server.json.Json;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Conversión entre los valores de {@link Json} y los valores con tipo de la API REST de Firestore
 * ({@code {"integerValue": "5900"}}, {@code {"mapValue": {"fields": …}}}…).
 */
public final class FirestoreValues {
    private FirestoreValues() {
    }

    /** Instante que se guarda como {@code timestampValue} para poder ordenar y filtrar por fecha. */
    public record Timestamp(Instant instant) {
    }

    public static Map<String, Object> encodeFields(Map<String, Object> fields) {
        Map<String, Object> encoded = new LinkedHashMap<>();
        fields.forEach((key, value) -> encoded.put(key, encode(value)));
        return encoded;
    }

    public static Map<String, Object> encode(Object value) {
        Map<String, Object> typed = new LinkedHashMap<>();
        if (value == null) {
            typed.put("nullValue", null);
        } else if (value instanceof Boolean) {
            typed.put("booleanValue", value);
        } else if (value instanceof Long || value instanceof Integer || value instanceof Short || value instanceof Byte) {
            // int64 viaja como texto en JSON.
            typed.put("integerValue", String.valueOf(value));
        } else if (value instanceof Double || value instanceof Float) {
            typed.put("doubleValue", ((Number) value).doubleValue());
        } else if (value instanceof String text) {
            typed.put("stringValue", text);
        } else if (value instanceof Timestamp timestamp) {
            typed.put("timestampValue", timestamp.instant().toString());
        } else if (value instanceof Map<?, ?> map) {
            Map<String, Object> fields = new LinkedHashMap<>();
            map.forEach((key, item) -> fields.put(String.valueOf(key), encode(item)));
            typed.put("mapValue", Json.object("fields", fields));
        } else if (value instanceof List<?> list) {
            List<Object> values = new ArrayList<>();
            for (Object item : list) {
                if (item instanceof List) {
                    throw new IllegalArgumentException("Firestore no admite arreglos dentro de arreglos");
                }
                values.add(encode(item));
            }
            typed.put("arrayValue", Json.object("values", values));
        } else {
            throw new IllegalArgumentException("Tipo no soportado en Firestore: " + value.getClass().getName());
        }
        return typed;
    }

    public static Map<String, Object> decodeFields(Map<String, Object> fields) {
        Map<String, Object> decoded = new LinkedHashMap<>();
        fields.forEach((key, value) -> decoded.put(key, value instanceof Map ? decode(Json.asObject(value)) : null));
        return decoded;
    }

    /** Valor simple: los instantes vuelven como texto ISO-8601. */
    public static Object decode(Map<String, Object> typed) {
        if (typed.get("booleanValue") instanceof Boolean flag) {
            return flag;
        }
        if (typed.get("integerValue") instanceof String digits) {
            return Long.parseLong(digits);
        }
        if (typed.get("integerValue") instanceof Number number) {
            return number.longValue();
        }
        if (typed.get("doubleValue") instanceof Number number) {
            return number.doubleValue();
        }
        if (typed.get("stringValue") instanceof String text) {
            return text;
        }
        if (typed.get("timestampValue") instanceof String instant) {
            return instant;
        }
        if (typed.get("mapValue") instanceof Map<?, ?> map) {
            Object fields = map.get("fields");
            return fields instanceof Map ? decodeFields(Json.asObject(fields)) : new LinkedHashMap<String, Object>();
        }
        if (typed.get("arrayValue") instanceof Map<?, ?> array) {
            List<Object> values = new ArrayList<>();
            if (array.get("values") instanceof List<?> items) {
                for (Object item : items) {
                    values.add(item instanceof Map ? decode(Json.asObject(item)) : null);
                }
            }
            return values;
        }
        return null;
    }
}
