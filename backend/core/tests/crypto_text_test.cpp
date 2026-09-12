#include <doctest/doctest.h>

#include <string>

#include "crypto/crypto.hpp"
#include "text/text.hpp"

using namespace voxon;

TEST_CASE("SHA-256 con vectores conocidos") {
  CHECK(crypto::toHex(crypto::sha256("")) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  CHECK(crypto::toHex(crypto::sha256("abc")) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  CHECK(crypto::toHex(crypto::sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")) ==
        "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
  const std::string million(1000000, 'a');
  CHECK(crypto::toHex(crypto::sha256(million)) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
}

TEST_CASE("HMAC-SHA256 (RFC 4231, caso 2)") {
  CHECK(crypto::toHex(crypto::hmacSha256("Jefe", "what do ya want for nothing?")) ==
        "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843");
}

TEST_CASE("PBKDF2-HMAC-SHA256") {
  CHECK(crypto::toHex(crypto::pbkdf2HmacSha256("password", "salt", 1, 32)) ==
        "120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b");
  CHECK(crypto::toHex(crypto::pbkdf2HmacSha256("password", "salt", 2, 32)) ==
        "ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43");
  CHECK(crypto::toHex(crypto::pbkdf2HmacSha256("password", "salt", 4096, 32)) ==
        "c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a");
  CHECK(crypto::pbkdf2HmacSha256("password", "salt", 1, 40).size() == 40);
}

TEST_CASE("UUID versión 4") {
  const auto id = crypto::uuidV4();
  CHECK(id.size() == 36);
  CHECK(id[8] == '-');
  CHECK(id[14] == '4');
  CHECK(std::string("89ab").find(id[19]) != std::string::npos);
  CHECK(crypto::uuidV4() != id);
}

TEST_CASE("comparación en tiempo constante") {
  CHECK(crypto::constantTimeEquals("abc", "abc"));
  CHECK_FALSE(crypto::constantTimeEquals("abc", "abd"));
  CHECK_FALSE(crypto::constantTimeEquals("abc", "ab"));
}

TEST_CASE("búsqueda sin acentos igual que la app") {
  CHECK(text::normalizeForSearch("  Café  CON Leche ") == "cafe con leche");
  CHECK(text::normalizeForSearch("Piña y Ñame") == "pina y name");
  CHECK(text::normalizeForSearch("ÁÉÍÓÚ Ü ç") == "aeiou u c");
}

TEST_CASE("trim, dígitos y longitud UTF-8") {
  CHECK(text::trim("  hola \n") == "hola");
  CHECK(text::trim("   ").empty());
  CHECK(text::isDigits("0123"));
  CHECK_FALSE(text::isDigits(""));
  CHECK_FALSE(text::isDigits("12a"));
  CHECK(text::utf8Length("Peña") == 4);
}
