#pragma once

#include <chrono>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

#include "core/json.hpp"
#include "db/sqlite.hpp"

namespace voxon {

class Params;

enum class Role { Owner, Manager, Cashier, Waiter, Kitchen };

std::string_view toString(Role role);
std::optional<Role> parseRole(std::string_view value);

// Grupos de roles para los permisos de cada método.
namespace roles {
inline const std::vector<Role> kOwner = {Role::Owner};
inline const std::vector<Role> kManagers = {Role::Owner, Role::Manager};
inline const std::vector<Role> kCash = {Role::Owner, Role::Manager, Role::Cashier};
inline const std::vector<Role> kFloor = {Role::Owner, Role::Manager, Role::Cashier, Role::Waiter};
inline const std::vector<Role> kKitchen = {Role::Owner, Role::Manager, Role::Waiter, Role::Kitchen};
}  // namespace roles

/// Empleado que hace la solicitud.
struct Actor {
  std::string id;
  std::string name;
  Role role = Role::Cashier;
};

struct EngineOptions {
  /// Iteraciones de PBKDF2 para los PIN nuevos.
  std::uint32_t pinIterations = 60000;
  /// PIN incorrectos seguidos (en un minuto) antes de bloquear el acceso.
  int loginMaxFailures = 5;
  /// Duración del bloqueo tras demasiados intentos.
  std::chrono::seconds loginLockDuration{30};
};

/// Frena los intentos de adivinar un PIN.
class LoginThrottle {
 public:
  explicit LoginThrottle(const EngineOptions& options) : options_(options) {}

  /// Lanza too_many_attempts mientras dure un bloqueo.
  void check();
  void recordFailure();
  void recordSuccess();

 private:
  using Clock = std::chrono::steady_clock;

  const EngineOptions& options_;
  std::vector<Clock::time_point> failures_;
  Clock::time_point lockedUntil_{};
};

/// Datos disponibles para un método mientras atiende una solicitud.
struct Context {
  db::Database& db;
  const Params& params;
  const std::optional<Actor>& actor;
  const EngineOptions& options;
  LoginThrottle& loginThrottle;
  const std::string& databasePath;

  /// Empleado autenticado; lanza unauthorized si no hay.
  const Actor& requireActor() const;
};

struct MethodSpec {
  std::function<Json(Context&)> handler;
  /// false para métodos sin sesión (estado, configuración inicial, login).
  bool requiresActor = true;
  /// Roles permitidos; vacío = cualquier empleado activo.
  std::vector<Role> roles;
  /// true envuelve el método en una transacción de escritura.
  bool writes = true;
};

class Registry {
 public:
  void add(std::string name, MethodSpec spec);
  const MethodSpec* find(std::string_view name) const;
  std::vector<std::string> names() const;

 private:
  std::map<std::string, MethodSpec, std::less<>> methods_;
};

Json errorResponse(std::string_view code, std::string_view message);

/// Serializa sin fallar ante texto UTF-8 inválido.
std::string dumpJson(const Json& json);

/// Motor local: una base de datos y los métodos de la API.
class Engine {
 public:
  /// Abre la base y aplica migraciones. Lanza ApiError si falla.
  static std::unique_ptr<Engine> open(const std::string& path, EngineOptions options = {});

  Engine(const Engine&) = delete;
  Engine& operator=(const Engine&) = delete;

  /// Atiende una solicitud. Nunca lanza: los errores vuelven como respuesta.
  Json execute(const Json& request);
  std::string execute(std::string_view requestText);

  int schemaVersion() const noexcept { return schemaVersion_; }
  std::vector<std::string> methods() const { return registry_.names(); }

 private:
  Engine(db::Database db, std::string path, EngineOptions options, int schemaVersion);

  Json dispatch(const Json& request);
  Actor resolveActor(const Json& request);

  std::mutex mutex_;
  db::Database db_;
  std::string path_;
  EngineOptions options_;
  LoginThrottle loginThrottle_;
  int schemaVersion_;
  Registry registry_;
};

}  // namespace voxon
