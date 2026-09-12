#pragma once

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <string_view>

#include "core/engine.hpp"
#include "core/json.hpp"
#include "core/params.hpp"
#include "db/sqlite.hpp"

namespace voxon::services {

/// Hora actual en el formato de las tablas, para usar dentro de SQL.
inline constexpr const char* kNowSql = "strftime('%Y-%m-%dT%H:%M:%fZ', 'now')";

using Binder = std::function<void(db::Statement&)>;

std::string newId();

/// "price_cents" → "priceCents".
std::string snakeToCamel(std::string_view name);

/// Fila actual como objeto JSON: nombres en camelCase y columnas booleanas
/// (active, track_stock...) como true/false.
Json rowToJson(const db::Statement& statement);

/// Todas las filas como arreglo JSON.
Json queryAll(db::Database& db, std::string_view sql, const Binder& bind = {});

/// Primera fila, o nullopt si no hay.
std::optional<Json> queryOne(db::Database& db, std::string_view sql, const Binder& bind = {});

/// Primera fila, o not_found con `notFoundMessage`.
Json requireOne(db::Database& db, std::string_view sql, const Binder& bind, const std::string& notFoundMessage);

/// Primera columna de la primera fila como entero, o `fallback`.
std::int64_t queryInt(db::Database& db, std::string_view sql, const Binder& bind = {}, std::int64_t fallback = 0);

/// Ejecuta un comando sin resultados.
void execute(db::Database& db, std::string_view sql, const Binder& bind = {});

/// Registra una acción en la bitácora con el empleado de la solicitud.
void audit(const Context& context, std::string_view action, std::string_view entity, std::string_view entityId,
           const Json& details = Json::object());

/// Siguiente número de un contador de documentos ("sale", "order").
std::int64_t nextCounter(db::Database& db, std::string_view name);

/// RNC (9 dígitos) o cédula (11 dígitos) opcional; acepta guiones y espacios.
std::optional<std::string> optionalDocumentId(const Params& params, std::string_view key);

/// "%término%" escapando los comodines de LIKE (usar con ESCAPE '\').
std::string likePattern(const std::string& term);

/// Id de la caja abierta, si hay una.
std::optional<std::string> openCashSessionId(db::Database& db);

/// Id de la caja abierta o cash_session_closed.
std::string requireOpenCashSession(db::Database& db);

/// Fecha "AAAA-MM-DD" con mes y día en rango.
bool isIsoDate(std::string_view value);

/// Período "AAAA-MM".
bool isIsoMonth(std::string_view value);

/// Exige que exista una fila con ese id en la tabla (solo nombres internos).
void requireExists(db::Database& db, std::string_view table, const std::string& id, const std::string& message);

}  // namespace voxon::services
