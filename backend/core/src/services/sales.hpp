#pragma once

#include <optional>
#include <string>

#include "core/engine.hpp"
#include "core/json.hpp"
#include "core/params.hpp"

namespace voxon::services {

/// Cobra una venta con los parámetros de sales.complete. `orderId` la asocia
/// a una orden de restaurante. Devuelve el detalle para el recibo.
Json completeSale(Context& context, const Params& params, const std::optional<std::string>& orderId);

/// Venta con encabezado, líneas, pagos, desglose de ITBIS y datos del negocio.
Json saleDetail(db::Database& db, const std::string& saleId);

}  // namespace voxon::services
