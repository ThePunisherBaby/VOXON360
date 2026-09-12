// Restaurante: áreas, mesas, órdenes con comandas por estación, pantalla de
// cocina y cobro (que usa las mismas reglas de ventas).

#include <algorithm>
#include <map>
#include <string>
#include <vector>

#include "core/error.hpp"
#include "domain/money.hpp"
#include "services/common.hpp"
#include "services/sales.hpp"
#include "services/services.hpp"

namespace voxon::services {

namespace {

constexpr const char* kOrderHeader = R"SQL(
  SELECT o.id, o.number, o.kind, o.status, o.table_id, t.name AS table_name, o.waiter_id, u.name AS waiter_name,
         o.guests, o.customer_name, o.delivery_address, o.notes, o.opened_at, o.closed_at,
         (SELECT s.id FROM sales AS s WHERE s.order_id = o.id) AS sale_id
  FROM orders AS o
  JOIN users AS u ON u.id = o.waiter_id
  LEFT JOIN dining_tables AS t ON t.id = o.table_id
  WHERE o.id = ?1
)SQL";

bool isManager(const Actor& actor) { return actor.role == Role::Owner || actor.role == Role::Manager; }

// Cuenta estimada con las reglas del cobro: sin descuentos y con propina solo en el local.
Json estimate(db::Database& db, const std::string& kind, const Json& items) {
  std::vector<domain::SaleLineInput> lines;
  for (const auto& item : items) {
    if (item["status"] != "cancelled") {
      lines.push_back(domain::SaleLineInput{
          item["unitPriceCents"].get<std::int64_t>(), item["quantityMilli"].get<std::int64_t>(),
          domain::parseTaxRate(item["taxRate"].get<std::string>()).value_or(domain::TaxRate::Standard), {}});
    }
  }
  domain::SaleTotals totals;
  const auto business = queryOne(db, "SELECT price_mode, legal_tip_enabled FROM business_profile WHERE id = 1");
  if (business && !lines.empty()) {
    const bool tip = (*business)["legalTipEnabled"].get<bool>() && kind == "dine_in";
    totals = domain::calculateSale(
        lines, domain::parsePriceMode((*business)["priceMode"].get<std::string>()).value_or(domain::PriceMode::TaxExcluded),
        std::nullopt, tip ? domain::kLegalTipBasisPoints : 0);
  }
  Json result = Json::object();
  result["subtotalCents"] = totals.subtotal();
  result["taxCents"] = totals.tax();
  result["tipCents"] = totals.tip;
  result["totalCents"] = totals.total();
  return result;
}

Json orderDetail(db::Database& db, const std::string& id) {
  const auto bindId = [&](db::Statement& s) { s.bind(1, id); };
  auto order = requireOne(db, kOrderHeader, bindId, "La orden no existe");
  order["items"] = queryAll(db, R"SQL(
    SELECT i.id, i.product_id, p.name AS product_name, p.tax_rate, i.quantity_milli, i.unit_price_cents,
           (i.quantity_milli * i.unit_price_cents + 500) / 1000 AS gross_cents, i.notes, i.station, i.status,
           i.created_at, i.sent_at, i.ready_at, creator.name AS created_by_name
    FROM order_items AS i
    JOIN products AS p ON p.id = i.product_id
    JOIN users AS creator ON creator.id = i.created_by
    WHERE i.order_id = ?1
    ORDER BY i.created_at, i.rowid
  )SQL",
                            bindId);
  order["estimate"] = estimate(db, order["kind"].get<std::string>(), order["items"]);
  return order;
}

std::string requireOpenOrder(db::Database& db, const std::string& orderId) {
  const auto order = queryOne(db, "SELECT status, kind FROM orders WHERE id = ?1",
                              [&](db::Statement& s) { s.bind(1, orderId); });
  if (!order) {
    throw ApiError(errc::kNotFound, "La orden no existe");
  }
  if ((*order)["status"] != "open") {
    throw ApiError("order_not_open", "La orden ya está cerrada");
  }
  return (*order)["kind"].get<std::string>();
}

void requireFreeTable(db::Database& db, const std::string& tableId) {
  const auto active = queryInt(db, "SELECT count(*) FROM dining_tables WHERE id = ?1 AND active = 1",
                               [&](db::Statement& s) { s.bind(1, tableId); });
  if (active == 0) {
    throw ApiError(errc::kNotFound, "La mesa no existe o está desactivada");
  }
  const auto busy = queryInt(db, "SELECT count(*) FROM orders WHERE table_id = ?1 AND status = 'open'",
                             [&](db::Statement& s) { s.bind(1, tableId); });
  if (busy > 0) {
    throw ApiError(errc::kConflict, "La mesa ya tiene una orden abierta");
  }
}

// Envía a su estación lo pendiente; lo que no se prepara queda servido.
// Devuelve las comandas agrupadas por estación.
Json sendPending(Context& context, const std::string& orderId) {
  const auto pending = queryAll(context.db, R"SQL(
    SELECT i.id, i.station, p.name AS product_name, i.quantity_milli, i.notes
    FROM order_items AS i JOIN products AS p ON p.id = i.product_id
    WHERE i.order_id = ?1 AND i.status = 'pending'
    ORDER BY i.created_at, i.rowid
  )SQL",
                                [&](db::Statement& s) { s.bind(1, orderId); });
  execute(context.db,
          std::string("UPDATE order_items SET status = CASE WHEN station = 'none' THEN 'served' ELSE 'sent' END, "
                      "sent_at = ") +
              kNowSql + " WHERE order_id = ?1 AND status = 'pending'",
          [&](db::Statement& s) { s.bind(1, orderId); });

  std::map<std::string, Json> byStation;
  for (const auto& item : pending) {
    const auto station = item["station"].get<std::string>();
    if (station == "none") {
      continue;
    }
    if (!byStation.count(station)) {
      byStation[station] = Json::array();
    }
    byStation[station].push_back(item);
  }
  Json tickets = Json::array();
  for (auto& [station, items] : byStation) {
    Json ticket = Json::object();
    ticket["station"] = station;
    ticket["items"] = std::move(items);
    tickets.push_back(std::move(ticket));
  }
  return tickets;
}

// --- Áreas y mesas ------------------------------------------------------------

Json listAreas(Context& context) {
  return queryAll(context.db,
                  "SELECT id, name, sort_order, active FROM dining_areas WHERE active = 1 ORDER BY sort_order, name");
}

Json createArea(Context& context) {
  const auto id = newId();
  const auto name = context.params.requireString("name", 40);
  if (queryInt(context.db, "SELECT count(*) FROM dining_areas WHERE lower(name) = lower(?1)",
               [&](db::Statement& s) { s.bind(1, name); }) > 0) {
    throw ApiError(errc::kConflict, "Ya existe el área " + name);
  }
  execute(context.db, "INSERT INTO dining_areas (id, name, sort_order) VALUES (?1, ?2, ?3)", [&](db::Statement& s) {
    s.bind(1, id);
    s.bind(2, name);
    s.bind(3, context.params.intOr("sortOrder", 0));
  });
  audit(context, "area.create", "dining_area", id, Json{{"name", name}});
  return requireOne(context.db, "SELECT id, name, sort_order, active FROM dining_areas WHERE id = ?1",
                    [&](db::Statement& s) { s.bind(1, id); }, "El área no existe");
}

Json listTables(Context& context) {
  return queryAll(context.db, R"SQL(
    SELECT t.id, t.name, t.seats, t.area_id, a.name AS area_name,
           o.order_id, o.number AS order_number, o.waiter_name, o.item_count, o.gross_cents, o.opened_at
    FROM dining_tables AS t
    LEFT JOIN dining_areas AS a ON a.id = t.area_id
    LEFT JOIN v_open_orders AS o ON o.table_id = t.id
    WHERE t.active = 1
    ORDER BY a.sort_order, a.name, length(t.name), t.name
  )SQL");
}

Json tableById(db::Database& db, const std::string& id) {
  return requireOne(db, "SELECT id, name, seats, area_id, active FROM dining_tables WHERE id = ?1",
                    [&](db::Statement& s) { s.bind(1, id); }, "La mesa no existe");
}

void ensureTableNameFree(db::Database& db, const std::optional<std::string>& areaId, const std::string& name,
                         const std::string* excludeId) {
  const auto used = queryInt(db, "SELECT count(*) FROM dining_tables WHERE area_id IS ?1 AND name = ?2 AND id IS NOT ?3",
                             [&](db::Statement& s) {
                               s.bind(1, areaId);
                               s.bind(2, name);
                               if (excludeId != nullptr) {
                                 s.bind(3, *excludeId);
                               } else {
                                 s.bind(3, std::nullopt);
                               }
                             });
  if (used > 0) {
    throw ApiError(errc::kConflict, "Ya existe la mesa " + name + " en esa área");
  }
}

Json createTable(Context& context) {
  const auto& p = context.params;
  const auto id = newId();
  const auto name = p.requireString("name", 20);
  const auto areaId = p.optionalString("areaId", 36);
  if (areaId) {
    requireExists(context.db, "dining_areas", *areaId, "El área no existe");
  }
  ensureTableNameFree(context.db, areaId, name, nullptr);
  const auto seats = p.intOr("seats", 4);
  if (seats < 1) {
    invalidField("seats", "debe ser al menos 1");
  }
  execute(context.db, "INSERT INTO dining_tables (id, area_id, name, seats) VALUES (?1, ?2, ?3, ?4)",
          [&](db::Statement& s) {
            s.bind(1, id);
            s.bind(2, areaId);
            s.bind(3, name);
            s.bind(4, seats);
          });
  audit(context, "table.create", "dining_table", id, Json{{"name", name}});
  return tableById(context.db, id);
}

Json updateTable(Context& context) {
  const auto& p = context.params;
  const auto id = p.requireString("id", 36);
  const auto current = tableById(context.db, id);
  const auto name = p.has("name") ? p.requireString("name", 20) : current["name"].get<std::string>();
  auto areaId = current["areaId"].is_null() ? std::nullopt
                                            : std::optional<std::string>(current["areaId"].get<std::string>());
  if (p.contains("areaId")) {
    areaId = p.optionalString("areaId", 36);
    if (areaId) {
      requireExists(context.db, "dining_areas", *areaId, "El área no existe");
    }
  }
  const auto seats = p.intOr("seats", current["seats"].get<std::int64_t>());
  if (seats < 1) {
    invalidField("seats", "debe ser al menos 1");
  }
  const bool active = p.boolOr("active", current["active"].get<bool>());
  if (!active && queryInt(context.db, "SELECT count(*) FROM orders WHERE table_id = ?1 AND status = 'open'",
                          [&](db::Statement& s) { s.bind(1, id); }) > 0) {
    throw ApiError(errc::kConflict, "No se puede desactivar una mesa con orden abierta");
  }
  ensureTableNameFree(context.db, areaId, name, &id);
  execute(context.db, "UPDATE dining_tables SET name = ?1, area_id = ?2, seats = ?3, active = ?4 WHERE id = ?5",
          [&](db::Statement& s) {
            s.bind(1, name);
            s.bind(2, areaId);
            s.bind(3, seats);
            s.bind(4, active ? 1 : 0);
            s.bind(5, id);
          });
  audit(context, "table.update", "dining_table", id);
  return tableById(context.db, id);
}

// --- Órdenes ------------------------------------------------------------------

Json listOrders(Context& context) { return queryAll(context.db, "SELECT * FROM v_open_orders ORDER BY opened_at"); }

Json getOrder(Context& context) { return orderDetail(context.db, context.params.requireString("id", 36)); }

Json openOrder(Context& context) {
  const auto& actor = context.requireActor();
  const auto& p = context.params;
  const auto kind = p.requireEnum("kind", {"dine_in", "takeout", "delivery"});
  const auto tableId = p.optionalString("tableId", 36);
  if (kind == "dine_in" && !tableId) {
    invalidField("tableId", "es obligatorio para comer en el local");
  }
  if (tableId) {
    requireFreeTable(context.db, *tableId);
  }
  const auto guests = p.optionalInt("guests");
  if (guests && *guests < 1) {
    invalidField("guests", "debe ser al menos 1");
  }

  const auto id = newId();
  const auto number = nextCounter(context.db, "order");
  execute(context.db, R"SQL(
    INSERT INTO orders (id, number, kind, status, table_id, waiter_id, guests, customer_name, delivery_address, notes)
    VALUES (?1, ?2, ?3, 'open', ?4, ?5, ?6, ?7, ?8, ?9)
  )SQL",
          [&](db::Statement& s) {
            s.bind(1, id);
            s.bind(2, number);
            s.bind(3, kind);
            s.bind(4, tableId);
            s.bind(5, actor.id);
            s.bind(6, guests);
            s.bind(7, p.optionalString("customerName", 80));
            s.bind(8, p.optionalString("deliveryAddress", 200));
            s.bind(9, p.optionalString("notes", 200));
          });
  audit(context, "order.open", "order", id, Json{{"number", number}, {"kind", kind}});
  return orderDetail(context.db, id);
}

Json addItems(Context& context) {
  const auto& actor = context.requireActor();
  const auto orderId = context.params.requireString("orderId", 36);
  requireOpenOrder(context.db, orderId);
  const auto& items = context.params.requireArray("items");
  for (std::size_t i = 0; i < items.size(); ++i) {
    const std::string prefix = "items[" + std::to_string(i) + "]";
    if (!items[i].is_object()) {
      invalidField(prefix, "debe ser un objeto");
    }
    const Params item(items[i], prefix);
    const auto productId = item.requireString("productId", 36);
    const auto quantity = item.requireIntAtLeast("quantityMilli", 1);
    auto product =
        context.db.prepare("SELECT name, price_cents, allows_fraction, station FROM products WHERE id = ?1 AND active = 1");
    product.bind(1, productId);
    if (!product.step()) {
      throw ApiError(errc::kNotFound, "El producto de " + prefix + " no existe o está desactivado");
    }
    if (product.getInt(2) == 0 && quantity % 1000 != 0) {
      invalidField(item.field("quantityMilli"), "debe ser entero: " + product.getText(0) + " se vende por unidades");
    }
    const auto price = product.getInt(1);
    const auto station = product.getText(3);
    execute(context.db, R"SQL(
      INSERT INTO order_items (id, order_id, product_id, quantity_milli, unit_price_cents, notes, station, created_by)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
    )SQL",
            [&](db::Statement& s) {
              s.bind(1, newId());
              s.bind(2, orderId);
              s.bind(3, productId);
              s.bind(4, quantity);
              s.bind(5, price);
              s.bind(6, item.optionalString("notes", 120));
              s.bind(7, station);
              s.bind(8, actor.id);
            });
  }
  audit(context, "order.addItems", "order", orderId, Json{{"count", items.size()}});
  return orderDetail(context.db, orderId);
}

Json itemRow(db::Database& db, const std::string& itemId) {
  return requireOne(db, "SELECT id, order_id, status, notes, quantity_milli FROM order_items WHERE id = ?1",
                    [&](db::Statement& s) { s.bind(1, itemId); }, "El producto de la orden no existe");
}

// Solo lo que aún no se ha enviado a cocina se puede cambiar.
Json updateItem(Context& context) {
  const auto& p = context.params;
  const auto itemId = p.requireString("itemId", 36);
  const auto item = itemRow(context.db, itemId);
  const auto orderId = item["orderId"].get<std::string>();
  requireOpenOrder(context.db, orderId);
  if (item["status"] != "pending") {
    throw ApiError(errc::kConflict, "Ya se envió a preparación; cancélalo y agrega uno nuevo");
  }
  const auto quantity = p.has("quantityMilli") ? p.requireIntAtLeast("quantityMilli", 1)
                                                : item["quantityMilli"].get<std::int64_t>();
  auto notes = item["notes"].is_null() ? std::nullopt : std::optional<std::string>(item["notes"].get<std::string>());
  if (p.contains("notes")) {
    notes = p.optionalString("notes", 120);
  }
  execute(context.db, "UPDATE order_items SET quantity_milli = ?1, notes = ?2 WHERE id = ?3", [&](db::Statement& s) {
    s.bind(1, quantity);
    s.bind(2, notes);
    s.bind(3, itemId);
  });
  return orderDetail(context.db, orderId);
}

Json cancelItem(Context& context) {
  const auto& actor = context.requireActor();
  const auto itemId = context.params.requireString("itemId", 36);
  const auto item = itemRow(context.db, itemId);
  const auto status = item["status"].get<std::string>();
  if (status == "cancelled" || status == "served") {
    throw ApiError(errc::kConflict, "Ese producto ya está " + std::string(status == "served" ? "servido" : "cancelado"));
  }
  if (status != "pending" && !isManager(actor)) {
    throw ApiError(errc::kForbidden, "Solo el dueño o un gerente pueden cancelar lo que ya se envió a preparación");
  }
  execute(context.db, "UPDATE order_items SET status = 'cancelled' WHERE id = ?1",
          [&](db::Statement& s) { s.bind(1, itemId); });
  const auto orderId = item["orderId"].get<std::string>();
  audit(context, "order.cancelItem", "order", orderId,
        Json{{"itemId", itemId}, {"previousStatus", status},
             {"reason", context.params.optionalString("reason", 200).value_or("")}});
  return orderDetail(context.db, orderId);
}

Json sendOrder(Context& context) {
  const auto orderId = context.params.requireString("orderId", 36);
  requireOpenOrder(context.db, orderId);
  const auto pendingCount = queryInt(context.db,
                                     "SELECT count(*) FROM order_items WHERE order_id = ?1 AND status = 'pending'",
                                     [&](db::Statement& s) { s.bind(1, orderId); });
  if (pendingCount == 0) {
    throw ApiError(errc::kConflict, "No hay productos nuevos para enviar");
  }
  auto tickets = sendPending(context, orderId);
  audit(context, "order.send", "order", orderId, Json{{"count", pendingCount}});
  Json result = Json::object();
  result["order"] = orderDetail(context.db, orderId);
  result["tickets"] = std::move(tickets);
  return result;
}

Json moveTable(Context& context) {
  const auto orderId = context.params.requireString("orderId", 36);
  const auto tableId = context.params.requireString("tableId", 36);
  if (requireOpenOrder(context.db, orderId) != "dine_in") {
    throw ApiError(errc::kConflict, "Solo las órdenes en el local tienen mesa");
  }
  requireFreeTable(context.db, tableId);
  execute(context.db, "UPDATE orders SET table_id = ?1 WHERE id = ?2", [&](db::Statement& s) {
    s.bind(1, tableId);
    s.bind(2, orderId);
  });
  audit(context, "order.moveTable", "order", orderId, Json{{"tableId", tableId}});
  return orderDetail(context.db, orderId);
}

Json cancelOrder(Context& context) {
  const auto orderId = context.params.requireString("orderId", 36);
  const auto reason = context.params.requireString("reason", 200);
  requireOpenOrder(context.db, orderId);
  execute(context.db,
          "UPDATE order_items SET status = 'cancelled' WHERE order_id = ?1 AND status IN ('pending', 'sent', 'preparing', 'ready')",
          [&](db::Statement& s) { s.bind(1, orderId); });
  execute(context.db,
          std::string("UPDATE orders SET status = 'cancelled', closed_at = ") + kNowSql +
              ", notes = trim(coalesce(notes || ' · ', '') || 'Cancelada: ' || ?1) WHERE id = ?2",
          [&](db::Statement& s) {
            s.bind(1, reason);
            s.bind(2, orderId);
          });
  audit(context, "order.cancel", "order", orderId, Json{{"reason", reason}});
  return orderDetail(context.db, orderId);
}

// Cobra la orden con las reglas de ventas (precios vigentes del catálogo) y la cierra.
Json checkout(Context& context) {
  const auto& p = context.params;
  const auto orderId = p.requireString("orderId", 36);
  const auto kind = requireOpenOrder(context.db, orderId);
  const auto items = queryAll(context.db, R"SQL(
    SELECT product_id, quantity_milli FROM order_items
    WHERE order_id = ?1 AND status <> 'cancelled'
    ORDER BY created_at, rowid
  )SQL",
                              [&](db::Statement& s) { s.bind(1, orderId); });
  if (items.empty()) {
    throw ApiError(errc::kConflict, "La orden no tiene productos para cobrar");
  }

  Json sale = Json::object();
  sale["lines"] = Json::array();
  for (const auto& item : items) {
    sale["lines"].push_back(Json{{"productId", item["productId"]}, {"quantityMilli", item["quantityMilli"]}});
  }
  sale["payments"] = p.requireArray("payments", /*allowEmpty=*/true);
  if (const auto customerId = p.optionalString("customerId", 36)) {
    sale["customerId"] = *customerId;
  }
  const auto fiscal = p.object("fiscal");
  if (const auto documentType = fiscal.optionalString("documentType", 3)) {
    sale["fiscal"] = Json{{"documentType", *documentType}};
    if (const auto buyer = fiscal.optionalString("buyerDocumentId", 20)) {
      sale["fiscal"]["buyerDocumentId"] = *buyer;
    }
  }
  if (p.has("orderDiscount")) {
    const auto discount = p.object("orderDiscount");
    sale["orderDiscount"] = Json{{"kind", discount.requireEnum("kind", {"amount", "percent"})},
                                 {"value", discount.requireIntAtLeast("value", 0)}};
  }
  const auto legalTip = queryInt(context.db, "SELECT legal_tip_enabled FROM business_profile WHERE id = 1");
  sale["applyLegalTip"] = p.boolOr("applyLegalTip", legalTip == 1 && kind == "dine_in");

  const Params saleParams(sale);
  auto receipt = completeSale(context, saleParams, orderId);

  // Lo que nunca se envió sale ahora hacia su estación antes de cerrar.
  sendPending(context, orderId);
  execute(context.db, std::string("UPDATE orders SET status = 'closed', closed_at = ") + kNowSql + " WHERE id = ?1",
          [&](db::Statement& s) { s.bind(1, orderId); });
  audit(context, "order.checkout", "order", orderId, Json{{"saleId", receipt["id"]}});

  Json result = Json::object();
  result["order"] = orderDetail(context.db, orderId);
  result["sale"] = std::move(receipt);
  return result;
}

// --- Cocina -------------------------------------------------------------------

Json kitchenQueue(Context& context) {
  const auto station = context.params.optionalEnum("station", {"kitchen", "bar"});
  std::string sql = "SELECT * FROM v_kitchen_queue";
  if (station) {
    sql += " WHERE station = ?1";
  }
  sql += " ORDER BY sent_at, order_number";
  return queryAll(context.db, sql, [&](db::Statement& s) {
    if (station) s.bind(1, *station);
  });
}

// Los estados solo avanzan: enviado → preparando → listo → servido.
Json kitchenUpdate(Context& context) {
  const auto itemId = context.params.requireString("itemId", 36);
  const auto next = context.params.requireEnum("status", {"preparing", "ready", "served"});
  const auto item = itemRow(context.db, itemId);
  const auto current = item["status"].get<std::string>();
  const auto rank = [](const std::string& status) {
    if (status == "sent") return 1;
    if (status == "preparing") return 2;
    if (status == "ready") return 3;
    if (status == "served") return 4;
    return 0;
  };
  if (rank(current) == 0 || rank(next) <= rank(current)) {
    throw ApiError(errc::kConflict, "No se puede pasar de '" + current + "' a '" + next + "'");
  }
  execute(context.db,
          std::string("UPDATE order_items SET status = ?1, ready_at = CASE WHEN ?1 = 'ready' THEN ") + kNowSql +
              " ELSE ready_at END WHERE id = ?2",
          [&](db::Statement& s) {
            s.bind(1, next);
            s.bind(2, itemId);
          });
  return itemRow(context.db, itemId);
}

}  // namespace

void registerRestaurant(Registry& registry) {
  registry.add("restaurant.areas.list", {listAreas, true, {}, false});
  registry.add("restaurant.areas.create", {createArea, true, roles::kManagers, true});
  registry.add("restaurant.tables.list", {listTables, true, {}, false});
  registry.add("restaurant.tables.create", {createTable, true, roles::kManagers, true});
  registry.add("restaurant.tables.update", {updateTable, true, roles::kManagers, true});
  registry.add("restaurant.orders.list", {listOrders, true, {}, false});
  registry.add("restaurant.orders.get", {getOrder, true, {}, false});
  registry.add("restaurant.orders.open", {openOrder, true, roles::kFloor, true});
  registry.add("restaurant.orders.addItems", {addItems, true, roles::kFloor, true});
  registry.add("restaurant.orders.updateItem", {updateItem, true, roles::kFloor, true});
  registry.add("restaurant.orders.cancelItem", {cancelItem, true, roles::kFloor, true});
  registry.add("restaurant.orders.send", {sendOrder, true, roles::kFloor, true});
  registry.add("restaurant.orders.moveTable", {moveTable, true, roles::kFloor, true});
  registry.add("restaurant.orders.cancel", {cancelOrder, true, roles::kManagers, true});
  registry.add("restaurant.orders.checkout", {checkout, true, roles::kCash, true});
  registry.add("restaurant.kitchen.queue", {kitchenQueue, true, roles::kKitchen, false});
  registry.add("restaurant.kitchen.updateItem", {kitchenUpdate, true, roles::kKitchen, true});
}

}  // namespace voxon::services
