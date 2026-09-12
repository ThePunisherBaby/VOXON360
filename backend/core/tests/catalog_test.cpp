#include <doctest/doctest.h>

#include "support.hpp"

using namespace voxon;
using namespace voxon::testing;

TEST_CASE("catálogo: crear, buscar sin acentos y por código de barras") {
  auto engine = openEngine();
  const auto owner = setupBusiness(*engine);

  const auto drinks = call(*engine, "catalog.categories.create", Json{{"name", "Bebidas"}}, owner)["id"];
  callError(*engine, "catalog.categories.create", Json{{"name", "bebidas"}}, owner, "conflict");

  const auto coffee = call(*engine, "catalog.products.create",
                           Json{{"name", "Café Santo Domingo 1 lb"},
                                {"priceCents", 11600},
                                {"taxRate", "reduced"},
                                {"barcode", "7460001"},
                                {"categoryId", drinks}},
                           owner);
  CHECK(coffee["categoryName"] == "Bebidas");
  CHECK_FALSE(coffee["allowsFraction"].get<bool>());

  const auto rice = call(*engine, "catalog.products.create",
                         Json{{"name", "Arroz"},
                              {"priceCents", 3500},
                              {"taxRate", "exempt"},
                              {"unit", "pound"},
                              {"costCents", 2500},
                              {"initialStockMilli", 50000}},
                         owner);
  CHECK(rice["allowsFraction"].get<bool>());
  CHECK(rice["stockMilli"] == 50000);

  const auto found = call(*engine, "catalog.products.list", Json{{"search", "CAFE"}}, owner);
  REQUIRE(found.size() == 1);
  CHECK(found[0]["name"] == "Café Santo Domingo 1 lb");
  CHECK(call(*engine, "catalog.products.get", Json{{"barcode", "7460001"}}, owner)["id"] == coffee["id"]);

  callError(*engine, "catalog.products.create",
            Json{{"name", "Otro"}, {"priceCents", 100}, {"taxRate", "standard"}, {"barcode", "7460001"}}, owner,
            "conflict");
  callError(*engine, "catalog.products.get", Json{{"barcode", "000"}}, owner, "not_found");
  callError(*engine, "catalog.products.create", Json{{"name", "Sin precio"}, {"taxRate", "standard"}}, owner,
            "validation_failed");
}

TEST_CASE("catálogo: presentaciones al detalle") {
  auto engine = openEngine();
  const auto owner = setupBusiness(*engine);
  const auto cigarette = call(*engine, "catalog.products.create",
                              Json{{"name", "Cigarrillo"},
                                   {"priceCents", 1000},
                                   {"taxRate", "standard"},
                                   {"initialStockMilli", 40000}},
                              owner);
  const auto pack = call(*engine, "catalog.products.create",
                         Json{{"name", "Cajetilla"},
                              {"priceCents", 18000},
                              {"taxRate", "standard"},
                              {"stockSourceId", cigarette["id"]},
                              {"stockFactorMilli", 20000}},
                         owner);
  // 40 cigarrillos alcanzan para 2 cajetillas.
  CHECK(pack["availableMilli"] == 2000);

  callError(*engine, "catalog.products.create",
            Json{{"name", "Cartón"}, {"priceCents", 1}, {"taxRate", "standard"}, {"stockSourceId", pack["id"]}},
            owner, "validation_failed");
  callError(*engine, "catalog.products.create",
            Json{{"name", "Otra"},
                 {"priceCents", 1},
                 {"taxRate", "standard"},
                 {"stockSourceId", cigarette["id"]},
                 {"initialStockMilli", 1000}},
            owner, "validation_failed");
}

TEST_CASE("catálogo: solo dueño o gerente editan, y desactivar oculta el producto") {
  auto engine = openEngine();
  const auto owner = setupBusiness(*engine);
  const auto cashier = createUser(*engine, owner, "Luis", "cashier", "2222");
  const auto product = call(*engine, "catalog.products.create",
                            Json{{"name", "Refresco"}, {"priceCents", 5900}, {"taxRate", "standard"},
                                 {"barcode", "123"}},
                            owner);
  const auto id = product["id"].get<std::string>();

  callError(*engine, "catalog.products.update", Json{{"id", id}, {"priceCents", 6000}}, cashier, "forbidden");
  const auto updated =
      call(*engine, "catalog.products.update", Json{{"id", id}, {"priceCents", 6500}, {"barcode", nullptr}}, owner);
  CHECK(updated["priceCents"] == 6500);
  CHECK(updated["barcode"].is_null());
  CHECK(updated["name"] == "Refresco");

  call(*engine, "catalog.products.deactivate", Json{{"id", id}}, owner);
  CHECK(call(*engine, "catalog.products.list", Json::object(), cashier).empty());
  CHECK(call(*engine, "catalog.products.list", Json{{"includeInactive", true}}, owner).size() == 1);
}
