#include <doctest/doctest.h>

#include "support.hpp"

using namespace voxon;
using namespace voxon::testing;

namespace {

Json findBy(const Json& rows, const std::string& key, const std::string& value) {
  for (const auto& row : rows) {
    if (row[key] == value) {
      return row;
    }
  }
  return nullptr;
}

}  // namespace

TEST_CASE("reportes: tablero del día, ventas por producto, cajeros, fiao y bitácora") {
  auto engine = openEngine();
  const auto owner = setupBusiness(*engine);
  const auto cashier = createUser(*engine, owner, "Luis", "cashier", "2222");
  const auto manager = createUser(*engine, owner, "Marta", "manager", "3333");
  const auto soda = call(*engine, "catalog.products.create",
                         Json{{"name", "Refresco"}, {"priceCents", 5900}, {"taxRate", "standard"}, {"costCents", 4000},
                              {"initialStockMilli", 24000}},
                         owner)["id"]
                        .get<std::string>();
  const auto rice = call(*engine, "catalog.products.create",
                         Json{{"name", "Arroz"}, {"priceCents", 3500}, {"taxRate", "exempt"}, {"unit", "pound"},
                              {"costCents", 2500}, {"initialStockMilli", 50000}},
                         owner)["id"]
                        .get<std::string>();
  const auto juan =
      call(*engine, "customers.create", Json{{"name", "Juan"}, {"creditLimitCents", 50000}}, owner)["id"]
          .get<std::string>();
  call(*engine, "cash.open", Json{{"openingFloatCents", 100000}}, cashier);

  const auto sell = [&](const std::string& productId, std::int64_t quantity, const std::string& method,
                        std::int64_t amount, const std::string& customer = "") {
    Json params = {{"lines", Json::array({Json{{"productId", productId}, {"quantityMilli", quantity}}})},
                   {"payments", Json::array({Json{{"method", method}, {"amountCents", amount}}})}};
    if (!customer.empty()) {
      params["customerId"] = customer;
    }
    return call(*engine, "sales.complete", params, cashier);
  };
  sell(soda, 2000, "cash", 11800);
  sell(rice, 1000, "card", 3500);
  sell(soda, 1000, "credit", 5900, juan);
  const auto toVoid = sell(soda, 1000, "cash", 5900);
  call(*engine, "sales.void", Json{{"id", toVoid["id"]}, {"reason", "Cobro duplicado"}}, owner);

  const auto dashboard = call(*engine, "reports.dashboard", Json::object(), manager);
  CHECK(dashboard["sales"]["count"] == 3);
  CHECK(dashboard["sales"]["totalCents"] == 21200);
  CHECK(dashboard["sales"]["averageTicketCents"] == 7066);
  CHECK(dashboard["voidedSales"] == 1);
  CHECK(findBy(dashboard["payments"], "method", "cash")["amountCents"] == 11800);
  CHECK(findBy(dashboard["payments"], "method", "credit")["amountCents"] == 5900);
  CHECK(dashboard["topProducts"][0]["description"] == "Refresco");
  CHECK(dashboard["receivablesCents"] == 5900);
  CHECK(dashboard["openCashSession"]["expectedCashCents"] == 111800);
  CHECK(dashboard["openOrders"] == 0);
  callError(*engine, "reports.dashboard", Json::object(), cashier, "forbidden");

  const auto day = dashboard["day"].get<std::string>();
  const auto products = call(*engine, "reports.productSales", Json{{"from", day}, {"to", day}}, owner);
  const auto sodaRow = findBy(products, "description", "Refresco");
  CHECK(sodaRow["quantityMilli"] == 3000);
  CHECK(sodaRow["netCents"] == 17700);
  CHECK(sodaRow["costCents"] == 12000);
  CHECK(sodaRow["marginCents"] == 5700);
  callError(*engine, "reports.productSales", Json{{"from", day}}, owner, "validation_failed");
  callError(*engine, "reports.productSales", Json{{"from", day}, {"to", "2000-01-01"}}, owner, "validation_failed");

  const auto byDay = call(*engine, "reports.salesByDay", Json{{"from", day}, {"to", day}}, owner);
  CHECK(byDay["days"].size() == 1);
  CHECK(byDay["totals"]["totalCents"] == 21200);

  const auto cashiers = call(*engine, "reports.cashiers", Json{{"from", day}, {"to", day}}, owner);
  REQUIRE(cashiers.size() == 1);
  CHECK(cashiers[0]["cashierName"] == "Luis");
  CHECK(cashiers[0]["salesCount"] == 3);

  const auto receivables = call(*engine, "reports.receivables", Json::object(), cashier);
  CHECK(receivables["totalCents"] == 5900);
  CHECK(receivables["customers"][0]["name"] == "Juan");

  const auto audit = call(*engine, "reports.audit", Json{{"action", "sale.void"}}, owner);
  REQUIRE(audit.size() == 1);
  CHECK(audit[0]["details"]["reason"] == "Cobro duplicado");
  CHECK(audit[0]["userName"] == "Ana");
  callError(*engine, "reports.audit", Json::object(), manager, "forbidden");
}
