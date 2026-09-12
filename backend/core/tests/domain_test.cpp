// Mismos casos que packages/voxon_domain (Dart): ambos motores deben coincidir.

#include <doctest/doctest.h>

#include "core/error.hpp"
#include "domain/money.hpp"

using namespace voxon::domain;

namespace {

SaleLineInput line(Cents price, TaxRate rate, Milli quantity = 1000, std::optional<Discount> discount = std::nullopt) {
  return SaleLineInput{price, quantity, rate, discount};
}

Discount percent(std::int64_t basisPoints) { return Discount{Discount::Kind::Percent, basisPoints}; }

Discount amount(Cents cents) { return Discount{Discount::Kind::Amount, cents}; }

}  // namespace

TEST_CASE("redondeo comercial: las mitades se alejan de cero") {
  CHECK(percentOf(25, 1800) == 5);
  CHECK(percentOf(-25, 1800) == -5);
  CHECK(percentOf(24, 1800) == 4);
  CHECK(roundDiv(5, 2) == 3);
  CHECK(roundDiv(-5, 2) == -3);
}

TEST_CASE("el reparto no pierde centavos") {
  CHECK(allocate(10000, {1, 1, 1}) == std::vector<Cents>{3334, 3333, 3333});
  CHECK(allocate(1500, {100, 50}) == std::vector<Cents>{1000, 500});
  CHECK_THROWS_AS(allocate(100, {0, 0}), voxon::ApiError);
}

TEST_CASE("restaurante: propina 10 % sobre la base y sin ITBIS") {
  const auto totals = calculateSale({line(100000, TaxRate::Standard)}, PriceMode::TaxExcluded, std::nullopt,
                                    kLegalTipBasisPoints);
  CHECK(totals.subtotal() == 100000);
  CHECK(totals.tip == 10000);
  CHECK(totals.tax() == 18000);
  CHECK(totals.total() == 128000);
}

TEST_CASE("colmado: ITBIS incluido y tasas mixtas") {
  const auto totals = calculateSale(
      {line(3500, TaxRate::Exempt, 2000), line(11600, TaxRate::Reduced), line(5900, TaxRate::Standard, 2000)},
      PriceMode::TaxIncluded, std::nullopt, 0);
  CHECK(totals.total() == 30400);
  CHECK(totals.subtotal() == 27000);
  CHECK(totals.tax() == 3400);
  REQUIRE(totals.taxGroups.size() == 3);
  // Doble paréntesis: doctest no sabe imprimir estos enums.
  CHECK((totals.taxGroups[0].rate == TaxRate::Exempt));
  CHECK(totals.taxGroups[1].taxableBase == 10000);
  CHECK(totals.taxGroups[1].tax == 1600);
  CHECK(totals.taxGroups[2].tax == 1800);
}

TEST_CASE("el descuento de línea va antes del ITBIS") {
  const auto totals =
      calculateSale({line(118000, TaxRate::Standard, 1000, percent(1000))}, PriceMode::TaxIncluded, std::nullopt, 0);
  CHECK(totals.discount() == 11800);
  CHECK(totals.total() == 106200);
  CHECK(totals.subtotal() == 90000);
  CHECK(totals.tax() == 16200);
}

TEST_CASE("el descuento general se reparte entre líneas sin perder centavos") {
  const auto totals = calculateSale({line(10000, TaxRate::Standard), line(5000, TaxRate::Exempt)},
                                    PriceMode::TaxIncluded, amount(1500), 0);
  CHECK(totals.lines[0].net() == 9000);
  CHECK(totals.lines[1].net() == 4500);
  CHECK(totals.discount() == 1500);
  CHECK(totals.total() == 13500);
  CHECK(totals.tax() == 1373);
}

TEST_CASE("restaurante con descuento: la propina usa la base descontada") {
  const auto totals = calculateSale({line(100000, TaxRate::Standard)}, PriceMode::TaxExcluded, amount(10000),
                                    kLegalTipBasisPoints);
  CHECK(totals.subtotal() == 90000);
  CHECK(totals.tip == 9000);
  CHECK(totals.tax() == 16200);
  CHECK(totals.total() == 115200);
}

TEST_CASE("media libra se cobra redondeada al centavo") {
  const auto totals = calculateSale({line(3500, TaxRate::Exempt, 500)}, PriceMode::TaxIncluded, std::nullopt, 0);
  CHECK(totals.total() == 1750);
}

TEST_CASE("un descuento mayor que la línea la deja en cero") {
  const auto totals =
      calculateSale({line(5000, TaxRate::Standard, 1000, amount(8000))}, PriceMode::TaxIncluded, std::nullopt, 0);
  CHECK(totals.discount() == 5000);
  CHECK(totals.total() == 0);
}

TEST_CASE("una venta vacía da cero") {
  const auto totals = calculateSale({}, PriceMode::TaxIncluded, percent(1000), 0);
  CHECK(totals.total() == 0);
  CHECK(totals.taxGroups.empty());
}

TEST_CASE("rechaza precios negativos, cantidades en cero y descuentos fuera de rango") {
  CHECK_THROWS_AS(calculateSale({line(-500, TaxRate::Standard)}, PriceMode::TaxIncluded, std::nullopt, 0),
                  voxon::ApiError);
  CHECK_THROWS_AS(calculateSale({line(500, TaxRate::Standard, 0)}, PriceMode::TaxIncluded, std::nullopt, 0),
                  voxon::ApiError);
  CHECK_THROWS_AS(calculateSale({line(500, TaxRate::Standard, 1000, percent(12000))}, PriceMode::TaxIncluded,
                                std::nullopt, 0),
                  voxon::ApiError);
}

TEST_CASE("pagos: vuelto, pago mixto y saldo pendiente") {
  const auto exact = summarizePayments(30400, {{PaymentMethod::Cash, 30400}});
  CHECK(exact.isSettled());
  CHECK(exact.change() == 0);

  const auto withChange = summarizePayments(30400, {{PaymentMethod::Cash, 50000}});
  CHECK(withChange.change() == 19600);

  const auto mixed = summarizePayments(30400, {{PaymentMethod::Card, 20000}, {PaymentMethod::Cash, 20000}});
  CHECK(mixed.change() == 9600);

  const auto partial = summarizePayments(30400, {{PaymentMethod::Transfer, 10000}});
  CHECK_FALSE(partial.isSettled());
  CHECK(partial.remaining() == 20400);

  CHECK_THROWS_AS(summarizePayments(30400, {{PaymentMethod::Card, 30500}}), voxon::ApiError);
  CHECK_THROWS_AS(summarizePayments(30400, {{PaymentMethod::Credit, 40000}}), voxon::ApiError);
  CHECK_THROWS_AS(summarizePayments(30400, {{PaymentMethod::Cash, 0}}), voxon::ApiError);
}

TEST_CASE("formato y nombres de los enums") {
  CHECK(formatCents(125075) == "1250.75");
  CHECK(formatCents(-350) == "-3.50");
  CHECK(formatCents(5) == "0.05");
  CHECK((parseTaxRate("reduced") == TaxRate::Reduced));
  CHECK_FALSE(parseTaxRate("otra").has_value());
  CHECK(std::string(toString(PriceMode::TaxExcluded)) == "tax_excluded");
  CHECK((parsePaymentMethod("credit") == PaymentMethod::Credit));
}
