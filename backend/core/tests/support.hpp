#pragma once

#include <doctest/doctest.h>

#include <memory>
#include <string>

#include "core/engine.hpp"
#include "core/json.hpp"

namespace voxon::testing {

/// PIN rápidos y bloqueo tras 3 intentos para que las pruebas vayan ligeras.
inline EngineOptions fastOptions() {
  EngineOptions options;
  options.pinIterations = 1;
  options.loginMaxFailures = 3;
  options.loginLockDuration = std::chrono::seconds(60);
  return options;
}

inline std::unique_ptr<Engine> openEngine() { return Engine::open(":memory:", fastOptions()); }

inline Json request(const std::string& method, const Json& params, const std::string& actor) {
  Json body = Json::object();
  body["method"] = method;
  body["params"] = params;
  if (!actor.empty()) {
    body["actor"] = actor;
  }
  return body;
}

/// Llama un método que debe funcionar y devuelve su resultado.
inline Json call(Engine& engine, const std::string& method, const Json& params = Json::object(),
                 const std::string& actor = "") {
  const auto response = engine.execute(request(method, params, actor));
  const std::string context = method + " -> " + response.dump();
  INFO(context);
  REQUIRE(response["ok"].get<bool>());
  return response["result"];
}

/// Llama un método que debe fallar con `code`.
inline Json callError(Engine& engine, const std::string& method, const Json& params, const std::string& actor,
                      const std::string& code) {
  const auto response = engine.execute(request(method, params, actor));
  const std::string context = method + " -> " + response.dump();
  INFO(context);
  REQUIRE_FALSE(response["ok"].get<bool>());
  CHECK(response["error"]["code"].get<std::string>() == code);
  return response["error"];
}

/// Configura un negocio con dueña "Ana" (PIN 1111) y devuelve su id.
inline std::string setupBusiness(Engine& engine, const std::string& type = "colmado") {
  const auto result = call(engine, "business.setup",
                           Json{{"business", {{"name", "Colmado La Esquina"}, {"businessType", type}}},
                                {"owner", {{"name", "Ana"}, {"pin", "1111"}}}});
  return result["owner"]["id"].get<std::string>();
}

inline std::string createUser(Engine& engine, const std::string& actor, const std::string& name,
                              const std::string& role, const std::string& pin) {
  return call(engine, "users.create", Json{{"name", name}, {"role", role}, {"pin", pin}}, actor)["id"]
      .get<std::string>();
}

}  // namespace voxon::testing
