#include <doctest/doctest.h>

#include "support.hpp"

using namespace voxon;
using namespace voxon::testing;

TEST_CASE("nube: resumen del negocio para la app del dueño") {
  auto engine = openEngine();
  const auto owner = setupBusiness(*engine);
  const auto manager = createUser(*engine, owner, "Marta", "manager", "3333");
  const auto cashier = createUser(*engine, owner, "Luis", "cashier", "2222");
  const auto soda = call(*engine, "catalog.products.create",
                         Json{{"name", "Refresco"}, {"priceCents", 5900}, {"taxRate", "standard"}, {"costCents", 4000},
                              {"initialStockMilli", 6000}, {"minStockMilli", 5000}},
                         owner)["id"]
                        .get<std::string>();
  const auto juan =
      call(*engine, "customers.create", Json{{"name", "Juan"}, {"creditLimitCents", 50000}}, owner)["id"]
          .get<std::string>();
  call(*engine, "cash.open", Json{{"openingFloatCents", 100000}}, cashier);

  const auto sell = [&](std::int64_t quantity, const std::string& method, std::int64_t amount,
                        const std::string& customer = "") {
    Json params = {{"lines", Json::array({Json{{"productId", soda}, {"quantityMilli", quantity}}})},
                   {"payments", Json::array({Json{{"method", method}, {"amountCents", amount}}})}};
    if (!customer.empty()) {
      params["customerId"] = customer;
    }
    return call(*engine, "sales.complete", params, cashier);
  };
  sell(2000, "cash", 11800);
  sell(1000, "credit", 5900, juan);
  const auto toVoid = sell(1000, "card", 5900);
  call(*engine, "sales.void", Json{{"id", toVoid["id"]}, {"reason", "Tarjeta rechazada"}}, owner);

  const auto snapshot = call(*engine, "cloud.snapshot", Json::object(), owner);
  CHECK(snapshot["business"]["name"] == "Colmado La Esquina");
  CHECK(snapshot["business"]["businessType"] == "colmado");
  CHECK(snapshot["generatedAt"].get<std::string>().size() == 24);
  CHECK(snapshot["openCashSession"]["expectedCashCents"] == 111800);
  CHECK(snapshot["openCashSession"]["openedByName"] == "Luis");
  CHECK(snapshot["openOrders"] == 0);
  CHECK(snapshot["receivablesCents"] == 5900);

  // 6 - 2 - 1 - 1 + 1 (anulada) = 3 unidades, por debajo del mínimo de 5.
  CHECK(snapshot["lowStockCount"] == 1);
  REQUIRE(snapshot["lowStock"].size() == 1);
  CHECK(snapshot["lowStock"][0]["name"] == "Refresco");
  CHECK(snapshot["lowStock"][0]["stockMilli"] == 3000);
  REQUIRE(snapshot["receivables"].size() == 1);
  CHECK(snapshot["receivables"][0]["name"] == "Juan");
  CHECK(snapshot["receivables"][0]["balanceCents"] == 5900);
  REQUIRE(snapshot["cashSessions"].size() == 1);
  CHECK(snapshot["cashSessions"][0]["closedAt"].is_null());
  CHECK(snapshot["cashSessions"][0]["openedByName"] == "Luis");

  REQUIRE(snapshot["days"].size() == 2);
  const auto& today = snapshot["days"][0];
  const auto& yesterday = snapshot["days"][1];
  CHECK(today["day"].get<std::string>() > yesterday["day"].get<std::string>());
  CHECK(today["sales"]["count"] == 2);
  CHECK(today["sales"]["totalCents"] == 17700);
  CHECK(today["voided"]["count"] == 1);
  CHECK(today["voided"]["totalCents"] == 5900);
  CHECK(today["topProducts"][0]["description"] == "Refresco");
  CHECK(today["topProducts"][0]["quantityMilli"] == 3000);
  CHECK(today["cashiers"][0]["cashierName"] == "Luis");
  CHECK(today["cashiers"][0]["salesCount"] == 2);

  std::int64_t hourlyCount = 0;
  for (const auto& hour : today["hourly"]) {
    CHECK(hour["hour"].get<std::int64_t>() >= 0);
    CHECK(hour["hour"].get<std::int64_t>() <= 23);
    hourlyCount += hour["count"].get<std::int64_t>();
  }
  CHECK(hourlyCount == 2);

  REQUIRE(today["recentSales"].size() == 3);
  CHECK(today["recentSales"][0]["status"] == "voided");
  CHECK(today["recentSales"][0]["methods"] == "card");
  CHECK(today["recentSales"][1]["customerName"] == "Juan");
  CHECK(today["recentSales"][2]["cashierName"] == "Luis");
  CHECK(yesterday["sales"]["count"] == 0);
  CHECK(yesterday["recentSales"].empty());

  CHECK(call(*engine, "cloud.snapshot", Json{{"days", 7}}, owner)["days"].size() == 7);
  callError(*engine, "cloud.snapshot", Json{{"days", 0}}, owner, "validation_failed");
  callError(*engine, "cloud.snapshot", Json{{"days", 32}}, owner, "validation_failed");
  callError(*engine, "cloud.snapshot", Json::object(), manager, "forbidden");
  callError(*engine, "cloud.snapshot", Json::object(), cashier, "forbidden");
}
