#include <algorithm>
#include <string>

#include "core/error.hpp"
#include "services/common.hpp"
#include "services/services.hpp"
#include "text/text.hpp"

namespace voxon::services {

namespace {

constexpr const char* kSelectProducts = R"SQL(
SELECT p.id, p.name, p.category_id, c.name AS category_name, p.barcode, p.price_cents,
       p.wholesale_price_cents, p.cost_cents, p.tax_rate, p.unit, p.allows_fraction, p.track_stock,
       p.stock_milli, p.min_stock_milli, p.stock_source_id, p.stock_factor_milli, p.station, p.active,
       CASE WHEN p.stock_source_id IS NULL THEN p.stock_milli
            ELSE (base.stock_milli * 1000) / p.stock_factor_milli END AS available_milli,
       p.created_at, p.updated_at
FROM products AS p
LEFT JOIN categories AS c ON c.id = p.category_id
LEFT JOIN products AS base ON base.id = p.stock_source_id
)SQL";

constexpr const char* kSelectCategory = "SELECT id, name, sort_order, active FROM categories WHERE id = ?1";

std::optional<std::string> textOf(const Json& value) {
  return value.is_null() ? std::nullopt : std::optional<std::string>(value.get<std::string>());
}

std::optional<std::int64_t> intOf(const Json& value) {
  return value.is_null() ? std::nullopt : std::optional<std::int64_t>(value.get<std::int64_t>());
}

Json productById(db::Database& db, const std::string& id) {
  return requireOne(db, std::string(kSelectProducts) + " WHERE p.id = ?1", [&](db::Statement& s) { s.bind(1, id); },
                    "El producto no existe");
}

Json categoryById(db::Database& db, const std::string& id) {
  return requireOne(db, kSelectCategory, [&](db::Statement& s) { s.bind(1, id); }, "La categoría no existe");
}

std::int64_t nonNegative(const Params& params, const char* key, std::int64_t fallback) {
  const auto value = params.intOr(key, fallback);
  if (value < 0) {
    invalidField(params.field(key), "no puede ser negativo");
  }
  return value;
}

void ensureBarcodeFree(db::Database& db, const std::string& barcode, const std::string* excludeId) {
  const auto used = queryInt(db, "SELECT count(*) FROM products WHERE barcode = ?1 AND id IS NOT ?2",
                             [&](db::Statement& s) {
                               s.bind(1, barcode);
                               if (excludeId != nullptr) {
                                 s.bind(2, *excludeId);
                               } else {
                                 s.bind(2, std::nullopt);
                               }
                             });
  if (used > 0) {
    throw ApiError(errc::kConflict, "Ya existe un producto con el código de barras " + barcode);
  }
}

// El producto base de una presentación al detalle debe existir y no ser a su vez una presentación.
void validateStockSource(db::Database& db, const std::string& sourceId, const std::string* productId) {
  if (productId != nullptr && sourceId == *productId) {
    invalidField("stockSourceId", "no puede ser el mismo producto");
  }
  auto statement = db.prepare("SELECT stock_source_id FROM products WHERE id = ?1 AND active = 1");
  statement.bind(1, sourceId);
  if (!statement.step()) {
    throw ApiError(errc::kNotFound, "El producto base no existe");
  }
  if (!statement.isNull(0)) {
    invalidField("stockSourceId", "debe ser un producto base, no otra presentación al detalle");
  }
}

void ensureCategoryNameFree(db::Database& db, const std::string& name, const std::string* excludeId) {
  const auto used =
      queryInt(db, "SELECT count(*) FROM categories WHERE lower(name) = lower(?1) AND active = 1 AND id IS NOT ?2",
               [&](db::Statement& s) {
                 s.bind(1, name);
                 if (excludeId != nullptr) {
                   s.bind(2, *excludeId);
                 } else {
                   s.bind(2, std::nullopt);
                 }
               });
  if (used > 0) {
    throw ApiError(errc::kConflict, "Ya existe la categoría " + name);
  }
}

// --- Categorías ---------------------------------------------------------------

Json listCategories(Context& context) {
  const bool includeInactive = context.params.boolOr("includeInactive", false);
  return queryAll(context.db, std::string("SELECT id, name, sort_order, active FROM categories") +
                                  (includeInactive ? "" : " WHERE active = 1") +
                                  " ORDER BY sort_order, name COLLATE NOCASE");
}

Json createCategory(Context& context) {
  const auto id = newId();
  const auto name = context.params.requireString("name", 40);
  ensureCategoryNameFree(context.db, name, nullptr);
  execute(context.db, "INSERT INTO categories (id, name, sort_order) VALUES (?1, ?2, ?3)", [&](db::Statement& s) {
    s.bind(1, id);
    s.bind(2, name);
    s.bind(3, context.params.intOr("sortOrder", 0));
  });
  audit(context, "category.create", "category", id, Json{{"name", name}});
  return categoryById(context.db, id);
}

Json updateCategory(Context& context) {
  const auto id = context.params.requireString("id", 36);
  const auto current = categoryById(context.db, id);
  const auto name = context.params.has("name") ? context.params.requireString("name", 40)
                                               : current["name"].get<std::string>();
  const bool active = context.params.boolOr("active", current["active"].get<bool>());
  if (active) {
    ensureCategoryNameFree(context.db, name, &id);
  }
  execute(context.db, "UPDATE categories SET name = ?1, sort_order = ?2, active = ?3 WHERE id = ?4",
          [&](db::Statement& s) {
            s.bind(1, name);
            s.bind(2, context.params.intOr("sortOrder", current["sortOrder"].get<std::int64_t>()));
            s.bind(3, active ? 1 : 0);
            s.bind(4, id);
          });
  audit(context, "category.update", "category", id);
  return categoryById(context.db, id);
}

// --- Productos ----------------------------------------------------------------

Json listProducts(Context& context) {
  const auto& p = context.params;
  const auto search = p.optionalString("search", 80);
  const auto categoryId = p.optionalString("categoryId", 36);
  const auto limit = std::clamp<std::int64_t>(p.intOr("limit", 200), 1, 1000);
  const auto offset = std::max<std::int64_t>(p.intOr("offset", 0), 0);

  std::string sql = std::string(kSelectProducts) + " WHERE 1 = 1";
  if (!p.boolOr("includeInactive", false)) {
    sql += " AND p.active = 1";
  }
  if (search) {
    sql += " AND (p.search_name LIKE ?1 ESCAPE '\\' OR p.barcode = ?2)";
  }
  if (categoryId) {
    sql += " AND p.category_id = ?3";
  }
  sql += " ORDER BY p.name COLLATE NOCASE LIMIT ?4 OFFSET ?5";

  return queryAll(context.db, sql, [&](db::Statement& s) {
    if (search) {
      s.bind(1, likePattern(text::normalizeForSearch(*search)));
      s.bind(2, *search);
    }
    if (categoryId) {
      s.bind(3, *categoryId);
    }
    s.bind(4, limit);
    s.bind(5, offset);
  });
}

Json getProduct(Context& context) {
  if (const auto barcode = context.params.optionalString("barcode", 64)) {
    return requireOne(context.db, std::string(kSelectProducts) + " WHERE p.barcode = ?1 AND p.active = 1",
                      [&](db::Statement& s) { s.bind(1, *barcode); }, "No hay un producto con el código " + *barcode);
  }
  return productById(context.db, context.params.requireString("id", 36));
}

Json createProduct(Context& context) {
  const auto& p = context.params;
  const auto& actor = context.requireActor();
  const auto id = newId();
  const auto name = p.requireString("name", 80);
  const auto price = p.requireIntAtLeast("priceCents", 0);
  const auto taxRate = p.requireEnum("taxRate", {"exempt", "reduced", "standard"});
  const auto unit = p.optionalEnum("unit", {"unit", "pound", "kilogram", "ounce", "liter"}).value_or("unit");
  const bool allowsFraction = p.boolOr("allowsFraction", unit != "unit");
  const bool trackStock = p.boolOr("trackStock", true);
  const auto station = p.optionalEnum("station", {"none", "kitchen", "bar"}).value_or("none");
  const auto cost = nonNegative(p, "costCents", 0);
  const auto minStock = nonNegative(p, "minStockMilli", 0);
  const auto initialStock = nonNegative(p, "initialStockMilli", 0);
  const auto wholesale = p.optionalInt("wholesalePriceCents");
  if (wholesale && *wholesale < 0) {
    invalidField("wholesalePriceCents", "no puede ser negativo");
  }

  const auto categoryId = p.optionalString("categoryId", 36);
  if (categoryId) {
    requireExists(context.db, "categories", *categoryId, "La categoría no existe");
  }
  const auto barcode = p.optionalString("barcode", 64);
  if (barcode) {
    ensureBarcodeFree(context.db, *barcode, nullptr);
  }
  const auto stockSource = p.optionalString("stockSourceId", 36);
  const auto factor = p.intOr("stockFactorMilli", 1000);
  if (factor <= 0) {
    invalidField("stockFactorMilli", "debe ser mayor que cero");
  }
  if (stockSource) {
    validateStockSource(context.db, *stockSource, nullptr);
    if (initialStock > 0) {
      invalidField("initialStockMilli", "la existencia de una presentación al detalle se lleva en el producto base");
    }
  }

  execute(context.db, R"SQL(
    INSERT INTO products (id, category_id, name, search_name, barcode, price_cents, wholesale_price_cents,
                          cost_cents, tax_rate, unit, allows_fraction, track_stock, min_stock_milli,
                          stock_source_id, stock_factor_milli, station)
    VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16)
  )SQL",
          [&](db::Statement& s) {
            s.bind(1, id);
            s.bind(2, categoryId);
            s.bind(3, name);
            s.bind(4, text::normalizeForSearch(name));
            s.bind(5, barcode);
            s.bind(6, price);
            s.bind(7, wholesale);
            s.bind(8, cost);
            s.bind(9, taxRate);
            s.bind(10, unit);
            s.bind(11, allowsFraction ? 1 : 0);
            s.bind(12, trackStock ? 1 : 0);
            s.bind(13, minStock);
            s.bind(14, stockSource);
            s.bind(15, factor);
            s.bind(16, station);
          });

  if (initialStock > 0) {
    execute(context.db,
            "INSERT INTO stock_movements (product_id, kind, quantity_milli, unit_cost_cents, note, user_id) "
            "VALUES (?1, 'adjustment', ?2, ?3, 'Existencia inicial', ?4)",
            [&](db::Statement& s) {
              s.bind(1, id);
              s.bind(2, initialStock);
              s.bind(3, cost);
              s.bind(4, actor.id);
            });
  }
  audit(context, "product.create", "product", id, Json{{"name", name}, {"priceCents", price}});
  return productById(context.db, id);
}

// Solo cambia los campos enviados; null borra los opcionales.
Json updateProduct(Context& context) {
  const auto& p = context.params;
  const auto id = p.requireString("id", 36);
  const auto current = productById(context.db, id);

  const auto name = p.has("name") ? p.requireString("name", 80) : current["name"].get<std::string>();
  const auto price = p.has("priceCents") ? p.requireIntAtLeast("priceCents", 0)
                                         : current["priceCents"].get<std::int64_t>();
  const auto taxRate = p.optionalEnum("taxRate", {"exempt", "reduced", "standard"})
                           .value_or(current["taxRate"].get<std::string>());
  const auto unit = p.optionalEnum("unit", {"unit", "pound", "kilogram", "ounce", "liter"})
                        .value_or(current["unit"].get<std::string>());
  const auto station = p.optionalEnum("station", {"none", "kitchen", "bar"})
                           .value_or(current["station"].get<std::string>());
  const bool allowsFraction = p.boolOr("allowsFraction", current["allowsFraction"].get<bool>());
  const bool trackStock = p.boolOr("trackStock", current["trackStock"].get<bool>());
  const bool active = p.boolOr("active", current["active"].get<bool>());
  const auto cost = nonNegative(p, "costCents", current["costCents"].get<std::int64_t>());
  const auto minStock = nonNegative(p, "minStockMilli", current["minStockMilli"].get<std::int64_t>());
  const auto factor = p.intOr("stockFactorMilli", current["stockFactorMilli"].get<std::int64_t>());
  if (factor <= 0) {
    invalidField("stockFactorMilli", "debe ser mayor que cero");
  }

  auto categoryId = textOf(current["categoryId"]);
  if (p.contains("categoryId")) {
    categoryId = p.optionalString("categoryId", 36);
    if (categoryId) {
      requireExists(context.db, "categories", *categoryId, "La categoría no existe");
    }
  }
  auto barcode = textOf(current["barcode"]);
  if (p.contains("barcode")) {
    barcode = p.optionalString("barcode", 64);
    if (barcode) {
      ensureBarcodeFree(context.db, *barcode, &id);
    }
  }
  auto wholesale = intOf(current["wholesalePriceCents"]);
  if (p.contains("wholesalePriceCents")) {
    wholesale = p.optionalInt("wholesalePriceCents");
    if (wholesale && *wholesale < 0) {
      invalidField("wholesalePriceCents", "no puede ser negativo");
    }
  }
  auto stockSource = textOf(current["stockSourceId"]);
  if (p.contains("stockSourceId")) {
    stockSource = p.optionalString("stockSourceId", 36);
    if (stockSource) {
      validateStockSource(context.db, *stockSource, &id);
    }
  }

  execute(context.db, R"SQL(
    UPDATE products SET category_id = ?1, name = ?2, search_name = ?3, barcode = ?4, price_cents = ?5,
                        wholesale_price_cents = ?6, cost_cents = ?7, tax_rate = ?8, unit = ?9,
                        allows_fraction = ?10, track_stock = ?11, min_stock_milli = ?12,
                        stock_source_id = ?13, stock_factor_milli = ?14, station = ?15, active = ?16
    WHERE id = ?17
  )SQL",
          [&](db::Statement& s) {
            s.bind(1, categoryId);
            s.bind(2, name);
            s.bind(3, text::normalizeForSearch(name));
            s.bind(4, barcode);
            s.bind(5, price);
            s.bind(6, wholesale);
            s.bind(7, cost);
            s.bind(8, taxRate);
            s.bind(9, unit);
            s.bind(10, allowsFraction ? 1 : 0);
            s.bind(11, trackStock ? 1 : 0);
            s.bind(12, minStock);
            s.bind(13, stockSource);
            s.bind(14, factor);
            s.bind(15, station);
            s.bind(16, active ? 1 : 0);
            s.bind(17, id);
          });

  const auto previousPrice = current["priceCents"].get<std::int64_t>();
  if (price != previousPrice) {
    audit(context, "product.priceChanged", "product", id, Json{{"fromCents", previousPrice}, {"toCents", price}});
  }
  audit(context, "product.update", "product", id);
  return productById(context.db, id);
}

Json deactivateProduct(Context& context) {
  const auto id = context.params.requireString("id", 36);
  productById(context.db, id);
  execute(context.db, "UPDATE products SET active = 0 WHERE id = ?1", [&](db::Statement& s) { s.bind(1, id); });
  audit(context, "product.deactivate", "product", id);
  return productById(context.db, id);
}

}  // namespace

void registerCatalog(Registry& registry) {
  registry.add("catalog.categories.list", {listCategories, true, {}, false});
  registry.add("catalog.categories.create", {createCategory, true, roles::kManagers, true});
  registry.add("catalog.categories.update", {updateCategory, true, roles::kManagers, true});
  registry.add("catalog.products.list", {listProducts, true, {}, false});
  registry.add("catalog.products.get", {getProduct, true, {}, false});
  registry.add("catalog.products.create", {createProduct, true, roles::kManagers, true});
  registry.add("catalog.products.update", {updateProduct, true, roles::kManagers, true});
  registry.add("catalog.products.deactivate", {deactivateProduct, true, roles::kManagers, true});
}

}  // namespace voxon::services
