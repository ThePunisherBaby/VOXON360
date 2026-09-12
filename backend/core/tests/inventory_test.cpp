#include <doctest/doctest.h>

#include "support.hpp"

using namespace voxon;
using namespace voxon::testing;

TEST_CASE("inventario: compra con costo promedio, pago desde la caja y reporte 606") {
  auto engine = openEngine();
  const auto owner = setupBusiness(*engine);
  const auto cashier = createUser(*engine, owner, "Luis", "cashier", "2222");
  const auto rice = call(*engine, "catalog.products.create",
                         Json{{"name", "Arroz"}, {"priceCents", 3500}, {"taxRate", "exempt"}, {"unit", "pound"},
                              {"costCents", 2500}, {"initialStockMilli", 80000}},
                         owner)["id"]
                        .get<std::string>();
  const auto supplier = call(*engine, "inventory.suppliers.create",
                             Json{{"name", "Distribuidora Caribe"}, {"documentId", "101000001"}}, owner)["id"]
                            .get<std::string>();

  const Json purchase = {
      {"supplierId", supplier},
      {"ncf", "B0100000123"},
      {"invoiceDate", "2026-09-10"},
      {"paymentMethod", "cash"},
      {"items", Json::array({Json{{"productId", rice}, {"quantityMilli", 100000}, {"unitCostCents", 3000}}})}};
  callError(*engine, "inventory.purchases.create", purchase, owner, "cash_session_closed");
  call(*engine, "cash.open", Json{{"openingFloatCents", 500000}}, cashier);

  const auto created = call(*engine, "inventory.purchases.create", purchase, owner);
  CHECK(created["totalCents"] == 300000);
  CHECK(created["supplierName"] == "Distribuidora Caribe");
  CHECK(created["items"][0]["productName"] == "Arroz");

  // (80 lb × 25.00 + 100 lb × 30.00) / 180 lb = 27.78
  const auto product = call(*engine, "catalog.products.get", Json{{"id", rice}}, owner);
  CHECK(product["stockMilli"] == 180000);
  CHECK(product["costCents"] == 2778);
  CHECK(call(*engine, "cash.current", Json::object(), cashier)["expectedCashCents"] == 200000);

  callError(*engine, "inventory.purchases.create", purchase, owner, "conflict");
  callError(*engine, "inventory.purchases.create", purchase, cashier, "forbidden");

  const auto report = call(*engine, "fiscal.purchasesReport", Json{{"period", "2026-09"}}, owner);
  CHECK(report["purchases"].size() == 1);
  CHECK(report["totals"]["totalCents"] == 300000);
  CHECK(call(*engine, "inventory.purchases.list", Json{{"from", "2026-09-01"}}, owner).size() == 1);
}

TEST_CASE("inventario: mermas, conteo físico, movimientos y productos bajo mínimo") {
  auto engine = openEngine();
  const auto owner = setupBusiness(*engine);
  const auto cashier = createUser(*engine, owner, "Luis", "cashier", "2222");
  const auto soda = call(*engine, "catalog.products.create",
                         Json{{"name", "Refresco"}, {"priceCents", 5900}, {"taxRate", "standard"}, {"costCents", 4000},
                              {"initialStockMilli", 24000}},
                         owner)["id"]
                        .get<std::string>();
  const auto pack = call(*engine, "catalog.products.create",
                         Json{{"name", "Paquete"}, {"priceCents", 30000}, {"taxRate", "standard"},
                              {"stockSourceId", soda}, {"stockFactorMilli", 6000}},
                         owner)["id"]
                        .get<std::string>();

  callError(*engine, "inventory.adjust",
            Json{{"productId", soda}, {"quantityMilli", 1000}, {"kind", "waste"}, {"note", "Rotos"}}, owner,
            "validation_failed");
  const auto afterWaste = call(*engine, "inventory.adjust",
                               Json{{"productId", soda}, {"quantityMilli", -2000}, {"kind", "waste"},
                                    {"note", "Se rompieron 2"}},
                               owner);
  CHECK(afterWaste["stockMilli"] == 22000);

  const auto counted = call(*engine, "inventory.count", Json{{"productId", soda}, {"countedMilli", 21000}}, owner);
  CHECK(counted["previousMilli"] == 22000);
  CHECK(counted["differenceMilli"] == -1000);

  const auto history = call(*engine, "inventory.movements", Json{{"productId", soda}}, owner);
  REQUIRE(history.size() == 3);
  CHECK(history[0]["kind"] == "adjustment");
  CHECK(history[1]["kind"] == "waste");
  CHECK(history[0]["userName"] == "Ana");

  callError(*engine, "inventory.adjust",
            Json{{"productId", pack}, {"quantityMilli", -1000}, {"kind", "adjustment"}, {"note", "x"}}, owner,
            "validation_failed");
  callError(*engine, "inventory.adjust",
            Json{{"productId", soda}, {"quantityMilli", -1000}, {"kind", "adjustment"}, {"note", "x"}}, cashier,
            "forbidden");

  call(*engine, "catalog.products.update", Json{{"id", soda}, {"minStockMilli", 30000}}, owner);
  const auto low = call(*engine, "inventory.lowStock", Json::object(), cashier);
  REQUIRE(low.size() == 1);
  CHECK(low[0]["name"] == "Refresco");
}
