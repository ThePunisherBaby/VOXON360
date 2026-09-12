#include "crypto/crypto.hpp"

#include <random>

namespace voxon::crypto {

namespace {

constexpr std::array<std::uint32_t, 64> kRoundConstants = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2};

inline std::uint32_t rotr(std::uint32_t x, int n) {
  return (x >> n) | (x << (32 - n));
}

class Sha256 {
 public:
  void update(const std::uint8_t* data, std::size_t size) {
    for (std::size_t i = 0; i < size; ++i) {
      buffer_[bufferSize_++] = data[i];
      if (bufferSize_ == buffer_.size()) {
        transform(buffer_.data());
        bufferSize_ = 0;
      }
    }
    totalBytes_ += size;
  }

  void update(std::string_view data) { update(reinterpret_cast<const std::uint8_t*>(data.data()), data.size()); }

  Digest finish() {
    const std::uint64_t totalBits = totalBytes_ * 8;
    const std::uint8_t one = 0x80;
    const std::uint8_t zero = 0x00;
    update(&one, 1);
    while (bufferSize_ != 56) {
      update(&zero, 1);
    }
    std::array<std::uint8_t, 8> length{};
    for (int i = 0; i < 8; ++i) {
      length[static_cast<std::size_t>(i)] = static_cast<std::uint8_t>(totalBits >> (56 - 8 * i));
    }
    update(length.data(), length.size());

    Digest digest{};
    for (std::size_t i = 0; i < 8; ++i) {
      for (std::size_t j = 0; j < 4; ++j) {
        digest[i * 4 + j] = static_cast<std::uint8_t>(state_[i] >> (24 - 8 * j));
      }
    }
    return digest;
  }

 private:
  void transform(const std::uint8_t* block) {
    std::array<std::uint32_t, 64> w{};
    for (std::size_t i = 0; i < 16; ++i) {
      w[i] = (static_cast<std::uint32_t>(block[i * 4]) << 24) | (static_cast<std::uint32_t>(block[i * 4 + 1]) << 16) |
             (static_cast<std::uint32_t>(block[i * 4 + 2]) << 8) | static_cast<std::uint32_t>(block[i * 4 + 3]);
    }
    for (std::size_t i = 16; i < 64; ++i) {
      const std::uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      const std::uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }

    std::uint32_t a = state_[0], b = state_[1], c = state_[2], d = state_[3];
    std::uint32_t e = state_[4], f = state_[5], g = state_[6], h = state_[7];
    for (std::size_t i = 0; i < 64; ++i) {
      const std::uint32_t t1 =
          h + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + kRoundConstants[i] + w[i];
      const std::uint32_t t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
      h = g;
      g = f;
      f = e;
      e = d + t1;
      d = c;
      c = b;
      b = a;
      a = t1 + t2;
    }
    state_[0] += a;
    state_[1] += b;
    state_[2] += c;
    state_[3] += d;
    state_[4] += e;
    state_[5] += f;
    state_[6] += g;
    state_[7] += h;
  }

  std::array<std::uint32_t, 8> state_ = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                                         0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19};
  std::array<std::uint8_t, 64> buffer_{};
  std::size_t bufferSize_ = 0;
  std::uint64_t totalBytes_ = 0;
};

std::string_view asView(const Digest& digest) {
  return {reinterpret_cast<const char*>(digest.data()), digest.size()};
}

}  // namespace

Digest sha256(std::string_view data) {
  Sha256 hash;
  hash.update(data);
  return hash.finish();
}

Digest hmacSha256(std::string_view key, std::string_view message) {
  std::array<std::uint8_t, 64> block{};
  if (key.size() > block.size()) {
    const auto hashed = sha256(key);
    std::copy(hashed.begin(), hashed.end(), block.begin());
  } else {
    std::copy(key.begin(), key.end(), block.begin());
  }

  std::array<std::uint8_t, 64> inner{};
  std::array<std::uint8_t, 64> outer{};
  for (std::size_t i = 0; i < block.size(); ++i) {
    inner[i] = static_cast<std::uint8_t>(block[i] ^ 0x36);
    outer[i] = static_cast<std::uint8_t>(block[i] ^ 0x5c);
  }

  Sha256 innerHash;
  innerHash.update(inner.data(), inner.size());
  innerHash.update(message);
  const auto innerDigest = innerHash.finish();

  Sha256 outerHash;
  outerHash.update(outer.data(), outer.size());
  outerHash.update(innerDigest.data(), innerDigest.size());
  return outerHash.finish();
}

Bytes pbkdf2HmacSha256(std::string_view password, std::string_view salt, std::uint32_t iterations,
                       std::size_t length) {
  Bytes output;
  output.reserve(length);
  for (std::uint32_t blockIndex = 1; output.size() < length; ++blockIndex) {
    std::string firstMessage(salt);
    firstMessage.push_back(static_cast<char>((blockIndex >> 24) & 0xff));
    firstMessage.push_back(static_cast<char>((blockIndex >> 16) & 0xff));
    firstMessage.push_back(static_cast<char>((blockIndex >> 8) & 0xff));
    firstMessage.push_back(static_cast<char>(blockIndex & 0xff));

    Digest u = hmacSha256(password, firstMessage);
    Digest block = u;
    for (std::uint32_t i = 1; i < iterations; ++i) {
      u = hmacSha256(password, asView(u));
      for (std::size_t j = 0; j < block.size(); ++j) {
        block[j] = static_cast<std::uint8_t>(block[j] ^ u[j]);
      }
    }
    for (std::size_t j = 0; j < block.size() && output.size() < length; ++j) {
      output.push_back(block[j]);
    }
  }
  return output;
}

Bytes randomBytes(std::size_t count) {
  static thread_local std::random_device device;
  std::uniform_int_distribution<int> distribution(0, 255);
  Bytes bytes(count);
  for (auto& byte : bytes) {
    byte = static_cast<std::uint8_t>(distribution(device));
  }
  return bytes;
}

std::string toHex(const std::uint8_t* data, std::size_t size) {
  static constexpr char kDigits[] = "0123456789abcdef";
  std::string hex;
  hex.reserve(size * 2);
  for (std::size_t i = 0; i < size; ++i) {
    hex.push_back(kDigits[data[i] >> 4]);
    hex.push_back(kDigits[data[i] & 0x0f]);
  }
  return hex;
}

std::string uuidV4() {
  auto bytes = randomBytes(16);
  bytes[6] = static_cast<std::uint8_t>((bytes[6] & 0x0f) | 0x40);
  bytes[8] = static_cast<std::uint8_t>((bytes[8] & 0x3f) | 0x80);
  const auto hex = toHex(bytes);
  return hex.substr(0, 8) + "-" + hex.substr(8, 4) + "-" + hex.substr(12, 4) + "-" + hex.substr(16, 4) + "-" +
         hex.substr(20, 12);
}

bool constantTimeEquals(std::string_view a, std::string_view b) {
  if (a.size() != b.size()) {
    return false;
  }
  unsigned char difference = 0;
  for (std::size_t i = 0; i < a.size(); ++i) {
    difference = static_cast<unsigned char>(difference | (a[i] ^ b[i]));
  }
  return difference == 0;
}

}  // namespace voxon::crypto
