#pragma once

#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

// Reglas de dinero, ITBIS, propina y pagos. Es el mismo algoritmo que
// packages/voxon_domain (Dart): ambos deben dar resultados idénticos.
namespace voxon::domain {

/// Montos en centavos enteros; nunca se usa punto flotante para dinero.
using Cents = std::int64_t;

/// Cantidades en milésimas: 500 = media libra.
using Milli = std::int64_t;

/// Divide redondeando al entero más cercano; las mitades se alejan de cero.
std::int64_t roundDiv(std::int64_t numerator, std::int64_t denominator);

/// Porcentaje en puntos básicos (1800 = 18 %) redondeado al centavo.
Cents percentOf(Cents amount, std::int64_t basisPoints);

/// Importe de `quantity` milésimas a `unitPrice`, redondeado al centavo.
Cents lineAmount(Cents unitPrice, Milli quantity);

/// Reparte `amount` en partes proporcionales a `weights` sin perder centavos;
/// los sobrantes van a las partes con mayor residuo (y a la primera si empatan).
std::vector<Cents> allocate(Cents amount, const std::vector<std::int64_t>& weights);

/// "1250.75" para mensajes y exportaciones.
std::string formatCents(Cents amount);

enum class TaxRate { Exempt, Reduced, Standard };
enum class PriceMode { TaxIncluded, TaxExcluded };
enum class PaymentMethod { Cash, Card, Transfer, Credit };

/// 0, 1600 o 1800.
std::int64_t basisPoints(TaxRate rate);

std::string_view toString(TaxRate rate);
std::string_view toString(PriceMode mode);
std::string_view toString(PaymentMethod method);
std::optional<TaxRate> parseTaxRate(std::string_view value);
std::optional<PriceMode> parsePriceMode(std::string_view value);
std::optional<PaymentMethod> parsePaymentMethod(std::string_view value);

struct Discount {
  enum class Kind { Amount, Percent };

  Kind kind = Kind::Amount;
  /// Centavos (Amount) o puntos básicos (Percent, 0..10000).
  std::int64_t value = 0;

  /// Monto a descontar de `base`: nunca negativo ni mayor que `base`.
  Cents applyTo(Cents base) const;
};

struct SaleLineInput {
  Cents unitPrice = 0;
  Milli quantity = 0;
  TaxRate taxRate = TaxRate::Standard;
  std::optional<Discount> discount;
};

struct LineTotals {
  Cents gross = 0;
  Cents lineDiscount = 0;
  Cents orderDiscount = 0;
  TaxRate taxRate = TaxRate::Standard;

  Cents net() const { return gross - lineDiscount - orderDiscount; }
};

struct TaxGroup {
  TaxRate rate = TaxRate::Standard;
  Cents taxableBase = 0;
  Cents tax = 0;
};

struct SaleTotals {
  std::vector<LineTotals> lines;
  /// Un grupo por tasa presente, en orden exento, reducido, general.
  std::vector<TaxGroup> taxGroups;
  /// Propina legal: no lleva ITBIS.
  Cents tip = 0;

  Cents discount() const;
  /// Suma de bases imponibles, sin ITBIS ni propina.
  Cents subtotal() const;
  Cents tax() const;
  Cents total() const;
};

/// Propina legal de establecimientos de comida y bebida: 10 %.
inline constexpr std::int64_t kLegalTipBasisPoints = 1000;

/// Calcula una venta:
///  - los descuentos van antes del ITBIS; el general se reparte por importe;
///  - el ITBIS se calcula por tasa sobre el monto agrupado;
///  - la propina se calcula sobre la base sin ITBIS (Código de Trabajo, art. 228).
SaleTotals calculateSale(const std::vector<SaleLineInput>& lines, PriceMode priceMode,
                         const std::optional<Discount>& orderDiscount, std::int64_t tipBasisPoints);

struct Payment {
  PaymentMethod method = PaymentMethod::Cash;
  Cents amount = 0;
};

struct PaymentSummary {
  Cents total = 0;
  Cents paid = 0;

  bool isSettled() const { return paid >= total; }
  Cents remaining() const { return isSettled() ? 0 : total - paid; }
  /// El vuelto siempre sale del efectivo: los demás medios no pasan del total.
  Cents change() const { return paid > total ? paid - total : 0; }
};

/// Valida los pagos (mayores que cero; tarjeta, transferencia y fiao no pueden
/// pasar del total) y resume el cobro.
PaymentSummary summarizePayments(Cents total, const std::vector<Payment>& payments);

}  // namespace voxon::domain
