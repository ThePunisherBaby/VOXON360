#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

// Criptografía mínima del motor, sin dependencias: hash del PIN y UUID.
namespace voxon::crypto {

using Digest = std::array<std::uint8_t, 32>;
using Bytes = std::vector<std::uint8_t>;

Digest sha256(std::string_view data);

Digest hmacSha256(std::string_view key, std::string_view message);

/// PBKDF2 con HMAC-SHA256 (RFC 8018).
Bytes pbkdf2HmacSha256(std::string_view password, std::string_view salt, std::uint32_t iterations,
                       std::size_t length);

/// Bytes aleatorios del sistema operativo.
Bytes randomBytes(std::size_t count);

std::string toHex(const std::uint8_t* data, std::size_t size);
inline std::string toHex(const Digest& digest) { return toHex(digest.data(), digest.size()); }
inline std::string toHex(const Bytes& bytes) { return toHex(bytes.data(), bytes.size()); }

/// Identificador aleatorio con formato UUID versión 4.
std::string uuidV4();

/// Compara sin revelar por el tiempo cuántos caracteres coinciden.
bool constantTimeEquals(std::string_view a, std::string_view b);

}  // namespace voxon::crypto
