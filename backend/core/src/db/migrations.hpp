#pragma once

#include <string_view>
#include <vector>

namespace voxon::db {

class Database;

struct Migration {
  /// Nombre del archivo, p. ej. "0001_schema.sql". El prefijo es la versión.
  std::string_view name;
  std::string_view sql;
};

/// Migraciones de backend/sql/migrations incrustadas al compilar.
const std::vector<Migration>& embeddedMigrations();

/// Versión de una migración a partir de su nombre: "0003_views.sql" → 3.
int migrationVersion(std::string_view name);

/// Aplica, cada una en su transacción, las migraciones con versión mayor que
/// PRAGMA user_version. Devuelve la versión final del esquema.
int migrate(Database& db, const std::vector<Migration>& migrations);

}  // namespace voxon::db
