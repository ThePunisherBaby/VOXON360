#pragma once

#include <nlohmann/json.hpp>

namespace voxon {

// Se usa json ordenado para que las respuestas conserven el orden de los campos.
using Json = nlohmann::ordered_json;

}  // namespace voxon
