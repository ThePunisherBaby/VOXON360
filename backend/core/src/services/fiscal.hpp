#pragma once

#include <string>

#include "db/sqlite.hpp"

namespace voxon::services {

/// Toma el siguiente número del rango autorizado vigente para `documentType`
/// y lo devuelve formateado: "B0200000001" (NCF) o "E320000000001" (e-NCF).
/// Lanza fiscal_sequence_exhausted si no quedan números vigentes.
std::string assignFiscalNumber(db::Database& db, const std::string& documentType);

}  // namespace voxon::services
