// Reportes a partir de las vistas SQL. Los días son de República Dominicana
// (UTC-4): un día local va de las 04:00Z de ese día a las 04:00Z del siguiente.

#include <algorithm>
#include <string>

#include "core/error.hpp"
#include "services/common.hpp"
#include "services/services.hpp"

namespace voxon::services {

namespace {

// Límites en UTC de un rango de días locales, para aprovechar el índice de created_at.
constexpr const char* kFromUtc = "strftime('%Y-%m-%dT%H:%M:%fZ', ?1, '+4 hours')";
constexpr const char* kToUtc = "strftime('%Y-%m-%dT%H:%M:%fZ', ?2, '+1 day', '+4 hours')";

struct DateRange {
  std::string from;
  std::string to;
};

std::string requireDate(const Params& params, const char* key) {
  const auto value = params.requireString(key, 10);
  if (!isIsoDate(value)) {
    invalidField(key, "debe tener el formato AAAA-MM-DD");
  }
  return value;
}

DateRange requireRange(const Params& params) {
  DateRange range{requireDate(params, "from"), requireDate(params, "to")};
  if (range.to < range.from) {
    invalidField("to", "no puede ser anterior a 'from'");
  }
  return range;
}

Binder bindRange(const DateRange& range) {
  return [range](db::Statement& s) {
    s.bind(1, range.from);
    s.bind(2, range.to);
  };
}

std::string today(db::Database& db) {
  auto statement = db.prepare("SELECT date('now', '-4 hours')");
  statement.step();
  return statement.getText(0);
}

Json dashboard(Context& context) {
  const auto day = context.params.has("day") ? requireDate(context.params, "day") : today(context.db);
  const DateRange range{day, day};
  const auto bindDay = [&](db::Statement& s) { s.bind(1, day); };

  Json result = Json::object();
  result["day"] = day;
  result["sales"] = *queryOne(context.db,
                              std::string(R"SQL(
    SELECT count(*) AS count, coalesce(sum(total_cents), 0) AS total_cents, coalesce(sum(tax_cents), 0) AS tax_cents,
           coalesce(sum(tip_cents), 0) AS tip_cents, coalesce(sum(discount_cents), 0) AS discount_cents,
           coalesce(sum(total_cents) / nullif(count(*), 0), 0) AS average_ticket_cents
    FROM sales
    WHERE status = 'completed' AND created_at >= )SQL") + kFromUtc + " AND created_at < " + kToUtc,
                              bindRange(range));
  result["payments"] = queryAll(
      context.db, "SELECT method, amount_cents FROM v_daily_payments WHERE day = ?1 ORDER BY amount_cents DESC", bindDay);
  result["topProducts"] = queryAll(context.db, R"SQL(
    SELECT product_id, description, sum(quantity_milli) AS quantity_milli, sum(net_cents) AS net_cents
    FROM v_product_sales WHERE day = ?1
    GROUP BY product_id, description
    ORDER BY net_cents DESC
    LIMIT 5
  )SQL",
                                   bindDay);
  result["voidedSales"] = queryInt(
      context.db,
      std::string("SELECT count(*) FROM sales WHERE status = 'voided' AND voided_at >= ") + kFromUtc +
          " AND voided_at < " + kToUtc,
      bindRange(range));
  result["openCashSession"] =
      queryOne(context.db,
               "SELECT session_id, opened_at, expected_cash_cents FROM v_cash_session_balance WHERE closed_at IS NULL")
          .value_or(nullptr);
  result["lowStockCount"] = queryInt(context.db, "SELECT count(*) FROM v_low_stock");
  result["receivablesCents"] =
      queryInt(context.db, "SELECT coalesce(sum(balance_cents), 0) FROM customers WHERE balance_cents > 0");
  result["openOrders"] = queryInt(context.db, "SELECT count(*) FROM orders WHERE status = 'open'");
  return result;
}

Json salesByDay(Context& context) {
  const auto range = requireRange(context.params);
  Json result = Json::object();
  result["days"] = queryAll(context.db, "SELECT * FROM v_daily_sales WHERE day BETWEEN ?1 AND ?2 ORDER BY day",
                            bindRange(range));
  result["totals"] = *queryOne(context.db,
                               std::string(R"SQL(
    SELECT count(*) AS sales_count, coalesce(sum(subtotal_cents), 0) AS subtotal_cents,
           coalesce(sum(discount_cents), 0) AS discount_cents, coalesce(sum(tax_cents), 0) AS tax_cents,
           coalesce(sum(tip_cents), 0) AS tip_cents, coalesce(sum(total_cents), 0) AS total_cents
    FROM sales WHERE status = 'completed' AND created_at >= )SQL") + kFromUtc + " AND created_at < " + kToUtc,
                               bindRange(range));
  return result;
}

Json productSales(Context& context) {
  const auto range = requireRange(context.params);
  const auto limit = std::clamp<std::int64_t>(context.params.intOr("limit", 100), 1, 1000);
  return queryAll(context.db, R"SQL(
    SELECT product_id, description, sum(quantity_milli) AS quantity_milli, sum(net_cents) AS net_cents,
           sum(cost_cents) AS cost_cents, sum(margin_cents) AS margin_cents
    FROM v_product_sales
    WHERE day BETWEEN ?1 AND ?2
    GROUP BY product_id, description
    ORDER BY net_cents DESC
    LIMIT ?3
  )SQL",
                  [&](db::Statement& s) {
                    s.bind(1, range.from);
                    s.bind(2, range.to);
                    s.bind(3, limit);
                  });
}

Json paymentsByDay(Context& context) {
  const auto range = requireRange(context.params);
  return queryAll(context.db,
                  "SELECT day, method, amount_cents FROM v_daily_payments WHERE day BETWEEN ?1 AND ?2 ORDER BY day, method",
                  bindRange(range));
}

Json cashiers(Context& context) {
  const auto range = requireRange(context.params);
  return queryAll(context.db,
                  std::string(R"SQL(
    SELECT u.id AS cashier_id, u.name AS cashier_name, count(*) AS sales_count,
           sum(s.total_cents) AS total_cents, sum(s.tip_cents) AS tip_cents
    FROM sales AS s
    JOIN users AS u ON u.id = s.cashier_id
    WHERE s.status = 'completed' AND s.created_at >= )SQL") + kFromUtc + " AND s.created_at < " + kToUtc +
                      " GROUP BY u.id ORDER BY total_cents DESC",
                  bindRange(range));
}

Json receivables(Context& context) {
  Json result = Json::object();
  result["customers"] = queryAll(context.db, "SELECT * FROM v_customer_balances ORDER BY balance_cents DESC");
  result["totalCents"] =
      queryInt(context.db, "SELECT coalesce(sum(balance_cents), 0) FROM customers WHERE balance_cents > 0");
  return result;
}

Json auditLog(Context& context) {
  const auto& p = context.params;
  const auto entity = p.optionalString("entity", 40);
  const auto entityId = p.optionalString("entityId", 36);
  const auto action = p.optionalString("action", 60);
  const auto limit = std::clamp<std::int64_t>(p.intOr("limit", 100), 1, 500);

  std::string sql = R"SQL(
    SELECT a.id, a.action, a.entity, a.entity_id, a.details, a.created_at, u.name AS user_name
    FROM audit_log AS a
    LEFT JOIN users AS u ON u.id = a.user_id
    WHERE 1 = 1
  )SQL";
  if (entity) sql += " AND a.entity = ?1";
  if (entityId) sql += " AND a.entity_id = ?2";
  if (action) sql += " AND a.action = ?3";
  sql += " ORDER BY a.id DESC LIMIT ?4";

  auto rows = queryAll(context.db, sql, [&](db::Statement& s) {
    if (entity) s.bind(1, *entity);
    if (entityId) s.bind(2, *entityId);
    if (action) s.bind(3, *action);
    s.bind(4, limit);
  });
  for (auto& row : rows) {
    if (row["details"].is_string()) {
      row["details"] = Json::parse(row["details"].get<std::string>(), nullptr, false);
    }
  }
  return rows;
}

}  // namespace

void registerReports(Registry& registry) {
  registry.add("reports.dashboard", {dashboard, true, roles::kManagers, false});
  registry.add("reports.salesByDay", {salesByDay, true, roles::kManagers, false});
  registry.add("reports.productSales", {productSales, true, roles::kManagers, false});
  registry.add("reports.paymentsByDay", {paymentsByDay, true, roles::kManagers, false});
  registry.add("reports.cashiers", {cashiers, true, roles::kManagers, false});
  registry.add("reports.receivables", {receivables, true, roles::kCash, false});
  registry.add("reports.audit", {auditLog, true, roles::kOwner, false});
}

}  // namespace voxon::services
