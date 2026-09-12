#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>

struct sqlite3;
struct sqlite3_stmt;

namespace voxon::db {

class Statement;

/// Conexión SQLite con las opciones del motor (claves foráneas, WAL, espera
/// ante bloqueos). Movible, no copiable.
class Database {
 public:
  /// Abre o crea el archivo. ":memory:" crea una base temporal.
  static Database open(const std::string& path);

  Database(Database&& other) noexcept;
  Database& operator=(Database&& other) noexcept;
  Database(const Database&) = delete;
  Database& operator=(const Database&) = delete;
  ~Database();

  /// Ejecuta uno o varios comandos sin resultados.
  void exec(std::string_view sql);

  Statement prepare(std::string_view sql);

  int userVersion();
  void setUserVersion(int version);

  sqlite3* handle() const noexcept { return handle_; }

 private:
  explicit Database(sqlite3* handle) noexcept : handle_(handle) {}

  sqlite3* handle_ = nullptr;
};

/// Consulta preparada. Los índices de parámetros y columnas empiezan en 1 y 0
/// respectivamente, como en SQLite.
class Statement {
 public:
  Statement(Statement&& other) noexcept;
  Statement& operator=(Statement&& other) noexcept;
  Statement(const Statement&) = delete;
  Statement& operator=(const Statement&) = delete;
  ~Statement();

  Statement& bind(int index, std::int64_t value);
  Statement& bind(int index, int value) { return bind(index, static_cast<std::int64_t>(value)); }
  Statement& bind(int index, std::string_view value);
  Statement& bind(int index, const char* value) { return bind(index, std::string_view(value)); }
  Statement& bind(int index, const std::string& value) { return bind(index, std::string_view(value)); }
  Statement& bind(int index, std::nullopt_t);
  Statement& bind(int index, const std::optional<std::string>& value);
  Statement& bind(int index, const std::optional<std::int64_t>& value);

  /// Avanza a la siguiente fila. Devuelve false al terminar.
  bool step();

  /// Ejecuta hasta el final, ignorando filas.
  void run();

  enum class ColumnType { Integer, Float, Text, Blob, Null };

  ColumnType columnType(int column) const;
  double getDouble(int column) const;
  bool isNull(int column) const;
  std::int64_t getInt(int column) const;
  std::optional<std::int64_t> getOptionalInt(int column) const;
  std::string getText(int column) const;
  std::optional<std::string> getOptionalText(int column) const;
  int columnCount() const;
  std::string columnName(int column) const;

 private:
  friend class Database;
  Statement(sqlite3* db, sqlite3_stmt* stmt) noexcept : db_(db), stmt_(stmt) {}

  void check(int rc) const;

  sqlite3* db_ = nullptr;
  sqlite3_stmt* stmt_ = nullptr;
};

/// Transacción con escritura inmediata. Si no se confirma, se revierte al
/// salir del ámbito (también ante excepciones).
class Transaction {
 public:
  explicit Transaction(Database& db);
  Transaction(const Transaction&) = delete;
  Transaction& operator=(const Transaction&) = delete;
  ~Transaction();

  void commit();

 private:
  Database& db_;
  bool done_ = false;
};

/// Convierte un error de SQLite en ApiError. Los mensajes 'voxon:<codigo>' de
/// los triggers conservan su código; las restricciones pasan a conflict o
/// validation_failed.
[[noreturn]] void throwSqliteError(sqlite3* db, int rc);

}  // namespace voxon::db
