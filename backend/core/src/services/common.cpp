#include "services/common.hpp"

#include <array>
#include <utility>

#include "core/error.hpp"
#include "crypto/crypto.hpp"
#include "text/text.hpp"

namespace voxon::services {

namespace {

constexpr std::array<std::string_view, 5> kBooleanColumns = {
    "active", "allows_fraction", "track_stock", "legal_tip_enabled", "expired"};

bool isBooleanColumn(std::string_view name) {
  for (const auto column : kBooleanColumns) {
    if (column == name) return true;
  }
  return false;
}

}  // namespace

std::string newId() { return crypto::uuidV4(); }

std::string snakeToCamel(std::string_view name) {
  std::string camel;
  camel.reserve(name.size());
  bool upperNext = false;
  for (const char c : name) {
    if (c == '_') {
      upperNext = true;
      continue;
    }
    camel.push_back(upperNext && c >= 'a' && c <= 'z' ? static_cast<char>(c - 'a' + 'A') : c);
    upperNext = false;
  }
  return camel;
}

Json rowToJson(const db::Statement& statement) {
  Json row = Json::object();
  for (int column = 0; column < statement.columnCount(); ++column) {
    const auto name = statement.columnName(column);
    const auto key = snakeToCamel(name);
    switch (statement.columnType(column)) {
      case db::Statement::ColumnType::Integer:
        if (isBooleanColumn(name)) {
          row[key] = statement.getInt(column) != 0;
        } else {
          row[key] = statement.getInt(column);
        }
        break;
      case db::Statement::ColumnType::Float:
        row[key] = statement.getDouble(column);
        break;
      case db::Statement::ColumnType::Text:
        row[key] = statement.getText(column);
        break;
      default:
        row[key] = nullptr;
        break;
    }
  }
  return row;
}

Json queryAll(db::Database& db, std::string_view sql, const Binder& bind) {
  auto statement = db.prepare(sql);
  if (bind) bind(statement);
  Json rows = Json::array();
  while (statement.step()) {
    rows.push_back(rowToJson(statement));
  }
  return rows;
}

std::optional<Json> queryOne(db::Database& db, std::string_view sql, const Binder& bind) {
  auto statement = db.prepare(sql);
  if (bind) bind(statement);
  if (!statement.step()) {
    return std::nullopt;
  }
  return rowToJson(statement);
}

Json requireOne(db::Database& db, std::string_view sql, const Binder& bind, const std::string& notFoundMessage) {
  auto row = queryOne(db, sql, bind);
  if (!row) {
    throw ApiError(errc::kNotFound, notFoundMessage);
  }
  return std::move(*row);
}

std::int64_t queryInt(db::Database& db, std::string_view sql, const Binder& bind, std::int64_t fallback) {
  auto statement = db.prepare(sql);
  if (bind) bind(statement);
  if (!statement.step() || statement.isNull(0)) {
    return fallback;
  }
  return statement.getInt(0);
}

void execute(db::Database& db, std::string_view sql, const Binder& bind) {
  auto statement = db.prepare(sql);
  if (bind) bind(statement);
  statement.run();
}

void audit(const Context& context, std::string_view action, std::string_view entity, std::string_view entityId,
           const Json& details) {
  execute(context.db,
          "INSERT INTO audit_log (action, user_id, entity, entity_id, details) VALUES (?1, ?2, ?3, ?4, ?5)",
          [&](db::Statement& s) {
            s.bind(1, action);
            if (context.actor) {
              s.bind(2, context.actor->id);
            } else {
              s.bind(2, std::nullopt);
            }
            s.bind(3, entity);
            s.bind(4, entityId);
            s.bind(5, details.dump());
          });
}

std::int64_t nextCounter(db::Database& db, std::string_view name) {
  auto statement =
      db.prepare("UPDATE document_counters SET next_value = next_value + 1 WHERE name = ?1 RETURNING next_value - 1");
  statement.bind(1, name);
  if (!statement.step()) {
    throw ApiError(errc::kInternal, "No existe el contador " + std::string(name));
  }
  const auto value = statement.getInt(0);
  statement.run();
  return value;
}

std::optional<std::string> optionalDocumentId(const Params& params, std::string_view key) {
  auto raw = params.optionalString(key, 20);
  if (!raw) {
    return std::nullopt;
  }
  std::string digits;
  for (const char c : *raw) {
    if (c == '-' || c == ' ') continue;
    digits.push_back(c);
  }
  if (!text::isDigits(digits) || (digits.size() != 9 && digits.size() != 11)) {
    invalidField(params.field(key), "debe ser un RNC (9 dígitos) o una cédula (11 dígitos)");
  }
  return digits;
}

std::string likePattern(const std::string& term) {
  std::string pattern = "%";
  for (const char c : term) {
    if (c == '%' || c == '_' || c == '\\') {
      pattern.push_back('\\');
    }
    pattern.push_back(c);
  }
  pattern.push_back('%');
  return pattern;
}

std::optional<std::string> openCashSessionId(db::Database& db) {
  auto statement = db.prepare("SELECT id FROM cash_sessions WHERE closed_at IS NULL LIMIT 1");
  if (!statement.step()) {
    return std::nullopt;
  }
  return statement.getText(0);
}

std::string requireOpenCashSession(db::Database& db) {
  auto id = openCashSessionId(db);
  if (!id) {
    throw ApiError(errc::kCashSessionClosed, "No hay una caja abierta");
  }
  return std::move(*id);
}

namespace {

bool digitsAt(std::string_view value, std::size_t from, std::size_t count) {
  for (std::size_t i = from; i < from + count; ++i) {
    if (value[i] < '0' || value[i] > '9') return false;
  }
  return true;
}

int twoDigits(std::string_view value, std::size_t from) { return (value[from] - '0') * 10 + (value[from + 1] - '0'); }

}  // namespace

bool isIsoMonth(std::string_view value) {
  if (value.size() != 7 || value[4] != '-' || !digitsAt(value, 0, 4) || !digitsAt(value, 5, 2)) {
    return false;
  }
  const int month = twoDigits(value, 5);
  return month >= 1 && month <= 12;
}

bool isIsoDate(std::string_view value) {
  if (value.size() != 10 || value[7] != '-' || !isIsoMonth(value.substr(0, 7)) || !digitsAt(value, 8, 2)) {
    return false;
  }
  const int day = twoDigits(value, 8);
  return day >= 1 && day <= 31;
}

void requireExists(db::Database& db, std::string_view table, const std::string& id, const std::string& message) {
  const auto found = queryInt(db, "SELECT count(*) FROM " + std::string(table) + " WHERE id = ?1",
                              [&](db::Statement& s) { s.bind(1, id); });
  if (found == 0) {
    throw ApiError(errc::kNotFound, message);
  }
}

}  // namespace voxon::services
