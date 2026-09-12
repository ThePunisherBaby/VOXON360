#include "db/migrations.hpp"

#include <algorithm>
#include <string>

#include "core/error.hpp"
#include "db/sqlite.hpp"

namespace voxon::db {

int migrationVersion(std::string_view name) {
  int version = 0;
  size_t i = 0;
  while (i < name.size() && name[i] >= '0' && name[i] <= '9') {
    version = version * 10 + (name[i] - '0');
    ++i;
  }
  if (i == 0 || i >= name.size() || name[i] != '_') {
    throw ApiError(errc::kInternal, "Nombre de migración inválido: " + std::string(name));
  }
  return version;
}

int migrate(Database& db, const std::vector<Migration>& migrations) {
  std::vector<const Migration*> ordered;
  ordered.reserve(migrations.size());
  for (const auto& migration : migrations) {
    ordered.push_back(&migration);
  }
  std::sort(ordered.begin(), ordered.end(), [](const Migration* a, const Migration* b) {
    return migrationVersion(a->name) < migrationVersion(b->name);
  });
  for (size_t i = 1; i < ordered.size(); ++i) {
    if (migrationVersion(ordered[i - 1]->name) == migrationVersion(ordered[i]->name)) {
      throw ApiError(errc::kInternal, "Versión de migración repetida: " + std::string(ordered[i]->name));
    }
  }

  int current = db.userVersion();
  const int latest = ordered.empty() ? 0 : migrationVersion(ordered.back()->name);
  if (current > latest) {
    throw ApiError("schema_too_new",
                   "La base de datos es de una versión más nueva del programa (esquema " +
                       std::to_string(current) + ")");
  }

  for (const auto* migration : ordered) {
    const int version = migrationVersion(migration->name);
    if (version <= current) {
      continue;
    }
    Transaction transaction(db);
    db.exec(migration->sql);
    db.setUserVersion(version);
    transaction.commit();
    current = version;
  }
  return current;
}

}  // namespace voxon::db
