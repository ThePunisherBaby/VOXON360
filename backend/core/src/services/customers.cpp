// Clientes y fiao: cuentas por cobrar con límite de crédito y abonos.

#include <algorithm>
#include <string>

#include "core/error.hpp"
#include "services/common.hpp"
#include "services/services.hpp"
#include "text/text.hpp"

namespace voxon::services {

namespace {

constexpr const char* kSelectCustomers = R"SQL(
SELECT id, name, phone, document_id, address, credit_limit_cents, balance_cents,
       max(credit_limit_cents - balance_cents, 0) AS available_credit_cents, active, created_at, updated_at
FROM customers
)SQL";

Json customerById(db::Database& db, const std::string& id) {
  return requireOne(db, std::string(kSelectCustomers) + " WHERE id = ?1", [&](db::Statement& s) { s.bind(1, id); },
                    "El cliente no existe");
}

bool isManager(const Actor& actor) { return actor.role == Role::Owner || actor.role == Role::Manager; }

// Autorizar o cambiar el fiao de un cliente es decisión del dueño o un gerente.
std::int64_t creditLimit(const Context& context, std::int64_t fallback) {
  const auto limit = context.params.intOr("creditLimitCents", fallback);
  if (limit < 0) {
    invalidField("creditLimitCents", "no puede ser negativo");
  }
  if (limit != fallback && !isManager(context.requireActor())) {
    throw ApiError(errc::kForbidden, "Solo el dueño o un gerente pueden autorizar fiao");
  }
  return limit;
}

Json list(Context& context) {
  const auto& p = context.params;
  const auto search = p.optionalString("search", 80);
  const auto limit = std::clamp<std::int64_t>(p.intOr("limit", 200), 1, 1000);
  const auto offset = std::max<std::int64_t>(p.intOr("offset", 0), 0);

  std::string sql = std::string(kSelectCustomers) + " WHERE 1 = 1";
  if (!p.boolOr("includeInactive", false)) {
    sql += " AND active = 1";
  }
  if (p.boolOr("withBalance", false)) {
    sql += " AND balance_cents > 0";
  }
  if (search) {
    sql += " AND (search_name LIKE ?1 ESCAPE '\\' OR phone LIKE ?2 ESCAPE '\\' OR document_id = ?3)";
  }
  sql += " ORDER BY name COLLATE NOCASE LIMIT ?4 OFFSET ?5";

  return queryAll(context.db, sql, [&](db::Statement& s) {
    if (search) {
      s.bind(1, likePattern(text::normalizeForSearch(*search)));
      s.bind(2, likePattern(*search));
      s.bind(3, *search);
    }
    s.bind(4, limit);
    s.bind(5, offset);
  });
}

Json get(Context& context) { return customerById(context.db, context.params.requireString("id", 36)); }

Json create(Context& context) {
  const auto& p = context.params;
  const auto id = newId();
  const auto name = p.requireString("name", 80);
  const auto limit = creditLimit(context, 0);
  execute(context.db, R"SQL(
    INSERT INTO customers (id, name, search_name, phone, document_id, address, credit_limit_cents)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
  )SQL",
          [&](db::Statement& s) {
            s.bind(1, id);
            s.bind(2, name);
            s.bind(3, text::normalizeForSearch(name));
            s.bind(4, p.optionalString("phone", 30));
            s.bind(5, optionalDocumentId(p, "documentId"));
            s.bind(6, p.optionalString("address", 200));
            s.bind(7, limit);
          });
  audit(context, "customer.create", "customer", id, Json{{"name", name}, {"creditLimitCents", limit}});
  return customerById(context.db, id);
}

Json update(Context& context) {
  const auto& p = context.params;
  const auto id = p.requireString("id", 36);
  const auto current = customerById(context.db, id);

  const auto name = p.has("name") ? p.requireString("name", 80) : current["name"].get<std::string>();
  const auto previousLimit = current["creditLimitCents"].get<std::int64_t>();
  const auto limit = creditLimit(context, previousLimit);
  const bool active = p.boolOr("active", current["active"].get<bool>());
  if (active != current["active"].get<bool>() && !isManager(context.requireActor())) {
    throw ApiError(errc::kForbidden, "Solo el dueño o un gerente pueden activar o desactivar clientes");
  }

  auto textField = [&](const char* key, std::size_t max) -> std::optional<std::string> {
    if (p.contains(key)) {
      return p.optionalString(key, max);
    }
    const auto& value = current[key];
    return value.is_null() ? std::nullopt : std::optional<std::string>(value.get<std::string>());
  };
  auto documentId = textField("documentId", 11);
  if (p.contains("documentId")) {
    documentId = optionalDocumentId(p, "documentId");
  }

  execute(context.db, R"SQL(
    UPDATE customers SET name = ?1, search_name = ?2, phone = ?3, document_id = ?4, address = ?5,
                         credit_limit_cents = ?6, active = ?7
    WHERE id = ?8
  )SQL",
          [&](db::Statement& s) {
            s.bind(1, name);
            s.bind(2, text::normalizeForSearch(name));
            s.bind(3, textField("phone", 30));
            s.bind(4, documentId);
            s.bind(5, textField("address", 200));
            s.bind(6, limit);
            s.bind(7, active ? 1 : 0);
            s.bind(8, id);
          });
  if (limit != previousLimit) {
    audit(context, "customer.creditLimitChanged", "customer", id,
          Json{{"fromCents", previousLimit}, {"toCents", limit}});
  }
  audit(context, "customer.update", "customer", id);
  return customerById(context.db, id);
}

// Estado de cuenta: saldo y movimientos del fiao, del más reciente al más antiguo.
Json statement(Context& context) {
  const auto id = context.params.requireString("id", 36);
  const auto limit = std::clamp<std::int64_t>(context.params.intOr("limit", 100), 1, 1000);
  Json result = Json::object();
  result["customer"] = customerById(context.db, id);
  result["entries"] = queryAll(context.db, R"SQL(
    SELECT e.id, e.kind, e.amount_cents, e.method, e.note, e.created_at, s.number AS sale_number, u.name AS user_name
    FROM credit_entries AS e
    LEFT JOIN sales AS s ON s.id = e.sale_id
    JOIN users AS u ON u.id = e.user_id
    WHERE e.customer_id = ?1
    ORDER BY e.created_at DESC, e.rowid DESC
    LIMIT ?2
  )SQL",
                               [&](db::Statement& s) {
                                 s.bind(1, id);
                                 s.bind(2, limit);
                               });
  return result;
}

// Abono al fiao. En efectivo entra a la caja abierta.
Json payment(Context& context) {
  const auto& p = context.params;
  const auto& actor = context.requireActor();
  const auto customerId = p.requireString("customerId", 36);
  const auto amount = p.requireIntAtLeast("amountCents", 1);
  const auto method = p.requireEnum("method", {"cash", "card", "transfer"});
  customerById(context.db, customerId);

  const auto sessionId = method == "cash" ? std::optional<std::string>(requireOpenCashSession(context.db))
                                          : openCashSessionId(context.db);
  const auto entryId = newId();
  execute(context.db, R"SQL(
    INSERT INTO credit_entries (id, customer_id, kind, amount_cents, cash_session_id, method, note, user_id)
    VALUES (?1, ?2, 'payment', ?3, ?4, ?5, ?6, ?7)
  )SQL",
          [&](db::Statement& s) {
            s.bind(1, entryId);
            s.bind(2, customerId);
            s.bind(3, -amount);
            s.bind(4, sessionId);
            s.bind(5, method);
            s.bind(6, p.optionalString("note", 200));
            s.bind(7, actor.id);
          });
  audit(context, "customer.payment", "customer", customerId, Json{{"amountCents", amount}, {"method", method}});

  Json result = Json::object();
  result["entryId"] = entryId;
  result["customer"] = customerById(context.db, customerId);
  return result;
}

}  // namespace

void registerCustomers(Registry& registry) {
  registry.add("customers.list", {list, true, roles::kFloor, false});
  registry.add("customers.get", {get, true, roles::kFloor, false});
  registry.add("customers.create", {create, true, roles::kCash, true});
  registry.add("customers.update", {update, true, roles::kCash, true});
  registry.add("customers.statement", {statement, true, roles::kCash, false});
  registry.add("customers.payment", {payment, true, roles::kCash, true});
}

}  // namespace voxon::services
