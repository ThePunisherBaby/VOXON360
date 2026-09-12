#include "db/sqlite.hpp"

#include <sqlite3.h>

#include <string>
#include <utility>

#include "core/error.hpp"

namespace voxon::db {

namespace {

constexpr int kBusyTimeoutMs = 5000;
constexpr std::string_view kTriggerPrefix = "voxon:";

bool isCodeChar(char c) { return (c >= 'a' && c <= 'z') || c == '_'; }

}  // namespace

void throwSqliteError(sqlite3* db, int rc) {
  const std::string message = db != nullptr ? sqlite3_errmsg(db) : sqlite3_errstr(rc);

  // Reglas de los triggers: RAISE(ABORT, 'voxon:<codigo>').
  const auto prefix = message.find(kTriggerPrefix);
  if (prefix != std::string::npos) {
    auto end = prefix + kTriggerPrefix.size();
    while (end < message.size() && isCodeChar(message[end])) {
      ++end;
    }
    throw ApiError(message.substr(prefix + kTriggerPrefix.size(), end - prefix - kTriggerPrefix.size()), message);
  }

  const int extended = db != nullptr ? sqlite3_extended_errcode(db) : rc;
  switch (extended & 0xff) {
    case SQLITE_CONSTRAINT:
      if (extended == SQLITE_CONSTRAINT_UNIQUE || extended == SQLITE_CONSTRAINT_PRIMARYKEY) {
        throw ApiError(errc::kConflict, message);
      }
      throw ApiError(errc::kValidation, message);
    case SQLITE_BUSY:
    case SQLITE_LOCKED:
      throw ApiError("database_busy", message);
    default:
      throw ApiError(errc::kDatabase, message);
  }
}

// --- Database -----------------------------------------------------------------

Database Database::open(const std::string& path) {
  sqlite3* handle = nullptr;
  const int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_EXRESCODE;
  const int rc = sqlite3_open_v2(path.c_str(), &handle, flags, nullptr);
  if (rc != SQLITE_OK) {
    const std::string message = handle != nullptr ? sqlite3_errmsg(handle) : sqlite3_errstr(rc);
    sqlite3_close(handle);
    throw ApiError(errc::kDatabase, "No se pudo abrir la base de datos '" + path + "': " + message);
  }

  Database db(handle);
  sqlite3_busy_timeout(handle, kBusyTimeoutMs);
  db.exec("PRAGMA foreign_keys = ON;");
  db.exec("PRAGMA trusted_schema = OFF;");
  if (path != ":memory:" && !path.empty()) {
    // WAL permite leer (reportes, respaldos) mientras se escribe.
    db.exec("PRAGMA journal_mode = WAL;");
    db.exec("PRAGMA synchronous = NORMAL;");
  }
  return db;
}

Database::Database(Database&& other) noexcept : handle_(std::exchange(other.handle_, nullptr)) {}

Database& Database::operator=(Database&& other) noexcept {
  if (this != &other) {
    sqlite3_close_v2(handle_);
    handle_ = std::exchange(other.handle_, nullptr);
  }
  return *this;
}

Database::~Database() { sqlite3_close_v2(handle_); }

void Database::exec(std::string_view sql) {
  const std::string text(sql);
  char* error = nullptr;
  const int rc = sqlite3_exec(handle_, text.c_str(), nullptr, nullptr, &error);
  sqlite3_free(error);
  if (rc != SQLITE_OK) {
    throwSqliteError(handle_, rc);
  }
}

Statement Database::prepare(std::string_view sql) {
  sqlite3_stmt* stmt = nullptr;
  const int rc = sqlite3_prepare_v2(handle_, sql.data(), static_cast<int>(sql.size()), &stmt, nullptr);
  if (rc != SQLITE_OK) {
    throwSqliteError(handle_, rc);
  }
  return Statement(handle_, stmt);
}

int Database::userVersion() {
  auto stmt = prepare("PRAGMA user_version");
  stmt.step();
  return static_cast<int>(stmt.getInt(0));
}

void Database::setUserVersion(int version) {
  exec("PRAGMA user_version = " + std::to_string(version));
}

// --- Statement ----------------------------------------------------------------

Statement::Statement(Statement&& other) noexcept
    : db_(std::exchange(other.db_, nullptr)), stmt_(std::exchange(other.stmt_, nullptr)) {}

Statement& Statement::operator=(Statement&& other) noexcept {
  if (this != &other) {
    sqlite3_finalize(stmt_);
    db_ = std::exchange(other.db_, nullptr);
    stmt_ = std::exchange(other.stmt_, nullptr);
  }
  return *this;
}

Statement::~Statement() { sqlite3_finalize(stmt_); }

void Statement::check(int rc) const {
  if (rc != SQLITE_OK) {
    throwSqliteError(db_, rc);
  }
}

Statement& Statement::bind(int index, std::int64_t value) {
  check(sqlite3_bind_int64(stmt_, index, value));
  return *this;
}

Statement& Statement::bind(int index, std::string_view value) {
  check(sqlite3_bind_text(stmt_, index, value.data(), static_cast<int>(value.size()), SQLITE_TRANSIENT));
  return *this;
}

Statement& Statement::bind(int index, std::nullopt_t) {
  check(sqlite3_bind_null(stmt_, index));
  return *this;
}

Statement& Statement::bind(int index, const std::optional<std::string>& value) {
  return value ? bind(index, std::string_view(*value)) : bind(index, std::nullopt);
}

Statement& Statement::bind(int index, const std::optional<std::int64_t>& value) {
  return value ? bind(index, *value) : bind(index, std::nullopt);
}

bool Statement::step() {
  const int rc = sqlite3_step(stmt_);
  if (rc == SQLITE_ROW) {
    return true;
  }
  if (rc == SQLITE_DONE) {
    return false;
  }
  throwSqliteError(db_, rc);
}

void Statement::run() {
  while (step()) {
  }
}

Statement::ColumnType Statement::columnType(int column) const {
  switch (sqlite3_column_type(stmt_, column)) {
    case SQLITE_INTEGER: return ColumnType::Integer;
    case SQLITE_FLOAT: return ColumnType::Float;
    case SQLITE_TEXT: return ColumnType::Text;
    case SQLITE_BLOB: return ColumnType::Blob;
    default: return ColumnType::Null;
  }
}

double Statement::getDouble(int column) const { return sqlite3_column_double(stmt_, column); }

bool Statement::isNull(int column) const { return sqlite3_column_type(stmt_, column) == SQLITE_NULL; }

std::int64_t Statement::getInt(int column) const { return sqlite3_column_int64(stmt_, column); }

std::optional<std::int64_t> Statement::getOptionalInt(int column) const {
  if (isNull(column)) {
    return std::nullopt;
  }
  return getInt(column);
}

std::string Statement::getText(int column) const {
  const auto* text = sqlite3_column_text(stmt_, column);
  if (text == nullptr) {
    return {};
  }
  return std::string(reinterpret_cast<const char*>(text), static_cast<size_t>(sqlite3_column_bytes(stmt_, column)));
}

std::optional<std::string> Statement::getOptionalText(int column) const {
  if (isNull(column)) {
    return std::nullopt;
  }
  return getText(column);
}

int Statement::columnCount() const { return sqlite3_column_count(stmt_); }

std::string Statement::columnName(int column) const { return sqlite3_column_name(stmt_, column); }

// --- Transaction --------------------------------------------------------------

Transaction::Transaction(Database& db) : db_(db) { db_.exec("BEGIN IMMEDIATE"); }

Transaction::~Transaction() {
  if (!done_) {
    sqlite3_exec(db_.handle(), "ROLLBACK", nullptr, nullptr, nullptr);
  }
}

void Transaction::commit() {
  db_.exec("COMMIT");
  done_ = true;
}

}  // namespace voxon::db
