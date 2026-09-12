#include "core/engine.hpp"

#include <algorithm>
#include <array>
#include <stdexcept>
#include <utility>

#include "core/error.hpp"
#include "core/params.hpp"
#include "db/migrations.hpp"
#include "services/services.hpp"

namespace voxon {

namespace {

constexpr std::array<std::pair<Role, std::string_view>, 5> kRoleNames = {{
    {Role::Owner, "owner"},
    {Role::Manager, "manager"},
    {Role::Cashier, "cashier"},
    {Role::Waiter, "waiter"},
    {Role::Kitchen, "kitchen"},
}};

}  // namespace

std::string_view toString(Role role) {
  for (const auto& [value, name] : kRoleNames) {
    if (value == role) return name;
  }
  return "cashier";
}

std::optional<Role> parseRole(std::string_view value) {
  for (const auto& [role, name] : kRoleNames) {
    if (name == value) return role;
  }
  return std::nullopt;
}

Json errorResponse(std::string_view code, std::string_view message) {
  Json error = Json::object();
  error["code"] = std::string(code);
  error["message"] = std::string(message);
  Json response = Json::object();
  response["ok"] = false;
  response["error"] = std::move(error);
  return response;
}

std::string dumpJson(const Json& json) { return json.dump(-1, ' ', false, Json::error_handler_t::replace); }

// --- LoginThrottle ------------------------------------------------------------

void LoginThrottle::check() {
  const auto now = Clock::now();
  if (now < lockedUntil_) {
    const auto seconds = std::chrono::duration_cast<std::chrono::seconds>(lockedUntil_ - now).count() + 1;
    throw ApiError("too_many_attempts",
                   "Demasiados PIN incorrectos. Espera " + std::to_string(seconds) + " segundos");
  }
}

void LoginThrottle::recordFailure() {
  const auto now = Clock::now();
  failures_.erase(std::remove_if(failures_.begin(), failures_.end(),
                                 [&](auto time) { return now - time > std::chrono::minutes(1); }),
                  failures_.end());
  failures_.push_back(now);
  if (static_cast<int>(failures_.size()) >= options_.loginMaxFailures) {
    lockedUntil_ = now + options_.loginLockDuration;
    failures_.clear();
  }
}

void LoginThrottle::recordSuccess() { failures_.clear(); }

// --- Context y Registry -------------------------------------------------------

const Actor& Context::requireActor() const {
  if (!actor) {
    throw ApiError(errc::kUnauthorized, "Inicia sesión con tu PIN");
  }
  return *actor;
}

void Registry::add(std::string name, MethodSpec spec) {
  if (!methods_.emplace(std::move(name), std::move(spec)).second) {
    throw std::logic_error("Método registrado dos veces");
  }
}

const MethodSpec* Registry::find(std::string_view name) const {
  const auto it = methods_.find(name);
  return it == methods_.end() ? nullptr : &it->second;
}

std::vector<std::string> Registry::names() const {
  std::vector<std::string> names;
  names.reserve(methods_.size());
  for (const auto& entry : methods_) {
    names.push_back(entry.first);
  }
  return names;
}

// --- Engine -------------------------------------------------------------------

std::unique_ptr<Engine> Engine::open(const std::string& path, EngineOptions options) {
  auto db = db::Database::open(path);
  const int version = db::migrate(db, db::embeddedMigrations());
  return std::unique_ptr<Engine>(new Engine(std::move(db), path, options, version));
}

Engine::Engine(db::Database db, std::string path, EngineOptions options, int schemaVersion)
    : db_(std::move(db)),
      path_(std::move(path)),
      options_(options),
      loginThrottle_(options_),
      schemaVersion_(schemaVersion) {
  services::registerAll(registry_);
}

Json Engine::execute(const Json& request) {
  std::lock_guard<std::mutex> lock(mutex_);
  Json response;
  try {
    Json result = dispatch(request);
    response = Json::object();
    response["ok"] = true;
    response["result"] = std::move(result);
  } catch (const ApiError& error) {
    response = errorResponse(error.code(), error.what());
  } catch (const Json::exception& error) {
    response = errorResponse(errc::kInvalidRequest, error.what());
  } catch (const std::exception& error) {
    response = errorResponse(errc::kInternal, error.what());
  }
  if (request.is_object() && request.contains("id")) {
    response["id"] = request["id"];
  }
  return response;
}

std::string Engine::execute(std::string_view requestText) {
  try {
    const Json request = Json::parse(requestText.begin(), requestText.end());
    return dumpJson(execute(request));
  } catch (const Json::parse_error& error) {
    return dumpJson(errorResponse(errc::kInvalidRequest, std::string("JSON inválido: ") + error.what()));
  } catch (const std::exception& error) {
    return dumpJson(errorResponse(errc::kInternal, error.what()));
  }
}

Json Engine::dispatch(const Json& request) {
  if (!request.is_object()) {
    throw ApiError(errc::kInvalidRequest, "La solicitud debe ser un objeto JSON");
  }
  const auto methodIt = request.find("method");
  if (methodIt == request.end() || !methodIt->is_string()) {
    throw ApiError(errc::kInvalidRequest, "Falta el campo 'method'");
  }
  const auto& method = methodIt->get_ref<const std::string&>();
  const auto* spec = registry_.find(method);
  if (spec == nullptr) {
    throw ApiError(errc::kUnknownMethod, "Método desconocido: " + method);
  }

  static const Json kNoParams;
  const auto paramsIt = request.find("params");
  const Json& paramsJson = paramsIt == request.end() ? kNoParams : *paramsIt;
  if (!paramsJson.is_null() && !paramsJson.is_object()) {
    throw ApiError(errc::kInvalidRequest, "El campo 'params' debe ser un objeto");
  }
  const Params params(paramsJson);

  std::optional<Actor> actor;
  if (spec->requiresActor) {
    actor = resolveActor(request);
    if (!spec->roles.empty() && std::find(spec->roles.begin(), spec->roles.end(), actor->role) == spec->roles.end()) {
      throw ApiError(errc::kForbidden,
                     "Tu rol (" + std::string(toString(actor->role)) + ") no permite esta operación");
    }
  }

  Context context{db_, params, actor, options_, loginThrottle_, path_};
  if (!spec->writes) {
    return spec->handler(context);
  }
  db::Transaction transaction(db_);
  Json result = spec->handler(context);
  transaction.commit();
  return result;
}

Actor Engine::resolveActor(const Json& request) {
  const auto it = request.find("actor");
  if (it == request.end() || !it->is_string() || it->get_ref<const std::string&>().empty()) {
    throw ApiError(errc::kUnauthorized, "Inicia sesión con tu PIN");
  }
  auto statement = db_.prepare("SELECT id, name, role FROM users WHERE id = ?1 AND active = 1");
  statement.bind(1, it->get_ref<const std::string&>());
  if (!statement.step()) {
    throw ApiError(errc::kUnauthorized, "El usuario no existe o está desactivado");
  }
  const auto role = parseRole(statement.getText(2));
  if (!role) {
    throw ApiError(errc::kInternal, "El usuario tiene un rol desconocido");
  }
  return Actor{statement.getText(0), statement.getText(1), *role};
}

}  // namespace voxon
