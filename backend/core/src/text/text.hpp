#pragma once

#include <cstddef>
#include <string>
#include <string_view>

namespace voxon::text {

/// Quita espacios en blanco al inicio y al final.
std::string trim(std::string_view value);

/// Minúsculas, sin acentos y con espacios simples, para que "cafe" encuentre
/// "Café" y "pina" encuentre "Piña". Igual que normalizeForSearch de la app.
std::string normalizeForSearch(std::string_view value);

/// true si no está vacío y todos sus caracteres son dígitos ASCII.
bool isDigits(std::string_view value);

/// Cantidad de caracteres de un texto UTF-8 (no de bytes).
std::size_t utf8Length(std::string_view value);

}  // namespace voxon::text
