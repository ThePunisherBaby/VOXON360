#include "text/text.hpp"

namespace voxon::text {

namespace {

bool isSpace(unsigned char c) {
  return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

// Segundo byte de U+00C0..U+00FF (prefijo 0xC3) → letra sin acento, o 0.
char foldLatin1(unsigned char b) {
  if ((b >= 0x80 && b <= 0x85) || (b >= 0xA0 && b <= 0xA5)) return 'a';
  if (b == 0x87 || b == 0xA7) return 'c';
  if ((b >= 0x88 && b <= 0x8B) || (b >= 0xA8 && b <= 0xAB)) return 'e';
  if ((b >= 0x8C && b <= 0x8F) || (b >= 0xAC && b <= 0xAF)) return 'i';
  if (b == 0x91 || b == 0xB1) return 'n';
  if ((b >= 0x92 && b <= 0x96) || (b >= 0xB2 && b <= 0xB6)) return 'o';
  if ((b >= 0x99 && b <= 0x9C) || (b >= 0xB9 && b <= 0xBC)) return 'u';
  if (b == 0x9D || b == 0xBD || b == 0xBF) return 'y';
  return 0;
}

}  // namespace

std::string trim(std::string_view value) {
  size_t start = 0;
  size_t end = value.size();
  while (start < end && isSpace(static_cast<unsigned char>(value[start]))) {
    ++start;
  }
  while (end > start && isSpace(static_cast<unsigned char>(value[end - 1]))) {
    --end;
  }
  return std::string(value.substr(start, end - start));
}

std::string normalizeForSearch(std::string_view value) {
  std::string out;
  out.reserve(value.size());
  bool pendingSpace = false;

  for (size_t i = 0; i < value.size(); ++i) {
    const auto c = static_cast<unsigned char>(value[i]);
    if (isSpace(c)) {
      pendingSpace = !out.empty();
      continue;
    }
    if (pendingSpace) {
      out.push_back(' ');
      pendingSpace = false;
    }
    if (c < 0x80) {
      out.push_back(static_cast<char>(c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c));
      continue;
    }
    if (c == 0xC3 && i + 1 < value.size()) {
      if (const char folded = foldLatin1(static_cast<unsigned char>(value[i + 1]))) {
        out.push_back(folded);
        ++i;
        continue;
      }
    }
    out.push_back(static_cast<char>(c));
  }
  return out;
}

bool isDigits(std::string_view value) {
  if (value.empty()) {
    return false;
  }
  for (const char c : value) {
    if (c < '0' || c > '9') {
      return false;
    }
  }
  return true;
}

std::size_t utf8Length(std::string_view value) {
  std::size_t length = 0;
  for (const char c : value) {
    if ((static_cast<unsigned char>(c) & 0xC0) != 0x80) {
      ++length;
    }
  }
  return length;
}

}  // namespace voxon::text
