// Ventas: cotizar, cobrar, consultar y anular.
//
// Los precios y tasas salen del catálogo (nunca del cliente, salvo artículos
// libres o precio manual autorizado) y los totales los calcula domain::calculateSale.

#include "services/sales.hpp"

#include <algorithm>
#include <map>
#include <string>
#include <vector>

#include "core/error.hpp"
#include "domain/money.hpp"
#include "services/common.hpp"
#include "services/fiscal.hpp"
#include "services/services.hpp"

namespace voxon::services {

namespace {

struct ResolvedLine {
  std::optional<std::string> productId;
  std::string description;
  domain::Cents unitPrice = 0;
  domain::Milli quantity = 0;
  domain::TaxRate taxRate = domain::TaxRate::Standard;
  std::optional<domain::Discount> discount;
  domain::Cents unitCost = 0;
};

struct SaleDraft {
  domain::PriceMode priceMode = domain::PriceMode::TaxIncluded;
  std::vector<ResolvedLine> lines;
  domain::SaleTotals totals;
};

bool isManager(const Actor& actor) { return actor.role == Role::Owner || actor.role == Role::Manager; }

std::optional<std::string> textOf(const Json& value) {
  return value.is_null() ? std::nullopt : std::optional<std::string>(value.get<std::string>());
}

std::optional<domain::Discount> parseDiscount(const Params& params, const char* key) {
  if (!params.has(key)) {
    return std::nullopt;
  }
  const auto discount = params.object(key);
  const auto kind = discount.requireEnum("kind", {"amount", "percent"});
  const auto value = discount.requireIntAtLeast("value", 0);
  if (kind == "percent" && value > 10000) {
    invalidField(discount.field("value"), "no puede pasar de 10000 (100 %)");
  }
  return domain::Discount{kind == "percent" ? domain::Discount::Kind::Percent : domain::Discount::Kind::Amount, value};
}

SaleDraft buildDraft(Context& context, const Params& params) {
  const auto& actor = context.requireActor();
  const auto business = queryOne(context.db, "SELECT price_mode, legal_tip_enabled FROM business_profile WHERE id = 1");
  if (!business) {
    throw ApiError(errc::kNotConfigured, "El negocio aún no está configurado");
  }

  SaleDraft draft;
  draft.priceMode = *domain::parsePriceMode((*business)["priceMode"].get<std::string>());
  const bool wholesale = params.optionalEnum("priceList", {"retail", "wholesale"}).value_or("retail") == "wholesale";

  const auto& linesJson = params.requireArray("lines");
  if (linesJson.size() > 500) {
    invalidField("lines", "admite máximo 500 líneas");
  }
  for (std::size_t i = 0; i < linesJson.size(); ++i) {
    const std::string prefix = "lines[" + std::to_string(i) + "]";
    if (!linesJson[i].is_object()) {
      invalidField(prefix, "debe ser un objeto");
    }
    const Params line(linesJson[i], prefix);
    ResolvedLine resolved;
    resolved.quantity = line.requireIntAtLeast("quantityMilli", 1);
    resolved.discount = parseDiscount(line, "discount");

    if (const auto productId = line.optionalString("productId", 36)) {
      auto product = context.db.prepare(
          "SELECT name, price_cents, wholesale_price_cents, tax_rate, allows_fraction, cost_cents "
          "FROM products WHERE id = ?1 AND active = 1");
      product.bind(1, *productId);
      if (!product.step()) {
        throw ApiError(errc::kNotFound, "El producto de " + prefix + " no existe o está desactivado");
      }
      resolved.productId = *productId;
      resolved.description = product.getText(0);
      resolved.unitPrice = wholesale && !product.isNull(2) ? product.getInt(2) : product.getInt(1);
      resolved.taxRate = domain::parseTaxRate(product.getText(3)).value_or(domain::TaxRate::Standard);
      resolved.unitCost = product.getInt(5);
      if (product.getInt(4) == 0 && resolved.quantity % 1000 != 0) {
        invalidField(line.field("quantityMilli"), "debe ser entero: " + resolved.description + " se vende por unidades");
      }
      if (line.has("unitPriceCents")) {
        if (!isManager(actor)) {
          throw ApiError(errc::kForbidden, "Solo el dueño o un gerente pueden cambiar el precio en la venta");
        }
        resolved.unitPrice = line.requireIntAtLeast("unitPriceCents", 0);
      }
    } else {
      // Artículo libre, fuera del catálogo ("varios").
      resolved.description = line.requireString("description", 80);
      resolved.unitPrice = line.requireIntAtLeast("unitPriceCents", 0);
      resolved.taxRate = *domain::parseTaxRate(line.requireEnum("taxRate", {"exempt", "reduced", "standard"}));
    }
    draft.lines.push_back(std::move(resolved));
  }

  std::vector<domain::SaleLineInput> inputs;
  inputs.reserve(draft.lines.size());
  for (const auto& line : draft.lines) {
    inputs.push_back(domain::SaleLineInput{line.unitPrice, line.quantity, line.taxRate, line.discount});
  }
  const bool legalTip = params.boolOr("applyLegalTip", (*business)["legalTipEnabled"].get<bool>());
  draft.totals = domain::calculateSale(inputs, draft.priceMode, parseDiscount(params, "orderDiscount"),
                                       legalTip ? domain::kLegalTipBasisPoints : 0);
  return draft;
}

Json taxGroupsJson(const std::vector<domain::TaxGroup>& groups) {
  Json result = Json::array();
  for (const auto& group : groups) {
    Json item = Json::object();
    item["taxRate"] = std::string(domain::toString(group.rate));
    item["taxableBaseCents"] = group.taxableBase;
    item["taxCents"] = group.tax;
    result.push_back(std::move(item));
  }
  return result;
}

Json draftJson(const SaleDraft& draft) {
  Json lines = Json::array();
  for (std::size_t i = 0; i < draft.lines.size(); ++i) {
    const auto& line = draft.lines[i];
    const auto& totals = draft.totals.lines[i];
    Json item = Json::object();
    item["productId"] = line.productId ? Json(*line.productId) : Json(nullptr);
    item["description"] = line.description;
    item["unitPriceCents"] = line.unitPrice;
    item["quantityMilli"] = line.quantity;
    item["taxRate"] = std::string(domain::toString(line.taxRate));
    item["grossCents"] = totals.gross;
    item["discountCents"] = totals.lineDiscount + totals.orderDiscount;
    item["netCents"] = totals.net();
    lines.push_back(std::move(item));
  }
  Json result = Json::object();
  result["priceMode"] = std::string(domain::toString(draft.priceMode));
  result["lines"] = std::move(lines);
  result["taxGroups"] = taxGroupsJson(draft.totals.taxGroups);
  result["subtotalCents"] = draft.totals.subtotal();
  result["discountCents"] = draft.totals.discount();
  result["taxCents"] = draft.totals.tax();
  result["tipCents"] = draft.totals.tip;
  result["totalCents"] = draft.totals.total();
  return result;
}

// Desglose de ITBIS de una venta guardada, con el mismo algoritmo del cobro.
Json storedTaxGroups(domain::PriceMode priceMode, const Json& items) {
  std::map<int, domain::Cents> netByRate;
  for (const auto& item : items) {
    const auto rate = domain::parseTaxRate(item["taxRate"].get<std::string>()).value_or(domain::TaxRate::Standard);
    netByRate[static_cast<int>(rate)] += item["netCents"].get<std::int64_t>();
  }
  std::vector<domain::TaxGroup> groups;
  for (const auto& [rate, net] : netByRate) {
    const auto totals = domain::calculateSale({domain::SaleLineInput{net, 1000, static_cast<domain::TaxRate>(rate), {}}},
                                              priceMode, std::nullopt, 0);
    groups.push_back(totals.taxGroups.front());
  }
  return taxGroupsJson(groups);
}

Json quote(Context& context) { return draftJson(buildDraft(context, context.params)); }

Json complete(Context& context) { return completeSale(context, context.params, std::nullopt); }

Json get(Context& context) { return saleDetail(context.db, context.params.requireString("id", 36)); }

// Un cajero solo ve las ventas de la caja abierta.
Json list(Context& context) {
  const auto& actor = context.requireActor();
  const auto& p = context.params;
  const auto from = p.optionalString("from", 10);
  const auto to = p.optionalString("to", 10);
  for (const auto& [key, value] : {std::pair{"from", from}, std::pair{"to", to}}) {
    if (value && !isIsoDate(*value)) {
      invalidField(key, "debe tener el formato AAAA-MM-DD");
    }
  }
  auto sessionId = p.optionalString("sessionId", 36);
  if (!isManager(actor)) {
    sessionId = openCashSessionId(context.db);
    if (!sessionId) {
      return Json::array();
    }
  }
  const auto status = p.optionalEnum("status", {"completed", "voided"});
  const auto limit = std::clamp<std::int64_t>(p.intOr("limit", 100), 1, 1000);
  const auto offset = std::max<std::int64_t>(p.intOr("offset", 0), 0);

  std::string sql = R"SQL(
    SELECT s.id, s.number, s.status, s.created_at, s.total_cents, s.fiscal_document_type, s.ncf,
           u.name AS cashier_name, c.name AS customer_name
    FROM sales AS s
    JOIN users AS u ON u.id = s.cashier_id
    LEFT JOIN customers AS c ON c.id = s.customer_id
    WHERE 1 = 1
  )SQL";
  if (from) sql += " AND date(s.created_at, '-4 hours') >= ?1";
  if (to) sql += " AND date(s.created_at, '-4 hours') <= ?2";
  if (sessionId) sql += " AND s.cash_session_id = ?3";
  if (status) sql += " AND s.status = ?4";
  sql += " ORDER BY s.number DESC LIMIT ?5 OFFSET ?6";

  return queryAll(context.db, sql, [&](db::Statement& s) {
    if (from) s.bind(1, *from);
    if (to) s.bind(2, *to);
    if (sessionId) s.bind(3, *sessionId);
    if (status) s.bind(4, *status);
    s.bind(5, limit);
    s.bind(6, offset);
  });
}

// Anular devuelve la mercancía (trigger) y revierte el fiao. Solo con la caja
// de la venta abierta.
Json voidSale(Context& context) {
  const auto& actor = context.requireActor();
  const auto id = context.params.requireString("id", 36);
  const auto reason = context.params.requireString("reason", 200);
  const auto status = queryOne(context.db, "SELECT status FROM sales WHERE id = ?1",
                               [&](db::Statement& s) { s.bind(1, id); });
  if (!status) {
    throw ApiError(errc::kNotFound, "La venta no existe");
  }
  if ((*status)["status"] != "completed") {
    throw ApiError(errc::kConflict, "La venta ya está anulada");
  }

  execute(context.db,
          std::string("UPDATE sales SET status = 'voided', voided_at = ") + kNowSql +
              ", voided_by = ?1, void_reason = ?2 WHERE id = ?3",
          [&](db::Statement& s) {
            s.bind(1, actor.id);
            s.bind(2, reason);
            s.bind(3, id);
          });

  const auto charges =
      queryAll(context.db, "SELECT customer_id, amount_cents FROM credit_entries WHERE sale_id = ?1 AND kind = 'charge'",
               [&](db::Statement& s) { s.bind(1, id); });
  for (const auto& charge : charges) {
    execute(context.db,
            "INSERT INTO credit_entries (id, customer_id, kind, amount_cents, sale_id, note, user_id) "
            "VALUES (?1, ?2, 'charge_void', ?3, ?4, ?5, ?6)",
            [&](db::Statement& s) {
              s.bind(1, newId());
              s.bind(2, charge["customerId"].get<std::string>());
              s.bind(3, -charge["amountCents"].get<std::int64_t>());
              s.bind(4, id);
              s.bind(5, "Venta anulada: " + reason);
              s.bind(6, actor.id);
            });
  }
  audit(context, "sale.void", "sale", id, Json{{"reason", reason}});
  return saleDetail(context.db, id);
}

}  // namespace

Json completeSale(Context& context, const Params& params, const std::optional<std::string>& orderId) {
  const auto& actor = context.requireActor();
  const auto sessionId = requireOpenCashSession(context.db);
  const auto draft = buildDraft(context, params);
  const auto total = draft.totals.total();

  const auto& paymentsJson = params.requireArray("payments", /*allowEmpty=*/total == 0);
  std::vector<domain::Payment> payments;
  std::vector<std::optional<std::string>> references;
  domain::Cents creditAmount = 0;
  for (std::size_t i = 0; i < paymentsJson.size(); ++i) {
    const std::string prefix = "payments[" + std::to_string(i) + "]";
    if (!paymentsJson[i].is_object()) {
      invalidField(prefix, "debe ser un objeto");
    }
    const Params payment(paymentsJson[i], prefix);
    const auto method = *domain::parsePaymentMethod(payment.requireEnum("method", {"cash", "card", "transfer", "credit"}));
    const auto amount = payment.requireIntAtLeast("amountCents", 1);
    if (method == domain::PaymentMethod::Credit) {
      creditAmount += amount;
    }
    payments.push_back(domain::Payment{method, amount});
    references.push_back(payment.optionalString("reference", 60));
  }
  const auto summary = domain::summarizePayments(total, payments);
  if (!summary.isSettled()) {
    throw ApiError(errc::kInsufficientPayment, "Falta cobrar RD$" + domain::formatCents(summary.remaining()));
  }

  const auto customerId = params.optionalString("customerId", 36);
  std::optional<std::string> customerDocument;
  if (customerId) {
    const auto customer = queryOne(context.db, "SELECT document_id FROM customers WHERE id = ?1",
                                   [&](db::Statement& s) { s.bind(1, *customerId); });
    if (!customer) {
      throw ApiError(errc::kNotFound, "El cliente no existe");
    }
    customerDocument = textOf((*customer)["documentId"]);
  }
  if (creditAmount > 0 && !customerId) {
    invalidField("customerId", "es obligatorio para vender fiado");
  }

  std::optional<std::string> fiscalType;
  std::optional<std::string> ncf;
  std::optional<std::string> buyerDocument;
  const auto fiscal = params.object("fiscal");
  if (const auto type = fiscal.optionalEnum("documentType", {"B01", "B02", "B14", "B15", "E31", "E32"})) {
    buyerDocument = fiscal.has("buyerDocumentId") ? optionalDocumentId(fiscal, "buyerDocumentId") : customerDocument;
    const bool withFiscalValue = *type != "B02" && *type != "E32";
    if (withFiscalValue && !buyerDocument) {
      invalidField("fiscal.buyerDocumentId", "es obligatorio para comprobantes con valor fiscal");
    }
    fiscalType = type;
    ncf = assignFiscalNumber(context.db, *type);
  }

  const auto saleId = newId();
  const auto number = nextCounter(context.db, "sale");
  execute(context.db, R"SQL(
    INSERT INTO sales (id, number, status, price_mode, cashier_id, cash_session_id, customer_id, order_id,
                       fiscal_document_type, ncf, buyer_document_id, subtotal_cents, discount_cents, tax_cents,
                       tip_cents, total_cents, change_cents)
    VALUES (?1, ?2, 'completed', ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)
  )SQL",
          [&](db::Statement& s) {
            s.bind(1, saleId);
            s.bind(2, number);
            s.bind(3, domain::toString(draft.priceMode));
            s.bind(4, actor.id);
            s.bind(5, sessionId);
            s.bind(6, customerId);
            s.bind(7, orderId);
            s.bind(8, fiscalType);
            s.bind(9, ncf);
            s.bind(10, buyerDocument);
            s.bind(11, draft.totals.subtotal());
            s.bind(12, draft.totals.discount());
            s.bind(13, draft.totals.tax());
            s.bind(14, draft.totals.tip);
            s.bind(15, total);
            s.bind(16, summary.change());
          });

  for (std::size_t i = 0; i < draft.lines.size(); ++i) {
    const auto& line = draft.lines[i];
    const auto& totals = draft.totals.lines[i];
    execute(context.db, R"SQL(
      INSERT INTO sale_items (id, sale_id, position, product_id, description, unit_price_cents, quantity_milli,
                              tax_rate, discount_cents, net_cents, unit_cost_cents)
      VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
    )SQL",
            [&](db::Statement& s) {
              s.bind(1, newId());
              s.bind(2, saleId);
              s.bind(3, static_cast<std::int64_t>(i));
              s.bind(4, line.productId);
              s.bind(5, line.description);
              s.bind(6, line.unitPrice);
              s.bind(7, line.quantity);
              s.bind(8, domain::toString(line.taxRate));
              s.bind(9, totals.lineDiscount + totals.orderDiscount);
              s.bind(10, totals.net());
              s.bind(11, line.unitCost);
            });
  }

  for (std::size_t i = 0; i < payments.size(); ++i) {
    execute(context.db,
            "INSERT INTO sale_payments (id, sale_id, method, amount_cents, reference) VALUES (?1, ?2, ?3, ?4, ?5)",
            [&](db::Statement& s) {
              s.bind(1, newId());
              s.bind(2, saleId);
              s.bind(3, domain::toString(payments[i].method));
              s.bind(4, payments[i].amount);
              s.bind(5, references[i]);
            });
  }

  if (creditAmount > 0) {
    execute(context.db,
            "INSERT INTO credit_entries (id, customer_id, kind, amount_cents, sale_id, user_id) "
            "VALUES (?1, ?2, 'charge', ?3, ?4, ?5)",
            [&](db::Statement& s) {
              s.bind(1, newId());
              s.bind(2, *customerId);
              s.bind(3, creditAmount);
              s.bind(4, saleId);
              s.bind(5, actor.id);
            });
  }

  audit(context, "sale.complete", "sale", saleId, Json{{"number", number}, {"totalCents", total}});
  return saleDetail(context.db, saleId);
}

Json saleDetail(db::Database& db, const std::string& saleId) {
  const auto bindId = [&](db::Statement& s) { s.bind(1, saleId); };
  auto sale = requireOne(db, R"SQL(
    SELECT s.id, s.number, s.status, s.price_mode, s.created_at, s.subtotal_cents, s.discount_cents, s.tax_cents,
           s.tip_cents, s.delivery_fee_cents, s.total_cents, s.change_cents, s.fiscal_document_type, s.ncf,
           s.buyer_document_id, s.cash_session_id, s.order_id, s.cashier_id, u.name AS cashier_name,
           s.customer_id, c.name AS customer_name, s.voided_at, voider.name AS voided_by_name, s.void_reason
    FROM sales AS s
    JOIN users AS u ON u.id = s.cashier_id
    LEFT JOIN customers AS c ON c.id = s.customer_id
    LEFT JOIN users AS voider ON voider.id = s.voided_by
    WHERE s.id = ?1
  )SQL",
                         bindId, "La venta no existe");

  sale["items"] = queryAll(db, R"SQL(
    SELECT id, position, product_id, description, unit_price_cents, quantity_milli, tax_rate, discount_cents, net_cents
    FROM sale_items WHERE sale_id = ?1 ORDER BY position
  )SQL",
                           bindId);
  sale["payments"] =
      queryAll(db, "SELECT method, amount_cents, reference FROM sale_payments WHERE sale_id = ?1 ORDER BY rowid", bindId);
  const auto priceMode =
      domain::parsePriceMode(sale["priceMode"].get<std::string>()).value_or(domain::PriceMode::TaxIncluded);
  sale["taxGroups"] = storedTaxGroups(priceMode, sale["items"]);
  sale["business"] =
      queryOne(db, "SELECT name, rnc, address, phone, receipt_footer FROM business_profile WHERE id = 1").value_or(nullptr);
  return sale;
}

void registerSales(Registry& registry) {
  registry.add("sales.quote", {quote, true, roles::kFloor, false});
  registry.add("sales.complete", {complete, true, roles::kCash, true});
  registry.add("sales.get", {get, true, roles::kCash, false});
  registry.add("sales.list", {list, true, roles::kCash, false});
  registry.add("sales.void", {voidSale, true, roles::kManagers, true});
}

}  // namespace voxon::services
