#include <doctest/doctest.h>

#include "support.hpp"

using namespace voxon;
using namespace voxon::testing;

namespace {

std::string product(Engine& engine, const std::string& owner, const Json& params) {
  return call(engine, "catalog.products.create", params, owner)["id"].get<std::string>();
}

}  // namespace

TEST_CASE("restaurante: mesa, comandas a cocina y bar, y cobro con propina legal") {
  auto engine = openEngine();
  const auto owner = setupBusiness(*engine, "restaurant");
  const auto waiter = createUser(*engine, owner, "Pedro", "waiter", "3333");
  const auto cook = createUser(*engine, owner, "Rosa", "kitchen", "4444");
  const auto cashier = createUser(*engine, owner, "Luis", "cashier", "2222");

  const auto mofongo = product(*engine, owner,
                               {{"name", "Mofongo"}, {"priceCents", 45000}, {"taxRate", "standard"},
                                {"station", "kitchen"}, {"trackStock", false}});
  const auto beer = product(*engine, owner,
                            {{"name", "Cerveza"}, {"priceCents", 20000}, {"taxRate", "standard"}, {"station", "bar"},
                             {"initialStockMilli", 24000}});
  const auto water = product(*engine, owner,
                             {{"name", "Agua"}, {"priceCents", 5000}, {"taxRate", "standard"},
                              {"initialStockMilli", 12000}});

  const auto area = call(*engine, "restaurant.areas.create", Json{{"name", "Terraza"}}, owner)["id"];
  const auto table =
      call(*engine, "restaurant.tables.create", Json{{"name", "Mesa 1"}, {"areaId", area}, {"seats", 4}}, owner)["id"]
          .get<std::string>();

  callError(*engine, "restaurant.orders.open", Json{{"kind", "dine_in"}}, waiter, "validation_failed");
  const auto order =
      call(*engine, "restaurant.orders.open", Json{{"kind", "dine_in"}, {"tableId", table}, {"guests", 2}}, waiter);
  const auto orderId = order["id"].get<std::string>();
  CHECK(order["number"] == 1);
  CHECK(order["waiterName"] == "Pedro");
  callError(*engine, "restaurant.orders.open", Json{{"kind", "dine_in"}, {"tableId", table}}, waiter, "conflict");
  CHECK(call(*engine, "restaurant.tables.list", Json::object(), waiter)[0]["orderNumber"] == 1);

  const auto added = call(*engine, "restaurant.orders.addItems",
                          Json{{"orderId", orderId},
                               {"items", Json::array({Json{{"productId", mofongo}, {"quantityMilli", 1000},
                                                           {"notes", "sin cebolla"}},
                                                      Json{{"productId", beer}, {"quantityMilli", 2000}},
                                                      Json{{"productId", water}, {"quantityMilli", 1000}}})}},
                          waiter);
  CHECK(added["items"].size() == 3);
  // Menú sin ITBIS: 900 de consumo + 10 % de propina + 18 % de ITBIS = 1,152.
  CHECK(added["estimate"]["totalCents"] == 115200);
  CHECK(added["estimate"]["tipCents"] == 9000);

  const auto sent = call(*engine, "restaurant.orders.send", Json{{"orderId", orderId}}, waiter);
  CHECK(sent["tickets"].size() == 2);
  callError(*engine, "restaurant.orders.send", Json{{"orderId", orderId}}, waiter, "conflict");

  const auto queue = call(*engine, "restaurant.kitchen.queue", Json{{"station", "kitchen"}}, cook);
  REQUIRE(queue.size() == 1);
  CHECK(queue[0]["productName"] == "Mofongo");
  CHECK(queue[0]["notes"] == "sin cebolla");
  CHECK(queue[0]["tableName"] == "Mesa 1");
  callError(*engine, "restaurant.kitchen.queue", Json::object(), cashier, "forbidden");

  const auto itemId = queue[0]["itemId"].get<std::string>();
  call(*engine, "restaurant.kitchen.updateItem", Json{{"itemId", itemId}, {"status", "ready"}}, cook);
  callError(*engine, "restaurant.kitchen.updateItem", Json{{"itemId", itemId}, {"status", "preparing"}}, cook,
            "conflict");

  const Json checkoutParams = {{"orderId", orderId}, {"payments", Json::array({Json{{"method", "cash"}, {"amountCents", 120000}}})}};
  callError(*engine, "restaurant.orders.checkout", checkoutParams, cashier, "cash_session_closed");
  call(*engine, "cash.open", Json{{"openingFloatCents", 0}}, cashier);
  const auto result = call(*engine, "restaurant.orders.checkout", checkoutParams, cashier);
  CHECK(result["sale"]["totalCents"] == 115200);
  CHECK(result["sale"]["tipCents"] == 9000);
  CHECK(result["sale"]["changeCents"] == 4800);
  CHECK(result["sale"]["orderId"] == orderId);
  CHECK(result["order"]["status"] == "closed");

  CHECK(call(*engine, "catalog.products.get", Json{{"id", beer}}, owner)["stockMilli"] == 22000);
  CHECK(call(*engine, "catalog.products.get", Json{{"id", water}}, owner)["stockMilli"] == 11000);
  CHECK(call(*engine, "restaurant.tables.list", Json::object(), waiter)[0]["orderId"].is_null());
  callError(*engine, "restaurant.orders.addItems",
            Json{{"orderId", orderId}, {"items", Json::array({Json{{"productId", water}, {"quantityMilli", 1000}}})}},
            waiter, "order_not_open");
}

TEST_CASE("restaurante: para llevar sin propina, cambios y cancelaciones") {
  auto engine = openEngine();
  const auto owner = setupBusiness(*engine, "restaurant");
  const auto waiter = createUser(*engine, owner, "Pedro", "waiter", "3333");
  const auto chicken = product(*engine, owner,
                               {{"name", "Pollo guisado"}, {"priceCents", 30000}, {"taxRate", "standard"},
                                {"station", "kitchen"}, {"trackStock", false}});

  const auto order =
      call(*engine, "restaurant.orders.open", Json{{"kind", "takeout"}, {"customerName", "María"}}, waiter);
  const auto orderId = order["id"].get<std::string>();
  const auto added = call(*engine, "restaurant.orders.addItems",
                          Json{{"orderId", orderId},
                               {"items", Json::array({Json{{"productId", chicken}, {"quantityMilli", 2000}}})}},
                          waiter);
  const auto itemId = added["items"][0]["id"].get<std::string>();

  const auto changed =
      call(*engine, "restaurant.orders.updateItem", Json{{"itemId", itemId}, {"quantityMilli", 1000}}, waiter);
  CHECK(changed["items"][0]["quantityMilli"] == 1000);
  // Para llevar no lleva propina legal: 300 + 18 % = 354.
  CHECK(changed["estimate"]["totalCents"] == 35400);
  CHECK(changed["estimate"]["tipCents"] == 0);

  call(*engine, "restaurant.orders.send", Json{{"orderId", orderId}}, waiter);
  callError(*engine, "restaurant.orders.updateItem", Json{{"itemId", itemId}, {"quantityMilli", 3000}}, waiter,
            "conflict");
  callError(*engine, "restaurant.orders.cancelItem", Json{{"itemId", itemId}}, waiter, "forbidden");
  const auto cancelled =
      call(*engine, "restaurant.orders.cancelItem", Json{{"itemId", itemId}, {"reason", "Se arrepintió"}}, owner);
  CHECK(cancelled["items"][0]["status"] == "cancelled");
  CHECK(cancelled["estimate"]["totalCents"] == 0);

  callError(*engine, "restaurant.orders.cancel", Json{{"orderId", orderId}, {"reason", "Se fue"}}, waiter, "forbidden");
  const auto closed = call(*engine, "restaurant.orders.cancel", Json{{"orderId", orderId}, {"reason", "Se fue"}}, owner);
  CHECK(closed["status"] == "cancelled");
  CHECK(call(*engine, "restaurant.orders.list", Json::object(), waiter).empty());
}
