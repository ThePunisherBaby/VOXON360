#pragma once

#include <string>

#include "core/engine.hpp"
#include "core/json.hpp"

namespace voxon::services {

/// Crea un empleado con PIN de 4 a 6 dígitos que no use nadie más.
/// Devuelve {id, name, role, active}.
Json createUser(const Context& context, const std::string& name, Role role, const std::string& pin);

}  // namespace voxon::services
