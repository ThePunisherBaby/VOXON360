// Resumen para la app del dueño. Solo lee: el servidor Java lo sube a Firebase
// cuando hay internet (ver backend/README.md). Vender nunca depende de esto.

#include <cstdint>
#include <string>

#include "core/error.hpp"
#include "services/common.hpp"
#include "services/services.hpp"

namespace voxon::services {

namespace {

// Un día local de República Dominicana (UTC-4) expresado en UTC, como en reports.cpp.
constexpr const char* kDayStartUtc = "strftime('%Y-%m-%dT%H:%M:%fZ', ?1, '+4 hours')";
constexpr const char* kDayEndUtc = "strftime('%Y-%m-%dT%H:%M:%fZ', ?1, '+1 day', '+4 hours')";

constexpr std::int64_t kMaxDays = 31;

std::string createdInDay() {
  return std::string("s.created_at >= ") + kDayStartUtc + " AND s.created_at < " + kDayEndUtc;
}

std::string textQuery(db::Database& db, const char* sql, const Binder& bind = {}) {
  auto statement = db.prepare(sql);
  if (bind) {
    bind(statement);
  }
  statement.step();
  return statement.getText(0);
}

// Totales, cobros, productos, horas, cajeros y últimas ventas de un día local.
Json daySummary(db::Database& db, const std::string& day) {
  const Binder bindDay = [&day](db::Statement& s) { s.bind(1, day); };
  const auto inDay = createdInDay();

  Json summary = Json::object();
  summary["day"] = day;
  summary["sales"] = *queryOne(db,
                               "SELECT count(*) AS count, coalesce(sum(s.total_cents), 0) AS total_cents, "
                               "coalesce(sum(s.tax_cents), 0) AS tax_cents, coalesce(sum(s.tip_cents), 0) AS tip_cents, "
                               "coalesce(sum(s.discount_cents), 0) AS discount_cents, "
                               "coalesce(sum(s.total_cents) / nullif(count(*), 0), 0) AS average_ticket_cents "
                               "FROM sales AS s WHERE s.status = 'completed' AND " +
                                   inDay,
                               bindDay);
  summary["voided"] = *queryOne(db,
                                std::string("SELECT count(*) AS count, coalesce(sum(s.total_cents), 0) AS total_cents "
                                            "FROM sales AS s WHERE s.status = 'voided' AND s.voided_at >= ") +
                                    kDayStartUtc + " AND s.voided_at < " + kDayEndUtc,
                                bindDay);
  summary["payments"] = queryAll(
      db, "SELECT method, amount_cents FROM v_daily_payments WHERE day = ?1 ORDER BY amount_cents DESC", bindDay);
  summary["topProducts"] = queryAll(db, R"SQL(
    SELECT description, sum(quantity_milli) AS quantity_milli, sum(net_cents) AS net_cents,
           sum(margin_cents) AS margin_cents
    FROM v_product_sales
    WHERE day = ?1
    GROUP BY product_id, description
    ORDER BY net_cents DESC
    LIMIT 10
  )SQL",
                                    bindDay);
  summary["hourly"] = queryAll(db,
                               "SELECT CAST(strftime('%H', s.created_at, '-4 hours') AS INTEGER) AS hour, "
                               "count(*) AS count, sum(s.total_cents) AS total_cents "
                               "FROM sales AS s WHERE s.status = 'completed' AND " +
                                   inDay + " GROUP BY hour ORDER BY hour",
                               bindDay);
  summary["cashiers"] = queryAll(db,
                                 "SELECT u.name AS cashier_name, count(*) AS sales_count, "
                                 "sum(s.total_cents) AS total_cents "
                                 "FROM sales AS s JOIN users AS u ON u.id = s.cashier_id "
                                 "WHERE s.status = 'completed' AND " +
                                     inDay + " GROUP BY u.id ORDER BY total_cents DESC",
                                 bindDay);
  summary["recentSales"] = queryAll(db,
                                    std::string(R"SQL(
    SELECT s.number, s.created_at, s.status, s.total_cents, u.name AS cashier_name, c.name AS customer_name,
           (SELECT group_concat(DISTINCT p.method) FROM sale_payments AS p WHERE p.sale_id = s.id) AS methods
    FROM sales AS s
    JOIN users AS u ON u.id = s.cashier_id
    LEFT JOIN customers AS c ON c.id = s.customer_id
    WHERE )SQL") + inDay + " ORDER BY s.number DESC LIMIT 30",
                                    bindDay);
  return summary;
}

Json snapshot(Context& context) {
  const auto days = context.params.intOr("days", 2);
  if (days < 1 || days > kMaxDays) {
    invalidField("days", "debe estar entre 1 y 31");
  }
  auto& db = context.db;

  Json result = Json::object();
  result["generatedAt"] = textQuery(db, "SELECT strftime('%Y-%m-%dT%H:%M:%fZ', 'now')");
  result["business"] = queryOne(db, "SELECT name, business_type, rnc FROM business_profile WHERE id = 1").value_or(nullptr);
  result["openCashSession"] = queryOne(db, R"SQL(
    SELECT b.session_id, b.opened_at, b.opening_float_cents, b.expected_cash_cents, u.name AS opened_by_name
    FROM v_cash_session_balance AS b
    JOIN users AS u ON u.id = b.opened_by
    WHERE b.closed_at IS NULL
  )SQL")
                                  .value_or(nullptr);
  result["openOrders"] = queryInt(db, "SELECT count(*) FROM orders WHERE status = 'open'");
  result["lowStockCount"] = queryInt(db, "SELECT count(*) FROM v_low_stock");
  result["receivablesCents"] =
      queryInt(db, "SELECT coalesce(sum(balance_cents), 0) FROM customers WHERE balance_cents > 0");

  const auto today = textQuery(db, "SELECT date('now', '-4 hours')");
  result["days"] = Json::array();
  for (std::int64_t offset = 0; offset < days; ++offset) {
    const std::string modifier = "-" + std::to_string(offset) + " days";
    const auto day = textQuery(db, "SELECT date(?1, ?2)", [&](db::Statement& s) {
      s.bind(1, today);
      s.bind(2, modifier);
    });
    result["days"].push_back(daySummary(db, day));
  }

  result["cashSessions"] = queryAll(db, R"SQL(
    SELECT b.session_id, b.opened_at, b.closed_at, b.opening_float_cents, b.expected_cash_cents,
           b.counted_cash_cents, b.difference_cents, opener.name AS opened_by_name, closer.name AS closed_by_name
    FROM v_cash_session_balance AS b
    JOIN users AS opener ON opener.id = b.opened_by
    LEFT JOIN users AS closer ON closer.id = b.closed_by
    ORDER BY b.opened_at DESC
    LIMIT 10
  )SQL");
  result["lowStock"] = queryAll(db, R"SQL(
    SELECT name, stock_milli, min_stock_milli, unit FROM v_low_stock
    ORDER BY stock_milli - min_stock_milli, name
    LIMIT 50
  )SQL");
  result["receivables"] = queryAll(db, R"SQL(
    SELECT name, phone, balance_cents, credit_limit_cents, last_payment_at FROM v_customer_balances
    ORDER BY balance_cents DESC
    LIMIT 50
  )SQL");
  return result;
}

}  // namespace

void registerCloud(Registry& registry) {
  // Solo el dueño: estos datos salen del negocio hacia su app.
  registry.add("cloud.snapshot", {snapshot, true, roles::kOwner, false});
}

}  // namespace voxon::services
