#include <sqlite3.h>

#include "core/error.hpp"
#include "services/common.hpp"
#include "services/services.hpp"

namespace voxon::services {

namespace {

Json info(Context& context) {
  Json result = Json::object();
  result["engineVersion"] = VOXON_VERSION;
  result["schemaVersion"] = context.db.userVersion();
  result["sqliteVersion"] = sqlite3_libversion();
  result["databasePath"] = context.databasePath;
  return result;
}

// Copia en caliente con la API de respaldo de SQLite: la base sigue usable.
Json backup(Context& context) {
  const auto destination = context.params.requireString("path", 1024);
  if (destination == context.databasePath) {
    invalidField("path", "no puede ser el mismo archivo de la base de datos");
  }

  sqlite3* target = nullptr;
  int rc = sqlite3_open_v2(destination.c_str(), &target, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nullptr);
  if (rc != SQLITE_OK) {
    const std::string message = target != nullptr ? sqlite3_errmsg(target) : sqlite3_errstr(rc);
    sqlite3_close(target);
    throw ApiError("backup_failed", "No se pudo crear el respaldo: " + message);
  }

  sqlite3_backup* handle = sqlite3_backup_init(target, "main", context.db.handle(), "main");
  if (handle == nullptr) {
    const std::string message = sqlite3_errmsg(target);
    sqlite3_close(target);
    throw ApiError("backup_failed", "No se pudo iniciar el respaldo: " + message);
  }
  do {
    rc = sqlite3_backup_step(handle, 256);
  } while (rc == SQLITE_OK || rc == SQLITE_BUSY || rc == SQLITE_LOCKED);
  const int pages = sqlite3_backup_pagecount(handle);
  sqlite3_backup_finish(handle);
  rc = sqlite3_errcode(target);
  const std::string message = sqlite3_errmsg(target);
  sqlite3_close(target);
  if (rc != SQLITE_OK) {
    throw ApiError("backup_failed", "El respaldo falló: " + message);
  }

  Json result = Json::object();
  result["path"] = destination;
  result["pages"] = pages;
  return result;
}

Json integrityCheck(Context& context) {
  Json problems = Json::array();
  auto integrity = context.db.prepare("PRAGMA integrity_check");
  while (integrity.step()) {
    const auto line = integrity.getText(0);
    if (line != "ok") {
      problems.push_back(line);
    }
  }
  auto foreignKeys = context.db.prepare("PRAGMA foreign_key_check");
  while (foreignKeys.step()) {
    problems.push_back("Referencia rota en " + foreignKeys.getText(0) + " (fila " +
                       std::to_string(foreignKeys.getInt(1)) + ")");
  }
  Json result = Json::object();
  result["ok"] = problems.empty();
  result["problems"] = std::move(problems);
  return result;
}

}  // namespace

void registerSystem(Registry& registry) {
  registry.add("system.info", {info, /*requiresActor=*/false, {}, /*writes=*/false});
  registry.add("system.backup", {backup, true, roles::kOwner, false});
  registry.add("system.integrityCheck", {integrityCheck, true, roles::kManagers, false});
}

}  // namespace voxon::services
