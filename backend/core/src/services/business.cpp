#include "core/error.hpp"
#include "services/common.hpp"
#include "services/services.hpp"
#include "services/users.hpp"

namespace voxon::services {

namespace {

constexpr const char* kSelectBusiness =
    "SELECT name, business_type, rnc, address, phone, price_mode, legal_tip_enabled, receipt_footer, "
    "created_at, updated_at FROM business_profile WHERE id = 1";

std::optional<Json> currentBusiness(db::Database& db) { return queryOne(db, kSelectBusiness); }

Json status(Context& context) {
  auto business = currentBusiness(context.db);
  Json result = Json::object();
  result["configured"] = business.has_value();
  result["business"] = business ? std::move(*business) : Json(nullptr);
  result["hasUsers"] = queryInt(context.db, "SELECT count(*) FROM users WHERE active = 1") > 0;
  return result;
}

// Primer uso: datos del negocio y el dueño, todo o nada.
Json setup(Context& context) {
  if (currentBusiness(context.db)) {
    throw ApiError(errc::kAlreadyConfigured, "El negocio ya está configurado");
  }
  const auto business = context.params.object("business");
  const auto owner = context.params.object("owner");

  const auto name = business.requireString("name", 80);
  const auto type = business.requireEnum("businessType", {"colmado", "store", "restaurant"});
  const bool isRestaurant = type == "restaurant";
  const auto priceMode = business.optionalEnum("priceMode", {"tax_included", "tax_excluded"})
                             .value_or(isRestaurant ? "tax_excluded" : "tax_included");
  const bool legalTip = business.boolOr("legalTipEnabled", isRestaurant);

  execute(context.db,
          "INSERT INTO business_profile (id, name, business_type, rnc, address, phone, price_mode, "
          "legal_tip_enabled, receipt_footer) VALUES (1, ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)",
          [&](db::Statement& s) {
            s.bind(1, name);
            s.bind(2, type);
            s.bind(3, optionalDocumentId(business, "rnc"));
            s.bind(4, business.optionalString("address", 200));
            s.bind(5, business.optionalString("phone", 30));
            s.bind(6, priceMode);
            s.bind(7, legalTip ? 1 : 0);
            s.bind(8, business.optionalString("receiptFooter", 200));
          });

  const auto ownerUser = createUser(context, owner.requireString("name", 60), Role::Owner,
                                    owner.requireString("pin", 6));
  audit(context, "business.setup", "business", "1", Json{{"name", name}, {"businessType", type}});

  Json result = Json::object();
  result["business"] = *currentBusiness(context.db);
  result["owner"] = ownerUser;
  return result;
}

Json get(Context& context) {
  auto business = currentBusiness(context.db);
  if (!business) {
    throw ApiError(errc::kNotConfigured, "El negocio aún no está configurado");
  }
  return std::move(*business);
}

// Actualiza solo los campos enviados; null borra los opcionales.
Json update(Context& context) {
  auto current = currentBusiness(context.db);
  if (!current) {
    throw ApiError(errc::kNotConfigured, "El negocio aún no está configurado");
  }
  const auto& p = context.params;
  auto textOrCurrent = [&](const char* key, const char* column, std::size_t max) -> std::optional<std::string> {
    if (!p.contains(key)) {
      const auto& value = (*current)[column];
      return value.is_null() ? std::nullopt : std::optional<std::string>(value.get<std::string>());
    }
    return p.optionalString(key, max);
  };

  const auto name = p.contains("name") ? p.requireString("name", 80) : (*current)["name"].get<std::string>();
  const auto type = p.optionalEnum("businessType", {"colmado", "store", "restaurant"})
                        .value_or((*current)["businessType"].get<std::string>());
  const auto priceMode = p.optionalEnum("priceMode", {"tax_included", "tax_excluded"})
                             .value_or((*current)["priceMode"].get<std::string>());
  const bool legalTip = p.boolOr("legalTipEnabled", (*current)["legalTipEnabled"].get<bool>());
  const auto rnc = p.contains("rnc") ? optionalDocumentId(p, "rnc") : textOrCurrent("rnc", "rnc", 11);

  execute(context.db,
          "UPDATE business_profile SET name = ?1, business_type = ?2, rnc = ?3, address = ?4, phone = ?5, "
          "price_mode = ?6, legal_tip_enabled = ?7, receipt_footer = ?8 WHERE id = 1",
          [&](db::Statement& s) {
            s.bind(1, name);
            s.bind(2, type);
            s.bind(3, rnc);
            s.bind(4, textOrCurrent("address", "address", 200));
            s.bind(5, textOrCurrent("phone", "phone", 30));
            s.bind(6, priceMode);
            s.bind(7, legalTip ? 1 : 0);
            s.bind(8, textOrCurrent("receiptFooter", "receiptFooter", 200));
          });
  audit(context, "business.update", "business", "1");
  return *currentBusiness(context.db);
}

}  // namespace

void registerBusiness(Registry& registry) {
  registry.add("business.status", {status, /*requiresActor=*/false, {}, /*writes=*/false});
  registry.add("business.setup", {setup, false, {}, true});
  registry.add("business.get", {get, true, {}, false});
  registry.add("business.update", {update, true, roles::kOwner, true});
}

}  // namespace voxon::services
