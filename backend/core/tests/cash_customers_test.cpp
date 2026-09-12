#include <doctest/doctest.h>

#include "support.hpp"

using namespace voxon;
using namespace voxon::testing;

TEST_CASE("caja: abrir, entradas y salidas, y cierre con cuadre") {
  auto engine = openEngine();
  const auto owner = setupBusiness(*engine);
  const auto cashier = createUser(*engine, owner, "Luis", "cashier", "2222");

  CHECK(call(*engine, "cash.current", Json::object(), cashier).is_null());
  callError(*engine, "cash.movement", Json{{"kind", "cash_in"}, {"amountCents", 100}, {"reason", "Menudo"}}, cashier,
            "cash_session_closed");

  const auto session = call(*engine, "cash.open", Json{{"openingFloatCents", 100000}}, cashier);
  CHECK(session["openingFloatCents"] == 100000);
  CHECK(session["expectedCashCents"] == 100000);
  CHECK(session["openedByName"] == "Luis");
  callError(*engine, "cash.open", Json{{"openingFloatCents", 0}}, owner, "cash_session_already_open");

  call(*engine, "cash.movement", Json{{"kind", "cash_in"}, {"amountCents", 5000}, {"reason", "Menudo"}}, cashier);
  const auto afterOut =
      call(*engine, "cash.movement", Json{{"kind", "cash_out"}, {"amountCents", 3000}, {"reason", "Hielo"}}, cashier);
  CHECK(afterOut["movements"].size() == 2);
  callError(*engine, "cash.movement", Json{{"kind", "cash_out"}, {"amountCents", 0}, {"reason", "Nada"}}, cashier,
            "validation_failed");

  const auto closed = call(*engine, "cash.close", Json{{"countedCashCents", 101000}}, cashier);
  CHECK(closed["expectedCashCents"] == 102000);
  CHECK(closed["differenceCents"] == -1000);
  CHECK(closed["closedByName"] == "Luis");
  CHECK_FALSE(closed["closedAt"].is_null());

  CHECK(call(*engine, "cash.current", Json::object(), cashier).is_null());
  CHECK(call(*engine, "cash.sessions", Json::object(), owner).size() == 1);
  callError(*engine, "cash.sessions", Json::object(), cashier, "forbidden");
  callError(*engine, "cash.close", Json{{"countedCashCents", 0}}, cashier, "cash_session_closed");
}

TEST_CASE("fiao: el dueño autoriza el límite y un cliente sin deuda no abona") {
  auto engine = openEngine();
  const auto owner = setupBusiness(*engine);
  const auto cashier = createUser(*engine, owner, "Luis", "cashier", "2222");

  callError(*engine, "customers.create", Json{{"name", "Juan"}, {"creditLimitCents", 100000}}, cashier, "forbidden");
  const auto juan = call(*engine, "customers.create",
                         Json{{"name", "Juan Pérez"}, {"phone", "809-555-0000"}, {"creditLimitCents", 100000},
                              {"documentId", "001-0000000-1"}},
                         owner);
  CHECK(juan["availableCreditCents"] == 100000);
  CHECK(juan["documentId"] == "00100000001");

  const auto customerId = juan["id"].get<std::string>();
  CHECK(call(*engine, "customers.list", Json{{"search", "perez"}}, cashier).size() == 1);
  CHECK(call(*engine, "customers.list", Json{{"search", "555-0000"}}, cashier).size() == 1);

  // El cajero edita datos, pero no el límite.
  call(*engine, "customers.update", Json{{"id", customerId}, {"address", "Calle 1"}}, cashier);
  callError(*engine, "customers.update", Json{{"id", customerId}, {"creditLimitCents", 5}}, cashier, "forbidden");

  callError(*engine, "customers.payment",
            Json{{"customerId", customerId}, {"amountCents", 100}, {"method", "cash"}}, cashier,
            "cash_session_closed");
  call(*engine, "cash.open", Json{{"openingFloatCents", 0}}, cashier);
  callError(*engine, "customers.payment",
            Json{{"customerId", customerId}, {"amountCents", 100}, {"method", "cash"}}, cashier,
            "payment_exceeds_balance");

  const auto statement = call(*engine, "customers.statement", Json{{"id", customerId}}, cashier);
  CHECK(statement["entries"].empty());
  CHECK(statement["customer"]["address"] == "Calle 1");
}
