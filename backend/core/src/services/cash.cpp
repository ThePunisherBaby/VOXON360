// Caja: apertura, entradas y salidas de efectivo, y cierre con cuadre.
// El efectivo esperado sale de la vista v_cash_session_balance (SQL).

#include <algorithm>
#include <string>

#include "core/error.hpp"
#include "services/common.hpp"
#include "services/services.hpp"

namespace voxon::services {

namespace {

Json sessionReport(db::Database& db, const std::string& sessionId) {
  const auto bindId = [&](db::Statement& s) { s.bind(1, sessionId); };
  auto report = requireOne(db, R"SQL(
    SELECT b.*, cs.notes, opener.name AS opened_by_name, closer.name AS closed_by_name
    FROM v_cash_session_balance AS b
    JOIN cash_sessions AS cs ON cs.id = b.session_id
    JOIN users AS opener ON opener.id = b.opened_by
    LEFT JOIN users AS closer ON closer.id = b.closed_by
    WHERE b.session_id = ?1
  )SQL",
                           bindId, "La caja no existe");

  report["sales"] = *queryOne(db, R"SQL(
    SELECT count(*) AS count, coalesce(sum(total_cents), 0) AS total_cents, coalesce(sum(tax_cents), 0) AS tax_cents,
           coalesce(sum(tip_cents), 0) AS tip_cents, coalesce(sum(discount_cents), 0) AS discount_cents
    FROM sales WHERE cash_session_id = ?1 AND status = 'completed'
  )SQL",
                              bindId);
  report["voidedSales"] =
      queryInt(db, "SELECT count(*) FROM sales WHERE cash_session_id = ?1 AND status = 'voided'", bindId);
  report["payments"] = queryAll(
      db, "SELECT method, amount_cents, sales_count FROM v_cash_session_payments WHERE session_id = ?1 ORDER BY method",
      bindId);
  report["movements"] = queryAll(db, R"SQL(
    SELECT m.id, m.kind, m.amount_cents, m.reason, m.created_at, u.name AS user_name
    FROM cash_movements AS m JOIN users AS u ON u.id = m.user_id
    WHERE m.session_id = ?1 ORDER BY m.created_at, m.rowid
  )SQL",
                                 bindId);
  return report;
}

Json current(Context& context) {
  const auto sessionId = openCashSessionId(context.db);
  return sessionId ? sessionReport(context.db, *sessionId) : Json(nullptr);
}

Json open(Context& context) {
  const auto& actor = context.requireActor();
  if (openCashSessionId(context.db)) {
    throw ApiError(errc::kCashSessionOpen, "Ya hay una caja abierta; ciérrala antes de abrir otra");
  }
  const auto openingFloat = context.params.requireIntAtLeast("openingFloatCents", 0);
  const auto id = newId();
  execute(context.db, "INSERT INTO cash_sessions (id, opened_by, opening_float_cents) VALUES (?1, ?2, ?3)",
          [&](db::Statement& s) {
            s.bind(1, id);
            s.bind(2, actor.id);
            s.bind(3, openingFloat);
          });
  audit(context, "cash.open", "cash_session", id, Json{{"openingFloatCents", openingFloat}});
  return sessionReport(context.db, id);
}

Json movement(Context& context) {
  const auto& actor = context.requireActor();
  const auto sessionId = requireOpenCashSession(context.db);
  const auto kind = context.params.requireEnum("kind", {"cash_in", "cash_out"});
  const auto amount = context.params.requireIntAtLeast("amountCents", 1);
  const auto reason = context.params.requireString("reason", 120);
  const auto id = newId();
  execute(context.db,
          "INSERT INTO cash_movements (id, session_id, kind, amount_cents, reason, user_id) "
          "VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
          [&](db::Statement& s) {
            s.bind(1, id);
            s.bind(2, sessionId);
            s.bind(3, kind);
            s.bind(4, amount);
            s.bind(5, reason);
            s.bind(6, actor.id);
          });
  audit(context, "cash.movement", "cash_session", sessionId,
        Json{{"kind", kind}, {"amountCents", amount}, {"reason", reason}});
  return sessionReport(context.db, sessionId);
}

Json close(Context& context) {
  const auto& actor = context.requireActor();
  const auto sessionId = requireOpenCashSession(context.db);
  const auto counted = context.params.requireIntAtLeast("countedCashCents", 0);
  const auto expected = queryInt(context.db,
                                 "SELECT expected_cash_cents FROM v_cash_session_balance WHERE session_id = ?1",
                                 [&](db::Statement& s) { s.bind(1, sessionId); });

  execute(context.db, std::string(R"SQL(
    UPDATE cash_sessions
    SET closed_at = )SQL") + kNowSql + R"SQL(, closed_by = ?1, expected_cash_cents = ?2, counted_cash_cents = ?3, notes = ?4
    WHERE id = ?5
  )SQL",
          [&](db::Statement& s) {
            s.bind(1, actor.id);
            s.bind(2, expected);
            s.bind(3, counted);
            s.bind(4, context.params.optionalString("notes", 500));
            s.bind(5, sessionId);
          });
  audit(context, "cash.close", "cash_session", sessionId,
        Json{{"expectedCashCents", expected}, {"countedCashCents", counted}, {"differenceCents", counted - expected}});
  return sessionReport(context.db, sessionId);
}

Json sessions(Context& context) {
  const auto limit = std::clamp<std::int64_t>(context.params.intOr("limit", 50), 1, 500);
  return queryAll(context.db, R"SQL(
    SELECT b.session_id, b.opened_at, b.closed_at, b.opening_float_cents, b.expected_cash_cents,
           b.counted_cash_cents, b.difference_cents, opener.name AS opened_by_name, closer.name AS closed_by_name
    FROM v_cash_session_balance AS b
    JOIN users AS opener ON opener.id = b.opened_by
    LEFT JOIN users AS closer ON closer.id = b.closed_by
    ORDER BY b.opened_at DESC
    LIMIT ?1
  )SQL",
                  [&](db::Statement& s) { s.bind(1, limit); });
}

Json report(Context& context) { return sessionReport(context.db, context.params.requireString("sessionId", 36)); }

}  // namespace

void registerCash(Registry& registry) {
  registry.add("cash.current", {current, true, roles::kCash, false});
  registry.add("cash.open", {open, true, roles::kCash, true});
  registry.add("cash.movement", {movement, true, roles::kCash, true});
  registry.add("cash.close", {close, true, roles::kCash, true});
  registry.add("cash.sessions", {sessions, true, roles::kManagers, false});
  registry.add("cash.report", {report, true, roles::kManagers, false});
}

}  // namespace voxon::services
