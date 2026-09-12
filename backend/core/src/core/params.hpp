#pragma once

#include <cstdint>
#include <initializer_list>
#include <optional>
#include <string>
#include <string_view>

#include "core/json.hpp"

namespace voxon {

/// Lectura validada de los parámetros de una solicitud. Cualquier dato
/// inválido se informa como validation_failed indicando el campo.
class Params {
 public:
  /// `json` debe ser un objeto; null se trata como objeto vacío.
  explicit Params(const Json& json, std::string prefix = "");

  /// true si el campo trae un valor distinto de null.
  bool has(std::string_view key) const;

  /// true si el campo viene en la solicitud, aunque sea null.
  bool contains(std::string_view key) const;

  /// Texto obligatorio, sin espacios sobrantes y no vacío.
  std::string requireString(std::string_view key, std::size_t maxLength = 200) const;

  /// Texto opcional: ausente, null o vacío devuelven nullopt.
  std::optional<std::string> optionalString(std::string_view key, std::size_t maxLength = 200) const;

  std::int64_t requireInt(std::string_view key) const;
  std::optional<std::int64_t> optionalInt(std::string_view key) const;
  std::int64_t intOr(std::string_view key, std::int64_t fallback) const;

  /// Entero mayor o igual que `min`.
  std::int64_t requireIntAtLeast(std::string_view key, std::int64_t min) const;

  bool boolOr(std::string_view key, bool fallback) const;

  std::string requireEnum(std::string_view key, std::initializer_list<std::string_view> allowed) const;
  std::optional<std::string> optionalEnum(std::string_view key,
                                          std::initializer_list<std::string_view> allowed) const;

  /// Arreglo obligatorio (puede estar vacío si `allowEmpty`).
  const Json& requireArray(std::string_view key, bool allowEmpty = false) const;

  /// Objeto anidado; ausente o null devuelve un objeto vacío.
  Params object(std::string_view key) const;

  /// Nombre completo del campo para mensajes, p. ej. "lines[2].quantityMilli".
  std::string field(std::string_view key) const;

 private:
  const Json* find(std::string_view key) const;

  const Json* json_;
  std::string prefix_;
};

/// Lanza validation_failed para `field` con el motivo dado.
[[noreturn]] void invalidField(const std::string& field, const std::string& reason);

}  // namespace voxon
