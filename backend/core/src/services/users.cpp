#include "services/users.hpp"

#include <optional>

#include "core/error.hpp"
#include "crypto/crypto.hpp"
#include "services/common.hpp"
#include "services/services.hpp"
#include "text/text.hpp"

namespace voxon::services {

namespace {

constexpr std::size_t kSaltBytes = 16;
constexpr const char* kSelectPublicUser = "SELECT id, name, role, active, created_at FROM users WHERE id = ?1";

struct UserRow {
  std::string id;
  std::string name;
  std::string role;
};

void validatePin(const std::string& pin, const std::string& field) {
  if (!text::isDigits(pin) || pin.size() < 4 || pin.size() > 6) {
    invalidField(field, "debe tener de 4 a 6 dígitos");
  }
}

std::string hashPin(const std::string& pin, const std::string& salt, std::uint32_t iterations) {
  return crypto::toHex(crypto::pbkdf2HmacSha256(pin, salt, iterations, 32));
}

// Recorre a todos los empleados activos para que el tiempo de respuesta no
// revele cuál coincide.
std::optional<UserRow> findActiveUserByPin(db::Database& db, const std::string& pin,
                                           const std::string* excludeId = nullptr) {
  auto statement = db.prepare("SELECT id, name, role, pin_hash, pin_salt, pin_iterations FROM users WHERE active = 1");
  std::optional<UserRow> match;
  while (statement.step()) {
    const auto id = statement.getText(0);
    const auto computed = hashPin(pin, statement.getText(4), static_cast<std::uint32_t>(statement.getInt(5)));
    const bool equal = crypto::constantTimeEquals(computed, statement.getText(3));
    if (equal && !match && (excludeId == nullptr || id != *excludeId)) {
      match = UserRow{id, statement.getText(1), statement.getText(2)};
    }
  }
  return match;
}

Json publicUser(db::Database& db, const std::string& id) {
  return requireOne(db, kSelectPublicUser, [&](db::Statement& s) { s.bind(1, id); }, "El empleado no existe");
}

Role roleOf(const Json& user) { return parseRole(user["role"].get<std::string>()).value_or(Role::Cashier); }

Role requireRole(const Params& params, const char* key) {
  return *parseRole(params.requireEnum(key, {"owner", "manager", "cashier", "waiter", "kitchen"}));
}

// Un gerente administra cajeros, meseros y cocina; dueños y gerentes solo el dueño.
void checkCanManage(const Actor& actor, Role target) {
  if (actor.role != Role::Owner && (target == Role::Owner || target == Role::Manager)) {
    throw ApiError(errc::kForbidden, "Solo el dueño puede administrar dueños y gerentes");
  }
}

void keepOneOwner(db::Database& db, const Json& target) {
  const bool isActiveOwner = roleOf(target) == Role::Owner && target["active"].get<bool>();
  if (isActiveOwner && queryInt(db, "SELECT count(*) FROM users WHERE role = 'owner' AND active = 1") <= 1) {
    throw ApiError(errc::kConflict, "Debe quedar al menos un dueño activo");
  }
}

void storePin(const Context& context, const std::string& userId, const std::string& pin) {
  const auto salt = crypto::toHex(crypto::randomBytes(kSaltBytes));
  const auto iterations = context.options.pinIterations;
  execute(context.db, "UPDATE users SET pin_hash = ?1, pin_salt = ?2, pin_iterations = ?3 WHERE id = ?4",
          [&](db::Statement& s) {
            s.bind(1, hashPin(pin, salt, iterations));
            s.bind(2, salt);
            s.bind(3, static_cast<std::int64_t>(iterations));
            s.bind(4, userId);
          });
}

void requireUniquePin(const Context& context, const std::string& pin, const std::string* excludeId) {
  if (findActiveUserByPin(context.db, pin, excludeId)) {
    throw ApiError(errc::kConflict, "Otro empleado ya usa ese PIN");
  }
}

Json login(Context& context) {
  context.loginThrottle.check();
  const auto pin = context.params.requireString("pin", 6);
  std::optional<UserRow> user;
  if (text::isDigits(pin) && pin.size() >= 4) {
    user = findActiveUserByPin(context.db, pin);
  }
  if (!user) {
    context.loginThrottle.recordFailure();
    throw ApiError(errc::kUnauthorized, "PIN incorrecto");
  }
  context.loginThrottle.recordSuccess();
  audit(context, "user.login", "user", user->id);

  Json result = Json::object();
  result["id"] = user->id;
  result["name"] = user->name;
  result["role"] = user->role;
  return result;
}

Json list(Context& context) {
  return queryAll(context.db,
                  "SELECT id, name, role, active, created_at FROM users ORDER BY active DESC, name COLLATE NOCASE");
}

Json create(Context& context) {
  const auto& actor = context.requireActor();
  const auto role = requireRole(context.params, "role");
  checkCanManage(actor, role);
  return createUser(context, context.params.requireString("name", 60), role, context.params.requireString("pin", 6));
}

Json update(Context& context) {
  const auto& actor = context.requireActor();
  const auto id = context.params.requireString("id", 36);
  const auto target = publicUser(context.db, id);
  const auto currentRole = roleOf(target);
  checkCanManage(actor, currentRole);

  auto newRole = currentRole;
  if (context.params.has("role")) {
    newRole = requireRole(context.params, "role");
    checkCanManage(actor, newRole);
    if (newRole != currentRole) {
      if (id == actor.id) {
        throw ApiError(errc::kForbidden, "No puedes cambiar tu propio rol");
      }
      if (currentRole == Role::Owner) {
        keepOneOwner(context.db, target);
      }
    }
  }
  const auto name =
      context.params.has("name") ? context.params.requireString("name", 60) : target["name"].get<std::string>();

  execute(context.db, "UPDATE users SET name = ?1, role = ?2 WHERE id = ?3", [&](db::Statement& s) {
    s.bind(1, name);
    s.bind(2, toString(newRole));
    s.bind(3, id);
  });
  audit(context, "user.update", "user", id, Json{{"name", name}, {"role", std::string(toString(newRole))}});
  return publicUser(context.db, id);
}

// Cambiar el propio PIN exige el actual; un gerente puede asignar el de otros.
Json setPin(Context& context) {
  const auto& actor = context.requireActor();
  const auto targetId = context.params.optionalString("userId", 36).value_or(actor.id);
  const auto pin = context.params.requireString("pin", 6);
  validatePin(pin, "pin");
  const auto target = publicUser(context.db, targetId);

  if (targetId == actor.id) {
    context.loginThrottle.check();
    const auto currentPin = context.params.requireString("currentPin", 6);
    const auto match = findActiveUserByPin(context.db, currentPin);
    if (!match || match->id != actor.id) {
      context.loginThrottle.recordFailure();
      throw ApiError(errc::kUnauthorized, "El PIN actual no es correcto");
    }
  } else {
    if (actor.role != Role::Owner && actor.role != Role::Manager) {
      throw ApiError(errc::kForbidden, "Solo el dueño o un gerente pueden cambiar el PIN de otro empleado");
    }
    checkCanManage(actor, roleOf(target));
  }

  requireUniquePin(context, pin, &targetId);
  storePin(context, targetId, pin);
  audit(context, "user.setPin", "user", targetId);
  return publicUser(context.db, targetId);
}

Json deactivate(Context& context) {
  const auto& actor = context.requireActor();
  const auto id = context.params.requireString("id", 36);
  if (id == actor.id) {
    throw ApiError(errc::kForbidden, "No puedes desactivarte a ti mismo");
  }
  const auto target = publicUser(context.db, id);
  checkCanManage(actor, roleOf(target));
  keepOneOwner(context.db, target);
  execute(context.db, "UPDATE users SET active = 0 WHERE id = ?1", [&](db::Statement& s) { s.bind(1, id); });
  audit(context, "user.deactivate", "user", id);
  return publicUser(context.db, id);
}

// Al reactivar se asigna un PIN nuevo: el anterior pudo haberlo tomado otro.
Json activate(Context& context) {
  const auto& actor = context.requireActor();
  const auto id = context.params.requireString("id", 36);
  const auto pin = context.params.requireString("pin", 6);
  validatePin(pin, "pin");
  const auto target = publicUser(context.db, id);
  checkCanManage(actor, roleOf(target));
  requireUniquePin(context, pin, &id);
  execute(context.db, "UPDATE users SET active = 1 WHERE id = ?1", [&](db::Statement& s) { s.bind(1, id); });
  storePin(context, id, pin);
  audit(context, "user.activate", "user", id);
  return publicUser(context.db, id);
}

}  // namespace

Json createUser(const Context& context, const std::string& name, Role role, const std::string& pin) {
  validatePin(pin, "pin");
  requireUniquePin(context, pin, nullptr);

  const auto id = newId();
  const auto salt = crypto::toHex(crypto::randomBytes(kSaltBytes));
  const auto iterations = context.options.pinIterations;
  execute(context.db,
          "INSERT INTO users (id, name, role, pin_hash, pin_salt, pin_iterations) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
          [&](db::Statement& s) {
            s.bind(1, id);
            s.bind(2, name);
            s.bind(3, toString(role));
            s.bind(4, hashPin(pin, salt, iterations));
            s.bind(5, salt);
            s.bind(6, static_cast<std::int64_t>(iterations));
          });
  audit(context, "user.create", "user", id, Json{{"name", name}, {"role", std::string(toString(role))}});
  return publicUser(context.db, id);
}

void registerUsers(Registry& registry) {
  registry.add("users.login", {login, /*requiresActor=*/false, {}, /*writes=*/true});
  registry.add("users.list", {list, true, roles::kManagers, false});
  registry.add("users.create", {create, true, roles::kManagers, true});
  registry.add("users.update", {update, true, roles::kManagers, true});
  registry.add("users.setPin", {setPin, true, {}, true});
  registry.add("users.deactivate", {deactivate, true, roles::kManagers, true});
  registry.add("users.activate", {activate, true, roles::kManagers, true});
}

}  // namespace voxon::services
