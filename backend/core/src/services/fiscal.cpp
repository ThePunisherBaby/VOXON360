// Comprobantes fiscales locales: rangos NCF / e-NCF autorizados por la DGII y
// reportes del período para preparar los formatos 606 y 607.
//
// Esta versión funciona sin internet: el motor numera los comprobantes y deja
// los datos listos; el envío a la DGII lo hace el contador por su cuenta.

#include "services/fiscal.hpp"

#include <string>

#include "core/error.hpp"
#include "services/common.hpp"
#include "services/services.hpp"

namespace voxon::services {

namespace {

// Serie B: tipo + 8 dígitos (B0200000001). Serie E: tipo + 10 dígitos (E320000000001).
std::int64_t maxNumberFor(const std::string& documentType) {
  return documentType.front() == 'E' ? 9999999999LL : 99999999LL;
}

std::string formatNumber(const std::string& documentType, std::int64_t number) {
  const std::size_t digits = documentType.front() == 'E' ? 10 : 8;
  const auto text = std::to_string(number);
  return documentType + std::string(digits - text.size(), '0') + text;
}

Json listSequences(Context& context) {
  return queryAll(context.db, R"SQL(
    SELECT id, document_type, range_from, range_to, next_number, remaining, expires_on, expired, active
    FROM v_fiscal_sequence_status
    ORDER BY document_type, range_from
  )SQL");
}

Json addSequence(Context& context) {
  const auto& p = context.params;
  const auto type = p.requireEnum("documentType", {"B01", "B02", "B04", "B14", "B15", "E31", "E32", "E33", "E34"});
  const auto from = p.requireIntAtLeast("rangeFrom", 1);
  const auto to = p.requireIntAtLeast("rangeTo", from);
  if (to > maxNumberFor(type)) {
    invalidField("rangeTo", "excede los dígitos permitidos para " + type);
  }
  const auto expiresOn = p.optionalString("expiresOn", 10);
  if (expiresOn && !isIsoDate(*expiresOn)) {
    invalidField("expiresOn", "debe tener el formato AAAA-MM-DD");
  }

  const auto overlapping = queryInt(context.db, R"SQL(
    SELECT count(*) FROM fiscal_sequences
    WHERE document_type = ?1 AND NOT (range_to < ?2 OR range_from > ?3)
  )SQL",
                                    [&](db::Statement& s) {
                                      s.bind(1, type);
                                      s.bind(2, from);
                                      s.bind(3, to);
                                    });
  if (overlapping > 0) {
    throw ApiError(errc::kConflict, "El rango se cruza con otro rango " + type + " ya registrado");
  }

  const auto id = newId();
  execute(context.db, R"SQL(
    INSERT INTO fiscal_sequences (id, document_type, range_from, range_to, next_number, expires_on)
    VALUES (?1, ?2, ?3, ?4, ?3, ?5)
  )SQL",
          [&](db::Statement& s) {
            s.bind(1, id);
            s.bind(2, type);
            s.bind(3, from);
            s.bind(4, to);
            s.bind(5, expiresOn);
          });
  audit(context, "fiscal.sequenceAdded", "fiscal_sequence", id,
        Json{{"documentType", type}, {"rangeFrom", from}, {"rangeTo", to}});
  return requireOne(context.db, "SELECT * FROM v_fiscal_sequence_status WHERE id = ?1",
                    [&](db::Statement& s) { s.bind(1, id); }, "El rango no existe");
}

Json deactivateSequence(Context& context) {
  const auto id = context.params.requireString("id", 36);
  requireExists(context.db, "fiscal_sequences", id, "El rango no existe");
  execute(context.db, "UPDATE fiscal_sequences SET active = 0 WHERE id = ?1", [&](db::Statement& s) { s.bind(1, id); });
  audit(context, "fiscal.sequenceDeactivated", "fiscal_sequence", id);
  return requireOne(context.db, "SELECT * FROM v_fiscal_sequence_status WHERE id = ?1",
                    [&](db::Statement& s) { s.bind(1, id); }, "El rango no existe");
}

std::string requirePeriod(const Params& params) {
  const auto period = params.requireString("period", 7);
  if (!isIsoMonth(period)) {
    invalidField("period", "debe tener el formato AAAA-MM");
  }
  return period;
}

// Ventas con comprobante del período (base del 607) y las anuladas (608).
Json salesReport(Context& context) {
  const auto period = requirePeriod(context.params);
  const auto bindPeriod = [&](db::Statement& s) { s.bind(1, period); };
  Json result = Json::object();
  result["period"] = period;
  result["sales"] = queryAll(context.db, "SELECT * FROM v_fiscal_sales WHERE period = ?1 ORDER BY ncf", bindPeriod);
  result["totals"] = *queryOne(context.db, R"SQL(
    SELECT count(*) AS count, coalesce(sum(subtotal_cents), 0) AS subtotal_cents,
           coalesce(sum(tax_cents), 0) AS tax_cents, coalesce(sum(tip_cents), 0) AS tip_cents,
           coalesce(sum(total_cents), 0) AS total_cents
    FROM v_fiscal_sales WHERE period = ?1 AND status = 'completed'
  )SQL",
                               bindPeriod);
  return result;
}

// Compras del período para el formato 606.
Json purchasesReport(Context& context) {
  const auto period = requirePeriod(context.params);
  const auto bindPeriod = [&](db::Statement& s) { s.bind(1, period); };
  Json result = Json::object();
  result["period"] = period;
  result["purchases"] =
      queryAll(context.db, "SELECT * FROM v_purchases_606 WHERE period = ?1 ORDER BY invoice_date", bindPeriod);
  result["totals"] = *queryOne(context.db, R"SQL(
    SELECT count(*) AS count, coalesce(sum(subtotal_cents), 0) AS subtotal_cents,
           coalesce(sum(tax_cents), 0) AS tax_cents, coalesce(sum(total_cents), 0) AS total_cents
    FROM v_purchases_606 WHERE period = ?1
  )SQL",
                               bindPeriod);
  return result;
}

}  // namespace

std::string assignFiscalNumber(db::Database& db, const std::string& documentType) {
  std::string sequenceId;
  std::int64_t number = 0;
  {
    auto statement = db.prepare(R"SQL(
      SELECT id, next_number FROM fiscal_sequences
      WHERE document_type = ?1 AND active = 1 AND next_number <= range_to
        AND (expires_on IS NULL OR expires_on >= date('now', '-4 hours'))
      ORDER BY range_from
      LIMIT 1
    )SQL");
    statement.bind(1, documentType);
    if (!statement.step()) {
      throw ApiError(errc::kFiscalSequenceExhausted,
                     "No quedan comprobantes " + documentType + " vigentes; registra un rango autorizado por la DGII");
    }
    sequenceId = statement.getText(0);
    number = statement.getInt(1);
  }
  execute(db, "UPDATE fiscal_sequences SET next_number = next_number + 1 WHERE id = ?1",
          [&](db::Statement& s) { s.bind(1, sequenceId); });
  return formatNumber(documentType, number);
}

void registerFiscal(Registry& registry) {
  registry.add("fiscal.sequences.list", {listSequences, true, roles::kManagers, false});
  registry.add("fiscal.sequences.add", {addSequence, true, roles::kOwner, true});
  registry.add("fiscal.sequences.deactivate", {deactivateSequence, true, roles::kOwner, true});
  registry.add("fiscal.salesReport", {salesReport, true, roles::kManagers, false});
  registry.add("fiscal.purchasesReport", {purchasesReport, true, roles::kManagers, false});
}

}  // namespace voxon::services
