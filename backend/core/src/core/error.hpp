#pragma once

#include <stdexcept>
#include <string>
#include <utility>

namespace voxon {

// Códigos estables que ven los clientes (app, servidor Java, web).
namespace errc {
inline constexpr const char* kInvalidRequest = "invalid_request";
inline constexpr const char* kUnknownMethod = "unknown_method";
inline constexpr const char* kValidation = "validation_failed";
inline constexpr const char* kNotFound = "not_found";
inline constexpr const char* kUnauthorized = "unauthorized";
inline constexpr const char* kForbidden = "forbidden";
inline constexpr const char* kConflict = "conflict";
inline constexpr const char* kNotConfigured = "not_configured";
inline constexpr const char* kAlreadyConfigured = "already_configured";
inline constexpr const char* kCashSessionClosed = "cash_session_closed";
inline constexpr const char* kCashSessionOpen = "cash_session_already_open";
inline constexpr const char* kInsufficientPayment = "insufficient_payment";
inline constexpr const char* kFiscalSequenceExhausted = "fiscal_sequence_exhausted";
inline constexpr const char* kDatabase = "database_error";
inline constexpr const char* kInternal = "internal_error";
}  // namespace errc

/// Error con un código estable que la API devuelve tal cual.
class ApiError : public std::runtime_error {
 public:
  ApiError(std::string code, const std::string& message)
      : std::runtime_error(message), code_(std::move(code)) {}

  const std::string& code() const noexcept { return code_; }

 private:
  std::string code_;
};

}  // namespace voxon
