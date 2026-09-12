// Inventario: suplidores, compras (existencia, costo promedio y 606), mermas,
// conteo físico y movimientos. La existencia la actualizan los triggers SQL.

#include <algorithm>
#include <string>
#include <vector>

#include "core/error.hpp"
#include "domain/money.hpp"
#include "services/common.hpp"
#include "services/services.hpp"

namespace voxon::services {

namespace {

constexpr const char* kSelectSupplier =
    "SELECT id, name, document_id, phone, active, created_at FROM suppliers WHERE id = ?1";

Json supplierById(db::Database& db, const std::string& id) {
  return requireOne(db, kSelectSupplier, [&](db::Statement& s) { s.bind(1, id); }, "El suplidor no existe");
}

std::optional<std::string> validDate(const Params& params, const char* key) {
  auto value = params.optionalString(key, 10);
  if (value && !isIsoDate(*value)) {
    invalidField(params.field(key), "debe tener el formato AAAA-MM-DD");
  }
  return value;
}

// --- Suplidores ---------------------------------------------------------------

Json listSuppliers(Context& context) {
  const auto& p = context.params;
  const auto search = p.optionalString("search", 80);
  std::string sql = "SELECT id, name, document_id, phone, active, created_at FROM suppliers WHERE 1 = 1";
  if (!p.boolOr("includeInactive", false)) {
    sql += " AND active = 1";
  }
  if (search) {
    sql += " AND (name LIKE ?1 ESCAPE '\\' OR document_id = ?2)";
  }
  sql += " ORDER BY name COLLATE NOCASE";
  return queryAll(context.db, sql, [&](db::Statement& s) {
    if (search) {
      s.bind(1, likePattern(*search));
      s.bind(2, *search);
    }
  });
}

Json createSupplier(Context& context) {
  const auto& p = context.params;
  const auto id = newId();
  const auto name = p.requireString("name", 80);
  execute(context.db, "INSERT INTO suppliers (id, name, document_id, phone) VALUES (?1, ?2, ?3, ?4)",
          [&](db::Statement& s) {
            s.bind(1, id);
            s.bind(2, name);
            s.bind(3, optionalDocumentId(p, "documentId"));
            s.bind(4, p.optionalString("phone", 30));
          });
  audit(context, "supplier.create", "supplier", id, Json{{"name", name}});
  return supplierById(context.db, id);
}

Json updateSupplier(Context& context) {
  const auto& p = context.params;
  const auto id = p.requireString("id", 36);
  const auto current = supplierById(context.db, id);
  const auto name = p.has("name") ? p.requireString("name", 80) : current["name"].get<std::string>();
  auto documentId = current["documentId"].is_null() ? std::nullopt
                                                     : std::optional<std::string>(current["documentId"].get<std::string>());
  if (p.contains("documentId")) {
    documentId = optionalDocumentId(p, "documentId");
  }
  auto phone = current["phone"].is_null() ? std::nullopt
                                          : std::optional<std::string>(current["phone"].get<std::string>());
  if (p.contains("phone")) {
    phone = p.optionalString("phone", 30);
  }
  execute(context.db, "UPDATE suppliers SET name = ?1, document_id = ?2, phone = ?3, active = ?4 WHERE id = ?5",
          [&](db::Statement& s) {
            s.bind(1, name);
            s.bind(2, documentId);
            s.bind(3, phone);
            s.bind(4, p.boolOr("active", current["active"].get<bool>()) ? 1 : 0);
            s.bind(5, id);
          });
  audit(context, "supplier.update", "supplier", id);
  return supplierById(context.db, id);
}

// --- Compras ------------------------------------------------------------------

Json purchaseDetail(db::Database& db, const std::string& id) {
  const auto bindId = [&](db::Statement& s) { s.bind(1, id); };
  auto purchase = requireOne(db, R"SQL(
    SELECT p.id, p.supplier_id, s.name AS supplier_name, s.document_id AS supplier_document_id, p.ncf,
           p.invoice_date, p.subtotal_cents, p.tax_cents, p.total_cents, p.payment_method, p.cash_session_id,
           p.created_at, u.name AS user_name
    FROM purchases AS p
    LEFT JOIN suppliers AS s ON s.id = p.supplier_id
    JOIN users AS u ON u.id = p.user_id
    WHERE p.id = ?1
  )SQL",
                             bindId, "La compra no existe");
  purchase["items"] = queryAll(db, R"SQL(
    SELECT i.id, i.position, i.product_id, pr.name AS product_name, i.quantity_milli, i.unit_cost_cents,
           (i.quantity_milli * i.unit_cost_cents + 500) / 1000 AS line_cost_cents
    FROM purchase_items AS i
    JOIN products AS pr ON pr.id = i.product_id
    WHERE i.purchase_id = ?1
    ORDER BY i.position
  )SQL",
                               bindId);
  return purchase;
}

Json createPurchase(Context& context) {
  const auto& actor = context.requireActor();
  const auto& p = context.params;
  const auto supplierId = p.optionalString("supplierId", 36);
  if (supplierId) {
    requireExists(context.db, "suppliers", *supplierId, "El suplidor no existe");
  }
  const auto ncf = p.optionalString("ncf", 19);
  const auto invoiceDate = validDate(p, "invoiceDate");
  if (!invoiceDate) {
    invalidField("invoiceDate", "es obligatorio");
  }
  const auto method = p.requireEnum("paymentMethod", {"cash", "card", "transfer", "credit"});
  const auto tax = p.intOr("taxCents", 0);
  if (tax < 0) {
    invalidField("taxCents", "no puede ser negativo");
  }
  if (supplierId && ncf) {
    const auto duplicated = queryInt(context.db, "SELECT count(*) FROM purchases WHERE supplier_id = ?1 AND ncf = ?2",
                                     [&](db::Statement& s) {
                                       s.bind(1, *supplierId);
                                       s.bind(2, *ncf);
                                     });
    if (duplicated > 0) {
      throw ApiError(errc::kConflict, "La factura " + *ncf + " de ese suplidor ya está registrada");
    }
  }

  struct Item {
    std::string productId;
    std::int64_t quantity = 0;
    std::int64_t unitCost = 0;
  };
  const auto& itemsJson = p.requireArray("items");
  std::vector<Item> items;
  domain::Cents subtotal = 0;
  for (std::size_t i = 0; i < itemsJson.size(); ++i) {
    const std::string prefix = "items[" + std::to_string(i) + "]";
    if (!itemsJson[i].is_object()) {
      invalidField(prefix, "debe ser un objeto");
    }
    const Params item(itemsJson[i], prefix);
    Item parsed{item.requireString("productId", 36), item.requireIntAtLeast("quantityMilli", 1),
                item.requireIntAtLeast("unitCostCents", 0)};
    requireExists(context.db, "products", parsed.productId, "El producto de " + prefix + " no existe");
    subtotal += domain::lineAmount(parsed.unitCost, parsed.quantity);
    items.push_back(std::move(parsed));
  }

  // Pagada en efectivo, la compra sale de la caja abierta.
  const auto sessionId = method == "cash" ? std::optional<std::string>(requireOpenCashSession(context.db))
                                          : std::nullopt;
  const auto id = newId();
  execute(context.db, R"SQL(
    INSERT INTO purchases (id, supplier_id, ncf, invoice_date, subtotal_cents, tax_cents, total_cents,
                           payment_method, cash_session_id, user_id)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
  )SQL",
          [&](db::Statement& s) {
            s.bind(1, id);
            s.bind(2, supplierId);
            s.bind(3, ncf);
            s.bind(4, *invoiceDate);
            s.bind(5, subtotal);
            s.bind(6, tax);
            s.bind(7, subtotal + tax);
            s.bind(8, method);
            s.bind(9, sessionId);
            s.bind(10, actor.id);
          });
  for (std::size_t i = 0; i < items.size(); ++i) {
    execute(context.db,
            "INSERT INTO purchase_items (id, purchase_id, position, product_id, quantity_milli, unit_cost_cents) "
            "VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
            [&](db::Statement& s) {
              s.bind(1, newId());
              s.bind(2, id);
              s.bind(3, static_cast<std::int64_t>(i));
              s.bind(4, items[i].productId);
              s.bind(5, items[i].quantity);
              s.bind(6, items[i].unitCost);
            });
  }
  audit(context, "purchase.create", "purchase", id, Json{{"totalCents", subtotal + tax}, {"paymentMethod", method}});
  return purchaseDetail(context.db, id);
}

Json listPurchases(Context& context) {
  const auto& p = context.params;
  const auto from = validDate(p, "from");
  const auto to = validDate(p, "to");
  const auto limit = std::clamp<std::int64_t>(p.intOr("limit", 100), 1, 1000);
  const auto offset = std::max<std::int64_t>(p.intOr("offset", 0), 0);
  std::string sql = R"SQL(
    SELECT p.id, p.invoice_date, p.ncf, p.total_cents, p.payment_method, s.name AS supplier_name,
           (SELECT count(*) FROM purchase_items AS i WHERE i.purchase_id = p.id) AS item_count
    FROM purchases AS p
    LEFT JOIN suppliers AS s ON s.id = p.supplier_id
    WHERE 1 = 1
  )SQL";
  if (from) sql += " AND p.invoice_date >= ?1";
  if (to) sql += " AND p.invoice_date <= ?2";
  sql += " ORDER BY p.invoice_date DESC, p.created_at DESC LIMIT ?3 OFFSET ?4";
  return queryAll(context.db, sql, [&](db::Statement& s) {
    if (from) s.bind(1, *from);
    if (to) s.bind(2, *to);
    s.bind(3, limit);
    s.bind(4, offset);
  });
}

Json getPurchase(Context& context) { return purchaseDetail(context.db, context.params.requireString("id", 36)); }

// --- Ajustes ------------------------------------------------------------------

struct StockProduct {
  std::string name;
  std::int64_t stock = 0;
  std::int64_t cost = 0;
};

// Los ajustes se hacen sobre el producto base, no sobre su presentación al detalle.
StockProduct requireBaseProduct(db::Database& db, const std::string& productId) {
  auto statement = db.prepare("SELECT name, stock_milli, cost_cents, stock_source_id FROM products WHERE id = ?1");
  statement.bind(1, productId);
  if (!statement.step()) {
    throw ApiError(errc::kNotFound, "El producto no existe");
  }
  if (!statement.isNull(3)) {
    invalidField("productId", "es una presentación al detalle; ajusta la existencia del producto base");
  }
  return StockProduct{statement.getText(0), statement.getInt(1), statement.getInt(2)};
}

void insertMovement(const Context& context, const std::string& productId, const std::string& kind,
                    std::int64_t quantity, std::int64_t unitCost, const std::string& note) {
  execute(context.db,
          "INSERT INTO stock_movements (product_id, kind, quantity_milli, unit_cost_cents, note, user_id) "
          "VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
          [&](db::Statement& s) {
            s.bind(1, productId);
            s.bind(2, kind);
            s.bind(3, quantity);
            s.bind(4, unitCost);
            s.bind(5, note);
            s.bind(6, context.requireActor().id);
          });
}

Json stockSummary(db::Database& db, const std::string& productId) {
  return requireOne(db, "SELECT id, name, stock_milli, min_stock_milli, cost_cents FROM products WHERE id = ?1",
                    [&](db::Statement& s) { s.bind(1, productId); }, "El producto no existe");
}

Json adjust(Context& context) {
  const auto& p = context.params;
  const auto productId = p.requireString("productId", 36);
  const auto quantity = p.requireInt("quantityMilli");
  const auto kind = p.requireEnum("kind", {"adjustment", "waste"});
  const auto note = p.requireString("note", 200);
  if (quantity == 0) {
    invalidField("quantityMilli", "no puede ser cero");
  }
  if (kind == "waste" && quantity > 0) {
    invalidField("quantityMilli", "una merma debe ser negativa");
  }
  const auto product = requireBaseProduct(context.db, productId);
  insertMovement(context, productId, kind, quantity, product.cost, note);
  audit(context, "inventory.adjust", "product", productId, Json{{"kind", kind}, {"quantityMilli", quantity}});
  return stockSummary(context.db, productId);
}

// Conteo físico: registra la diferencia entre lo contado y lo que dice el sistema.
Json count(Context& context) {
  const auto& p = context.params;
  const auto productId = p.requireString("productId", 36);
  const auto counted = p.requireIntAtLeast("countedMilli", 0);
  const auto product = requireBaseProduct(context.db, productId);
  const auto difference = counted - product.stock;
  if (difference != 0) {
    insertMovement(context, productId, "adjustment", difference, product.cost,
                   p.optionalString("note", 200).value_or("Conteo físico"));
  }
  audit(context, "inventory.count", "product", productId,
        Json{{"previousMilli", product.stock}, {"countedMilli", counted}});

  Json result = Json::object();
  result["productId"] = productId;
  result["name"] = product.name;
  result["previousMilli"] = product.stock;
  result["countedMilli"] = counted;
  result["differenceMilli"] = difference;
  return result;
}

Json movements(Context& context) {
  const auto productId = context.params.requireString("productId", 36);
  const auto limit = std::clamp<std::int64_t>(context.params.intOr("limit", 100), 1, 1000);
  return queryAll(context.db, R"SQL(
    SELECT m.id, m.kind, m.quantity_milli, m.unit_cost_cents, m.note, m.created_at,
           u.name AS user_name, s.number AS sale_number
    FROM stock_movements AS m
    LEFT JOIN users AS u ON u.id = m.user_id
    LEFT JOIN sale_items AS si ON si.id = m.sale_item_id
    LEFT JOIN sales AS s ON s.id = si.sale_id
    WHERE m.product_id = ?1
    ORDER BY m.id DESC
    LIMIT ?2
  )SQL",
                  [&](db::Statement& s) {
                    s.bind(1, productId);
                    s.bind(2, limit);
                  });
}

Json lowStock(Context& context) {
  return queryAll(context.db,
                  "SELECT product_id, name, stock_milli, min_stock_milli, unit FROM v_low_stock ORDER BY name COLLATE NOCASE");
}

}  // namespace

void registerInventory(Registry& registry) {
  registry.add("inventory.suppliers.list", {listSuppliers, true, roles::kCash, false});
  registry.add("inventory.suppliers.create", {createSupplier, true, roles::kManagers, true});
  registry.add("inventory.suppliers.update", {updateSupplier, true, roles::kManagers, true});
  registry.add("inventory.purchases.create", {createPurchase, true, roles::kManagers, true});
  registry.add("inventory.purchases.list", {listPurchases, true, roles::kManagers, false});
  registry.add("inventory.purchases.get", {getPurchase, true, roles::kManagers, false});
  registry.add("inventory.adjust", {adjust, true, roles::kManagers, true});
  registry.add("inventory.count", {count, true, roles::kManagers, true});
  registry.add("inventory.movements", {movements, true, roles::kManagers, false});
  registry.add("inventory.lowStock", {lowStock, true, roles::kCash, false});
}

}  // namespace voxon::services
