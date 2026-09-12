package com.voxon.server.json;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * JSON mínimo sin dependencias.
 *
 * <p>Tipos: objeto → {@code Map<String, Object>} (conserva el orden), arreglo →
 * {@code List<Object>}, texto → {@code String}, entero → {@code Long}, decimal →
 * {@code Double}, booleano → {@code Boolean} y null → {@code null}.
 */
public final class Json {
    private static final int MAX_DEPTH = 64;

    private Json() {
    }

    public static Object parse(String text) {
        Parser parser = new Parser(text);
        Object value = parser.readValue(0);
        parser.skipWhitespace();
        if (!parser.atEnd()) {
            throw parser.error("Contenido extra después del JSON");
        }
        return value;
    }

    /** Analiza un texto que debe ser un objeto JSON. */
    public static Map<String, Object> parseObject(String text) {
        Object value = parse(text);
        if (!(value instanceof Map)) {
            throw new JsonException("Se esperaba un objeto JSON");
        }
        return asObject(value);
    }

    public static String stringify(Object value) {
        StringBuilder out = new StringBuilder();
        write(out, value);
        return out.toString();
    }

    /** Crea un objeto a partir de pares clave, valor. */
    public static Map<String, Object> object(Object... keysAndValues) {
        if (keysAndValues.length % 2 != 0) {
            throw new IllegalArgumentException("Se esperaban pares clave, valor");
        }
        Map<String, Object> map = new LinkedHashMap<>();
        for (int i = 0; i < keysAndValues.length; i += 2) {
            map.put((String) keysAndValues[i], keysAndValues[i + 1]);
        }
        return map;
    }

    @SuppressWarnings("unchecked")
    public static Map<String, Object> asObject(Object value) {
        return (Map<String, Object>) value;
    }

    /** Objeto anidado en {@code key}, o un objeto vacío si falta o no es objeto. */
    public static Map<String, Object> objectOrEmpty(Map<String, Object> map, String key) {
        Object value = map.get(key);
        return value instanceof Map ? asObject(value) : new LinkedHashMap<>();
    }

    /** Texto en {@code key}, o null si falta o no es texto. */
    public static String stringOrNull(Map<String, Object> map, String key) {
        Object value = map.get(key);
        return value instanceof String ? (String) value : null;
    }

    private static void write(StringBuilder out, Object value) {
        if (value == null) {
            out.append("null");
        } else if (value instanceof String) {
            writeString(out, (String) value);
        } else if (value instanceof Boolean || value instanceof Long || value instanceof Integer
                || value instanceof Short || value instanceof Byte) {
            out.append(value);
        } else if (value instanceof Double || value instanceof Float) {
            double number = ((Number) value).doubleValue();
            if (Double.isNaN(number) || Double.isInfinite(number)) {
                throw new JsonException("JSON no admite NaN ni infinito");
            }
            out.append(value);
        } else if (value instanceof Map) {
            out.append('{');
            boolean first = true;
            for (Map.Entry<?, ?> entry : ((Map<?, ?>) value).entrySet()) {
                if (!first) {
                    out.append(',');
                }
                first = false;
                writeString(out, String.valueOf(entry.getKey()));
                out.append(':');
                write(out, entry.getValue());
            }
            out.append('}');
        } else if (value instanceof List) {
            out.append('[');
            boolean first = true;
            for (Object item : (List<?>) value) {
                if (!first) {
                    out.append(',');
                }
                first = false;
                write(out, item);
            }
            out.append(']');
        } else {
            throw new JsonException("Tipo no soportado en JSON: " + value.getClass().getName());
        }
    }

    private static void writeString(StringBuilder out, String text) {
        out.append('"');
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            switch (c) {
                case '"' -> out.append("\\\"");
                case '\\' -> out.append("\\\\");
                case '\n' -> out.append("\\n");
                case '\r' -> out.append("\\r");
                case '\t' -> out.append("\\t");
                case '\b' -> out.append("\\b");
                case '\f' -> out.append("\\f");
                default -> {
                    if (c < 0x20) {
                        out.append(String.format("\\u%04x", (int) c));
                    } else {
                        out.append(c);
                    }
                }
            }
        }
        out.append('"');
    }

    private static final class Parser {
        private final String text;
        private int position;

        Parser(String text) {
            if (text == null) {
                throw new JsonException("El texto JSON está vacío");
            }
            this.text = text;
        }

        boolean atEnd() {
            return position >= text.length();
        }

        JsonException error(String message) {
            return new JsonException(message + " (posición " + position + ")");
        }

        void skipWhitespace() {
            while (!atEnd()) {
                char c = text.charAt(position);
                if (c != ' ' && c != '\t' && c != '\n' && c != '\r') {
                    return;
                }
                position++;
            }
        }

        Object readValue(int depth) {
            if (depth > MAX_DEPTH) {
                throw error("JSON demasiado anidado");
            }
            skipWhitespace();
            if (atEnd()) {
                throw error("JSON incompleto");
            }
            char c = text.charAt(position);
            return switch (c) {
                case '{' -> readObject(depth);
                case '[' -> readArray(depth);
                case '"' -> readString();
                case 't' -> readLiteral("true", Boolean.TRUE);
                case 'f' -> readLiteral("false", Boolean.FALSE);
                case 'n' -> readLiteral("null", null);
                default -> {
                    if (c == '-' || (c >= '0' && c <= '9')) {
                        yield readNumber();
                    }
                    throw error("Carácter inesperado '" + c + "'");
                }
            };
        }

        Object readLiteral(String literal, Object value) {
            if (!text.startsWith(literal, position)) {
                throw error("Se esperaba " + literal);
            }
            position += literal.length();
            return value;
        }

        Map<String, Object> readObject(int depth) {
            Map<String, Object> map = new LinkedHashMap<>();
            position++;
            skipWhitespace();
            if (!atEnd() && text.charAt(position) == '}') {
                position++;
                return map;
            }
            while (true) {
                skipWhitespace();
                if (atEnd() || text.charAt(position) != '"') {
                    throw error("Se esperaba el nombre de un campo");
                }
                String key = readString();
                skipWhitespace();
                expect(':');
                map.put(key, readValue(depth + 1));
                skipWhitespace();
                if (atEnd()) {
                    throw error("Objeto sin cerrar");
                }
                char c = text.charAt(position++);
                if (c == '}') {
                    return map;
                }
                if (c != ',') {
                    throw error("Se esperaba ',' o '}'");
                }
            }
        }

        List<Object> readArray(int depth) {
            List<Object> list = new ArrayList<>();
            position++;
            skipWhitespace();
            if (!atEnd() && text.charAt(position) == ']') {
                position++;
                return list;
            }
            while (true) {
                list.add(readValue(depth + 1));
                skipWhitespace();
                if (atEnd()) {
                    throw error("Arreglo sin cerrar");
                }
                char c = text.charAt(position++);
                if (c == ']') {
                    return list;
                }
                if (c != ',') {
                    throw error("Se esperaba ',' o ']'");
                }
            }
        }

        void expect(char expected) {
            if (atEnd() || text.charAt(position) != expected) {
                throw error("Se esperaba '" + expected + "'");
            }
            position++;
        }

        String readString() {
            expect('"');
            StringBuilder out = new StringBuilder();
            while (true) {
                if (atEnd()) {
                    throw error("Texto sin cerrar");
                }
                char c = text.charAt(position++);
                if (c == '"') {
                    return out.toString();
                }
                if (c < 0x20) {
                    throw error("Carácter de control sin escapar");
                }
                if (c != '\\') {
                    out.append(c);
                    continue;
                }
                if (atEnd()) {
                    throw error("Escape incompleto");
                }
                char escaped = text.charAt(position++);
                switch (escaped) {
                    case '"' -> out.append('"');
                    case '\\' -> out.append('\\');
                    case '/' -> out.append('/');
                    case 'b' -> out.append('\b');
                    case 'f' -> out.append('\f');
                    case 'n' -> out.append('\n');
                    case 'r' -> out.append('\r');
                    case 't' -> out.append('\t');
                    case 'u' -> {
                        if (position + 4 > text.length()) {
                            throw error("Escape \\u incompleto");
                        }
                        try {
                            out.append((char) Integer.parseInt(text.substring(position, position + 4), 16));
                        } catch (NumberFormatException e) {
                            throw error("Escape \\u inválido");
                        }
                        position += 4;
                    }
                    default -> throw error("Escape inválido \\" + escaped);
                }
            }
        }

        Object readNumber() {
            int start = position;
            if (text.charAt(position) == '-') {
                position++;
            }
            boolean decimal = false;
            while (!atEnd()) {
                char c = text.charAt(position);
                if (c >= '0' && c <= '9') {
                    position++;
                } else if (c == '.' || c == 'e' || c == 'E' || c == '+' || c == '-') {
                    decimal = true;
                    position++;
                } else {
                    break;
                }
            }
            String number = text.substring(start, position);
            try {
                if (!decimal) {
                    return Long.parseLong(number);
                }
                return Double.parseDouble(number);
            } catch (NumberFormatException e) {
                throw error("Número inválido '" + number + "'");
            }
        }
    }
}
