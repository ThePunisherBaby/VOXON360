#include <doctest/doctest.h>

#include "support.hpp"

using namespace voxon;
using namespace voxon::testing;

namespace {

struct Shop {
  std::unique_ptr<Engine> engine;
  std::string owner;
  std::string cashier;
  std::string rice;
  std::string soda;
  std::string cigarette;
  std::string pack;
};

// Colmado con arroz por libra, refrescos, cigarrillos sueltos y cajetillas, y la caja abierta con RD$1,000.
Shop openShop() {
  Shop shop;
  shop.engine = openEngine();
  auto& engine = *shop.engine;
  shop.owner = setupBusiness(engine);
  shop.cashier = createUser(engine, shop.owner, "Luis", "cashier", "2222");
  const auto product = [&](const Json& params) {
    return call(engine, "catalog.products.create", params, shop.owner)["id"].get<std::string>();
  };
  shop.rice = product({{"name", "Arroz"}, {"priceCents", 3500}, {"taxRate", "exempt"}, {"unit", "pound"},
                       {"costCents", 2500}, {"initialStockMilli", 50000}});
  shop.soda = product({{"name", "Refresco"}, {"priceCents", 5900}, {"taxRate", "standard"}, {"costCents", 4000},
                       {"initialStockMilli", 24000}});
  shop.cigarette = product({{"name", "Cigarrillo"}, {"priceCents", 1000}, {"taxRate", "standard"},
                            {"costCents", 600}, {"initialStockMilli", 40000}});
  shop.pack = product({{"name", "Cajetilla"}, {"priceCents", 18000}, {"taxRate", "standard"},
                       {"stockSourceId", shop.cigarette}, {"stockFactorMilli", 20000}});
  call(engine, "cash.open", Json{{"openingFloatCents", 100000}}, shop.cashier);
  return shop;
}

Json line(const std::string& productId, std::int64_t quantityMilli) {
  return Json{{"productId", productId}, {"quantityMilli", quantityMilli}};
}

Json pay(const std::string& method, std::int64_t cents) { return Json{{"method", method}, {"amountCents", cents}}; }

Json saleParams(Json lines, Json payments) { return Json{{"lines", std::move(lines)}, {"payments", std::move(payments)}}; }

std::int64_t stockOf(Engine& engine, const std::string& actor, const std::string& productId) {
  return call(engine, "catalog.products.get", Json{{"id", productId}}, actor)["stockMilli"].get<std::int64_t>();
}

}  // namespace

TEST_CASE("ventas: cotizar calcula los totales sin guardar nada") {
  auto shop = openShop();
  auto& engine = *shop.engine;
  const auto quote = call(engine, "sales.quote",
                          Json{{"lines", Json::array({line(shop.rice, 500), line(shop.soda, 2000)})}}, shop.cashier);
  CHECK(quote["totalCents"] == 13550);
  CHECK(quote["taxCents"] == 1800);
  CHECK(quote["lines"][0]["netCents"] == 1750);
  CHECK(call(engine, "sales.list", Json::object(), shop.owner).empty());
}

TEST_CASE("ventas: cobro en efectivo con vuelto, inventario y cuadre de caja") {
  auto shop = openShop();
  auto& engine = *shop.engine;
  const auto sale = call(engine, "sales.complete",
                         saleParams(Json::array({line(shop.pack, 1000), line(shop.rice, 500)}),
                                    Json::array({pay("cash", 20000)})),
                         shop.cashier);
  CHECK(sale["number"] == 1);
  CHECK(sale["totalCents"] == 19750);
  CHECK(sale["taxCents"] == 2746);
  CHECK(sale["changeCents"] == 250);
  CHECK(sale["cashierName"] == "Luis");
  CHECK(sale["items"].size() == 2);
  CHECK(sale["taxGroups"].size() == 2);
  CHECK(sale["business"]["name"] == "Colmado La Esquina");

  // La cajetilla descuenta 20 cigarrillos; media libra de arroz, 500 milésimas.
  CHECK(stockOf(engine, shop.owner, shop.cigarette) == 20000);
  CHECK(stockOf(engine, shop.owner, shop.rice) == 49500);
  CHECK(call(engine, "cash.current", Json::object(), shop.cashier)["expectedCashCents"] == 119750);

  const auto second =
      call(engine, "sales.complete", saleParams(Json::array({line(shop.soda, 1000)}), Json::array({pay("card", 5900)})),
           shop.cashier);
  CHECK(second["number"] == 2);
  CHECK(call(engine, "sales.get", Json{{"id", sale["id"]}}, shop.cashier)["ncf"].is_null());
}

TEST_CASE("ventas: validaciones del cobro") {
  auto shop = openShop();
  auto& engine = *shop.engine;
  callError(engine, "sales.complete",
            saleParams(Json::array({line(shop.soda, 1000)}), Json::array({pay("cash", 5000)})), shop.cashier,
            "insufficient_payment");
  callError(engine, "sales.complete",
            saleParams(Json::array({line(shop.soda, 500)}), Json::array({pay("cash", 5000)})), shop.cashier,
            "validation_failed");
  callError(engine, "sales.complete",
            saleParams(Json::array({Json{{"productId", shop.soda}, {"quantityMilli", 1000}, {"unitPriceCents", 1}}}),
                       Json::array({pay("cash", 100)})),
            shop.cashier, "forbidden");
  callError(engine, "sales.complete",
            saleParams(Json::array({line(shop.soda, 1000)}), Json::array({pay("credit", 5900)})), shop.cashier,
            "validation_failed");
  callError(engine, "sales.complete", saleParams(Json::array(), Json::array({pay("cash", 100)})), shop.cashier,
            "validation_failed");
  CHECK(call(engine, "sales.list", Json::object(), shop.owner).empty());
}

TEST_CASE("ventas: artículo libre, descuento general y pago mixto") {
  auto shop = openShop();
  auto& engine = *shop.engine;
  const auto sale = call(
      engine, "sales.complete",
      Json{{"lines", Json::array({Json{{"description", "Varios"}, {"unitPriceCents", 10000}, {"taxRate", "standard"},
                                       {"quantityMilli", 1000}},
                                  line(shop.rice, 1000)})},
           {"orderDiscount", {{"kind", "amount"}, {"value", 1500}}},
           {"payments", Json::array({pay("card", 10000), pay("cash", 5000)})}},
      shop.cashier);
  CHECK(sale["totalCents"] == 12000);
  CHECK(sale["discountCents"] == 1500);
  CHECK(sale["changeCents"] == 3000);
  CHECK(sale["payments"].size() == 2);
  CHECK(sale["items"][0]["productId"].is_null());
}

TEST_CASE("ventas: fiao con límite, y anular revierte deuda e inventario") {
  auto shop = openShop();
  auto& engine = *shop.engine;
  const auto juan =
      call(engine, "customers.create", Json{{"name", "Juan"}, {"creditLimitCents", 20000}}, shop.owner)["id"]
          .get<std::string>();

  auto fiado = saleParams(Json::array({line(shop.soda, 2000)}), Json::array({pay("credit", 11800)}));
  fiado["customerId"] = juan;
  const auto sale = call(engine, "sales.complete", fiado, shop.cashier);
  CHECK(call(engine, "customers.get", Json{{"id", juan}}, shop.cashier)["balanceCents"] == 11800);
  CHECK(stockOf(engine, shop.owner, shop.soda) == 22000);
  callError(engine, "sales.complete", fiado, shop.cashier, "credit_limit_exceeded");

  callError(engine, "sales.void", Json{{"id", sale["id"]}, {"reason", "Error"}}, shop.cashier, "forbidden");
  const auto voided = call(engine, "sales.void", Json{{"id", sale["id"]}, {"reason", "Otro cliente"}}, shop.owner);
  CHECK(voided["status"] == "voided");
  CHECK(voided["voidedByName"] == "Ana");
  CHECK(call(engine, "customers.get", Json{{"id", juan}}, shop.cashier)["balanceCents"] == 0);
  CHECK(stockOf(engine, shop.owner, shop.soda) == 24000);
  CHECK(call(engine, "customers.statement", Json{{"id", juan}}, shop.cashier)["entries"].size() == 2);
  callError(engine, "sales.void", Json{{"id", sale["id"]}, {"reason", "Otra vez"}}, shop.owner, "conflict");

  // Un abono en efectivo entra a la caja.
  call(engine, "sales.complete", fiado, shop.cashier);
  call(engine, "customers.payment", Json{{"customerId", juan}, {"amountCents", 1800}, {"method", "cash"}},
       shop.cashier);
  CHECK(call(engine, "customers.get", Json{{"id", juan}}, shop.cashier)["balanceCents"] == 10000);
  CHECK(call(engine, "cash.current", Json::object(), shop.cashier)["expectedCashCents"] == 101800);
}

TEST_CASE("ventas: comprobantes fiscales numerados localmente") {
  auto shop = openShop();
  auto& engine = *shop.engine;
  auto withFiscal = [&](const std::string& type, const Json& buyer = nullptr) {
    auto params = saleParams(Json::array({line(shop.soda, 1000)}), Json::array({pay("cash", 5900)}));
    params["fiscal"] = Json{{"documentType", type}};
    if (!buyer.is_null()) {
      params["fiscal"]["buyerDocumentId"] = buyer;
    }
    return params;
  };

  callError(engine, "sales.complete", withFiscal("B02"), shop.cashier, "fiscal_sequence_exhausted");
  callError(engine, "fiscal.sequences.add", Json{{"documentType", "B02"}, {"rangeFrom", 1}, {"rangeTo", 2}},
            shop.cashier, "forbidden");
  call(engine, "fiscal.sequences.add", Json{{"documentType", "B02"}, {"rangeFrom", 1}, {"rangeTo", 2}}, shop.owner);
  callError(engine, "fiscal.sequences.add", Json{{"documentType", "B02"}, {"rangeFrom", 2}, {"rangeTo", 5}},
            shop.owner, "conflict");

  CHECK(call(engine, "sales.complete", withFiscal("B02"), shop.cashier)["ncf"] == "B0200000001");
  CHECK(call(engine, "sales.complete", withFiscal("B02"), shop.cashier)["ncf"] == "B0200000002");
  callError(engine, "sales.complete", withFiscal("B02"), shop.cashier, "fiscal_sequence_exhausted");
  CHECK(call(engine, "sales.list", Json::object(), shop.owner).size() == 2);

  call(engine, "fiscal.sequences.add", Json{{"documentType", "B01"}, {"rangeFrom", 1}, {"rangeTo", 10}}, shop.owner);
  callError(engine, "sales.complete", withFiscal("B01"), shop.cashier, "validation_failed");
  const auto creditFiscal = call(engine, "sales.complete", withFiscal("B01", "101-00000-1"), shop.cashier);
  CHECK(creditFiscal["ncf"] == "B0100000001");
  CHECK(creditFiscal["buyerDocumentId"] == "101000001");

  call(engine, "fiscal.sequences.add", Json{{"documentType", "E32"}, {"rangeFrom", 1}, {"rangeTo", 10}}, shop.owner);
  CHECK(call(engine, "sales.complete", withFiscal("E32"), shop.cashier)["ncf"] == "E320000000001");
  CHECK(call(engine, "fiscal.sequences.list", Json::object(), shop.owner).size() == 3);
  callError(engine, "fiscal.salesReport", Json{{"period", "2026-13"}}, shop.owner, "validation_failed");
}

TEST_CASE("ventas: el cajero solo ve su caja y no se anula con la caja cerrada") {
  auto shop = openShop();
  auto& engine = *shop.engine;
  const auto sale =
      call(engine, "sales.complete", saleParams(Json::array({line(shop.soda, 1000)}), Json::array({pay("cash", 5900)})),
           shop.cashier);
  CHECK(call(engine, "sales.list", Json::object(), shop.cashier).size() == 1);

  call(engine, "cash.close", Json{{"countedCashCents", 105900}}, shop.cashier);
  CHECK(call(engine, "sales.list", Json::object(), shop.cashier).empty());
  CHECK(call(engine, "sales.list", Json::object(), shop.owner).size() == 1);
  callError(engine, "sales.list", Json{{"from", "2026-02-3x"}}, shop.owner, "validation_failed");
  callError(engine, "sales.void", Json{{"id", sale["id"]}, {"reason", "Tarde"}}, shop.owner, "cash_session_closed");
}
