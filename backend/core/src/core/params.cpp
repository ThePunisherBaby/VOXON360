#include "core/params.hpp"

#include <utility>

#include "core/error.hpp"
#include "text/text.hpp"

namespace voxon {

namespace {

const Json& emptyObject() {
  static const Json empty = Json::object();
  return empty;
}

std::string joinAllowed(std::initializer_list<std::string_view> allowed) {
  std::string joined;
  for (const auto value : allowed) {
    if (!joined.empty()) {
      joined += ", ";
    }
    joined += value;
  }
  return joined;
}

}  // namespace

void invalidField(const std::string& field, const std::string& reason) {
  throw ApiError(errc::kValidation, "El campo '" + field + "' " + reason);
}

Params::Params(const Json& json, std::string prefix)
    : json_(json.is_object() ? &json : &emptyObject()), prefix_(std::move(prefix)) {}

std::string Params::field(std::string_view key) const {
  return prefix_.empty() ? std::string(key) : prefix_ + "." + std::string(key);
}

const Json* Params::find(std::string_view key) const {
  const auto it = json_->find(key);
  if (it == json_->end() || it->is_null()) {
    return nullptr;
  }
  return &*it;
}

bool Params::has(std::string_view key) const { return find(key) != nullptr; }

bool Params::contains(std::string_view key) const { return json_->contains(key); }

std::string Params::requireString(std::string_view key, std::size_t maxLength) const {
  auto value = optionalString(key, maxLength);
  if (!value) {
    invalidField(field(key), "es obligatorio");
  }
  return *value;
}

std::optional<std::string> Params::optionalString(std::string_view key, std::size_t maxLength) const {
  const auto* value = find(key);
  if (value == nullptr) {
    return std::nullopt;
  }
  if (!value->is_string()) {
    invalidField(field(key), "debe ser texto");
  }
  auto trimmed = text::trim(value->get<std::string>());
  if (trimmed.empty()) {
    return std::nullopt;
  }
  if (text::utf8Length(trimmed) > maxLength) {
    invalidField(field(key), "admite máximo " + std::to_string(maxLength) + " caracteres");
  }
  return trimmed;
}

std::int64_t Params::requireInt(std::string_view key) const {
  auto value = optionalInt(key);
  if (!value) {
    invalidField(field(key), "es obligatorio");
  }
  return *value;
}

std::optional<std::int64_t> Params::optionalInt(std::string_view key) const {
  const auto* value = find(key);
  if (value == nullptr) {
    return std::nullopt;
  }
  if (value->is_number_integer()) {
    if (value->is_number_unsigned() && value->get<std::uint64_t>() > static_cast<std::uint64_t>(INT64_MAX)) {
      invalidField(field(key), "es demasiado grande");
    }
    return value->get<std::int64_t>();
  }
  // Montos y cantidades siempre son enteros (centavos, milésimas).
  invalidField(field(key), "debe ser un número entero");
}

std::int64_t Params::intOr(std::string_view key, std::int64_t fallback) const {
  return optionalInt(key).value_or(fallback);
}

std::int64_t Params::requireIntAtLeast(std::string_view key, std::int64_t min) const {
  const auto value = requireInt(key);
  if (value < min) {
    invalidField(field(key), "debe ser mayor o igual que " + std::to_string(min));
  }
  return value;
}

bool Params::boolOr(std::string_view key, bool fallback) const {
  const auto* value = find(key);
  if (value == nullptr) {
    return fallback;
  }
  if (!value->is_boolean()) {
    invalidField(field(key), "debe ser true o false");
  }
  return value->get<bool>();
}

std::string Params::requireEnum(std::string_view key, std::initializer_list<std::string_view> allowed) const {
  auto value = optionalEnum(key, allowed);
  if (!value) {
    invalidField(field(key), "es obligatorio (" + joinAllowed(allowed) + ")");
  }
  return *value;
}

std::optional<std::string> Params::optionalEnum(std::string_view key,
                                                std::initializer_list<std::string_view> allowed) const {
  auto value = optionalString(key, 40);
  if (!value) {
    return std::nullopt;
  }
  for (const auto option : allowed) {
    if (*value == option) {
      return value;
    }
  }
  invalidField(field(key), "debe ser uno de: " + joinAllowed(allowed));
}

const Json& Params::requireArray(std::string_view key, bool allowEmpty) const {
  const auto* value = find(key);
  if (value == nullptr || !value->is_array()) {
    invalidField(field(key), "debe ser una lista");
  }
  if (!allowEmpty && value->empty()) {
    invalidField(field(key), "no puede estar vacío");
  }
  return *value;
}

Params Params::object(std::string_view key) const {
  const auto* value = find(key);
  if (value == nullptr) {
    return Params(emptyObject(), field(key));
  }
  if (!value->is_object()) {
    invalidField(field(key), "debe ser un objeto");
  }
  return Params(*value, field(key));
}

}  // namespace voxon
