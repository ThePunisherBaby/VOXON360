#include <doctest/doctest.h>

#include <filesystem>
#include <string>

#include "crypto/crypto.hpp"
#include "support.hpp"
#include "voxon/voxon.h"

using namespace voxon;
using namespace voxon::testing;

namespace {

std::filesystem::path makeTempDir() {
  auto dir = std::filesystem::temp_directory_path() / ("voxon-test-" + crypto::uuidV4());
  std::filesystem::create_directories(dir);
  return dir;
}

}  // namespace

TEST_CASE("las solicitudes inválidas devuelven errores claros") {
  auto engine = openEngine();
  CHECK(engine->execute(std::string_view("no es json")).find("invalid_request") != std::string::npos);
  callError(*engine, "no.existe", Json::object(), "", "unknown_method");

  Json badParams = {{"method", "business.status"}, {"params", 5}};
  CHECK(engine->execute(badParams)["error"]["code"] == "invalid_request");

  Json withId = {{"method", "system.info"}, {"id", 7}};
  const auto response = engine->execute(withId);
  CHECK(response["id"] == 7);
  CHECK(response["result"]["schemaVersion"].get<int>() == engine->schemaVersion());
}

TEST_CASE("la configuración inicial crea el negocio y el dueño una sola vez") {
  auto engine = openEngine();
  CHECK_FALSE(call(*engine, "business.status")["configured"].get<bool>());

  const auto ownerId = setupBusiness(*engine, "restaurant");
  const auto status = call(*engine, "business.status");
  CHECK(status["configured"].get<bool>());
  CHECK(status["business"]["priceMode"] == "tax_excluded");
  CHECK(status["business"]["legalTipEnabled"].get<bool>());

  callError(*engine, "business.setup",
            Json{{"business", {{"name", "Otro"}, {"businessType", "store"}}},
                 {"owner", {{"name", "Beto"}, {"pin", "2222"}}}},
            "", "already_configured");
  CHECK(call(*engine, "users.login", Json{{"pin", "1111"}})["id"] == ownerId);
}

TEST_CASE("si la configuración inicial falla no se guarda nada") {
  auto engine = openEngine();
  callError(*engine, "business.setup",
            Json{{"business", {{"name", "Colmado"}, {"businessType", "colmado"}}},
                 {"owner", {{"name", "Ana"}, {"pin", "12"}}}},
            "", "validation_failed");
  CHECK_FALSE(call(*engine, "business.status")["configured"].get<bool>());
}

TEST_CASE("el negocio se actualiza solo en los campos enviados") {
  auto engine = openEngine();
  const auto owner = setupBusiness(*engine);
  const auto updated =
      call(*engine, "business.update", Json{{"rnc", "101-00000-1"}, {"phone", "809-555-1234"}}, owner);
  CHECK(updated["rnc"] == "101000001");
  CHECK(updated["name"] == "Colmado La Esquina");

  const auto cleared = call(*engine, "business.update", Json{{"phone", nullptr}}, owner);
  CHECK(cleared["phone"].is_null());
  CHECK(cleared["rnc"] == "101000001");
  callError(*engine, "business.update", Json{{"rnc", "123"}}, owner, "validation_failed");
}

TEST_CASE("el PIN se bloquea tras varios intentos fallidos") {
  auto engine = openEngine();
  setupBusiness(*engine);
  callError(*engine, "users.login", Json{{"pin", "9999"}}, "", "unauthorized");
  callError(*engine, "users.login", Json{{"pin", "8888"}}, "", "unauthorized");
  callError(*engine, "users.login", Json{{"pin", "7777"}}, "", "unauthorized");
  callError(*engine, "users.login", Json{{"pin", "1111"}}, "", "too_many_attempts");
}

TEST_CASE("permisos por rol") {
  auto engine = openEngine();
  const auto owner = setupBusiness(*engine);
  const auto cashier = createUser(*engine, owner, "Luis", "cashier", "2222");

  callError(*engine, "users.list", Json::object(), "", "unauthorized");
  callError(*engine, "users.list", Json::object(), cashier, "forbidden");
  CHECK(call(*engine, "users.list", Json::object(), owner).size() == 2);

  // El PIN identifica al empleado: no puede repetirse.
  callError(*engine, "users.create", Json{{"name", "Otro"}, {"role", "waiter"}, {"pin", "2222"}}, owner, "conflict");

  const auto manager = createUser(*engine, owner, "Marta", "manager", "3333");
  callError(*engine, "users.create", Json{{"name", "Jefe"}, {"role", "owner"}, {"pin", "4444"}}, manager,
            "forbidden");
  CHECK_FALSE(createUser(*engine, manager, "Pedro", "waiter", "4444").empty());
}

TEST_CASE("siempre queda un dueño y nadie cambia su propio rol ni se desactiva") {
  auto engine = openEngine();
  const auto owner = setupBusiness(*engine);
  callError(*engine, "users.deactivate", Json{{"id", owner}}, owner, "forbidden");

  const auto secondOwner = createUser(*engine, owner, "Beto", "owner", "5555");
  call(*engine, "users.deactivate", Json{{"id", owner}}, secondOwner);
  callError(*engine, "users.login", Json{{"pin", "1111"}}, "", "unauthorized");
  callError(*engine, "users.update", Json{{"id", secondOwner}, {"role", "manager"}}, secondOwner, "forbidden");

  // Al reactivar se asigna un PIN nuevo.
  call(*engine, "users.activate", Json{{"id", owner}, {"pin", "1212"}}, secondOwner);
  CHECK(call(*engine, "users.login", Json{{"pin", "1212"}})["id"] == owner);
}

TEST_CASE("cambio de PIN") {
  auto engine = openEngine();
  const auto owner = setupBusiness(*engine);
  call(*engine, "users.setPin", Json{{"currentPin", "1111"}, {"pin", "1234"}}, owner);
  CHECK(call(*engine, "users.login", Json{{"pin", "1234"}})["id"] == owner);
  callError(*engine, "users.login", Json{{"pin", "1111"}}, "", "unauthorized");

  const auto cashier = createUser(*engine, owner, "Luis", "cashier", "2222");
  callError(*engine, "users.setPin", Json{{"userId", owner}, {"pin", "5555"}}, cashier, "forbidden");
  callError(*engine, "users.setPin", Json{{"currentPin", "0000"}, {"pin", "4321"}}, owner, "unauthorized");
  call(*engine, "users.setPin", Json{{"userId", cashier}, {"pin", "6666"}}, owner);
  CHECK(call(*engine, "users.login", Json{{"pin", "6666"}})["id"] == cashier);
}

TEST_CASE("respaldo en caliente e integridad") {
  const auto dir = makeTempDir();
  {
    auto engine = Engine::open((dir / "negocio.db").string(), fastOptions());
    const auto owner = setupBusiness(*engine);
    const auto backupPath = (dir / "respaldo.db").string();
    call(*engine, "system.backup", Json{{"path", backupPath}}, owner);
    CHECK(call(*engine, "system.integrityCheck", Json::object(), owner)["ok"].get<bool>());

    auto copy = Engine::open(backupPath, fastOptions());
    CHECK(call(*copy, "business.status")["configured"].get<bool>());
  }
  std::filesystem::remove_all(dir);
}

TEST_CASE("una base existente conserva sus datos y no se migra dos veces") {
  const auto dir = makeTempDir();
  const auto path = (dir / "negocio.db").string();
  {
    auto engine = Engine::open(path, fastOptions());
    CHECK(engine->schemaVersion() >= 3);
    setupBusiness(*engine);
  }
  {
    auto engine = Engine::open(path, fastOptions());
    CHECK(call(*engine, "business.status")["configured"].get<bool>());
  }
  std::filesystem::remove_all(dir);
}

TEST_CASE("API en C") {
  char* error = nullptr;
  voxon_engine* engine = voxon_open_with_options(":memory:", R"({"pinIterations":1})", &error);
  REQUIRE(engine != nullptr);
  CHECK(error == nullptr);

  char* response = voxon_execute(engine, R"({"method":"business.status"})");
  REQUIRE(response != nullptr);
  CHECK(std::string(response).find(R"("configured":false)") != std::string::npos);
  voxon_free(response);
  voxon_close(engine);

  CHECK(voxon_open_with_options(":memory:", R"({"pinIterations":0})", &error) == nullptr);
  REQUIRE(error != nullptr);
  CHECK(std::string(error).find("validation_failed") != std::string::npos);
  voxon_free(error);
  CHECK(std::string(voxon_version()) == VOXON_VERSION);
}
