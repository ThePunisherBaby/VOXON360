#include "domain/money.hpp"

#include <algorithm>
#include <array>
#include <limits>
#include <numeric>

#include "core/error.hpp"

namespace voxon::domain {

namespace {

constexpr std::int64_t kMax = std::numeric_limits<std::int64_t>::max();

// Multiplicación de valores no negativos que falla en vez de desbordar.
std::int64_t checkedMul(std::int64_t a, std::int64_t b) {
  if (a < 0 || b < 0) {
    throw ApiError(errc::kValidation, "Los montos y cantidades no pueden ser negativos");
  }
  if (a != 0 && b > kMax / a) {
    throw ApiError(errc::kValidation, "El monto es demasiado grande");
  }
  return a * b;
}

constexpr std::array<TaxRate, 3> kRatesInOrder = {TaxRate::Exempt, TaxRate::Reduced, TaxRate::Standard};

}  // namespace

std::int64_t roundDiv(std::int64_t numerator, std::int64_t denominator) {
  if (denominator <= 0) {
    throw ApiError(errc::kInternal, "El divisor debe ser mayor que cero");
  }
  const std::int64_t quotient = numerator / denominator;
  const std::int64_t remainder = numerator % denominator;
  const std::int64_t absRemainder = remainder < 0 ? -remainder : remainder;
  if (absRemainder >= denominator - absRemainder) {
    return numerator < 0 ? quotient - 1 : quotient + 1;
  }
  return quotient;
}

Cents percentOf(Cents amount, std::int64_t basisPoints) {
  if (amount < 0) {
    return -roundDiv(checkedMul(-amount, basisPoints), 10000);
  }
  return roundDiv(checkedMul(amount, basisPoints), 10000);
}

Cents lineAmount(Cents unitPrice, Milli quantity) { return roundDiv(checkedMul(unitPrice, quantity), 1000); }

std::vector<Cents> allocate(Cents amount, const std::vector<std::int64_t>& weights) {
  if (weights.empty() || std::any_of(weights.begin(), weights.end(), [](auto w) { return w < 0; })) {
    throw ApiError(errc::kInternal, "Los pesos del reparto deben ser no negativos");
  }
  std::int64_t totalWeight = 0;
  for (const auto weight : weights) {
    if (weight > kMax - totalWeight) {
      throw ApiError(errc::kValidation, "El monto es demasiado grande");
    }
    totalWeight += weight;
  }
  if (totalWeight == 0) {
    throw ApiError(errc::kInternal, "La suma de los pesos del reparto no puede ser cero");
  }

  const Cents absAmount = amount < 0 ? -amount : amount;
  std::vector<Cents> shares(weights.size());
  std::vector<std::int64_t> remainders(weights.size());
  Cents assigned = 0;
  for (size_t i = 0; i < weights.size(); ++i) {
    const auto product = checkedMul(absAmount, weights[i]);
    shares[i] = product / totalWeight;
    remainders[i] = product % totalWeight;
    assigned += shares[i];
  }

  std::vector<size_t> order(weights.size());
  std::iota(order.begin(), order.end(), size_t{0});
  std::stable_sort(order.begin(), order.end(), [&](size_t a, size_t b) { return remainders[a] > remainders[b]; });
  for (Cents leftover = absAmount - assigned, k = 0; leftover > 0; --leftover, ++k) {
    ++shares[order[static_cast<size_t>(k)]];
  }

  if (amount < 0) {
    for (auto& share : shares) {
      share = -share;
    }
  }
  return shares;
}

std::string formatCents(Cents amount) {
  const Cents absAmount = amount < 0 ? -amount : amount;
  const auto fraction = absAmount % 100;
  return std::string(amount < 0 ? "-" : "") + std::to_string(absAmount / 100) + "." + (fraction < 10 ? "0" : "") +
         std::to_string(fraction);
}

std::int64_t basisPoints(TaxRate rate) {
  switch (rate) {
    case TaxRate::Exempt: return 0;
    case TaxRate::Reduced: return 1600;
    case TaxRate::Standard: return 1800;
  }
  return 1800;
}

std::string_view toString(TaxRate rate) {
  switch (rate) {
    case TaxRate::Exempt: return "exempt";
    case TaxRate::Reduced: return "reduced";
    case TaxRate::Standard: return "standard";
  }
  return "standard";
}

std::string_view toString(PriceMode mode) {
  return mode == PriceMode::TaxIncluded ? "tax_included" : "tax_excluded";
}

std::string_view toString(PaymentMethod method) {
  switch (method) {
    case PaymentMethod::Cash: return "cash";
    case PaymentMethod::Card: return "card";
    case PaymentMethod::Transfer: return "transfer";
    case PaymentMethod::Credit: return "credit";
  }
  return "cash";
}

std::optional<TaxRate> parseTaxRate(std::string_view value) {
  for (const auto rate : kRatesInOrder) {
    if (toString(rate) == value) return rate;
  }
  return std::nullopt;
}

std::optional<PriceMode> parsePriceMode(std::string_view value) {
  if (value == "tax_included") return PriceMode::TaxIncluded;
  if (value == "tax_excluded") return PriceMode::TaxExcluded;
  return std::nullopt;
}

std::optional<PaymentMethod> parsePaymentMethod(std::string_view value) {
  for (const auto method : {PaymentMethod::Cash, PaymentMethod::Card, PaymentMethod::Transfer, PaymentMethod::Credit}) {
    if (toString(method) == value) return method;
  }
  return std::nullopt;
}

Cents Discount::applyTo(Cents base) const {
  const Cents amount = kind == Kind::Amount ? value : percentOf(base, value);
  return std::clamp<Cents>(amount, 0, std::max<Cents>(base, 0));
}

Cents SaleTotals::discount() const {
  Cents sum = 0;
  for (const auto& line : lines) sum += line.lineDiscount + line.orderDiscount;
  return sum;
}

Cents SaleTotals::subtotal() const {
  Cents sum = 0;
  for (const auto& group : taxGroups) sum += group.taxableBase;
  return sum;
}

Cents SaleTotals::tax() const {
  Cents sum = 0;
  for (const auto& group : taxGroups) sum += group.tax;
  return sum;
}

Cents SaleTotals::total() const { return subtotal() + tax() + tip; }

SaleTotals calculateSale(const std::vector<SaleLineInput>& lines, PriceMode priceMode,
                         const std::optional<Discount>& orderDiscount, std::int64_t tipBasisPoints) {
  for (const auto& line : lines) {
    if (line.unitPrice < 0) {
      throw ApiError(errc::kValidation, "El precio no puede ser negativo");
    }
    if (line.quantity <= 0) {
      throw ApiError(errc::kValidation, "La cantidad debe ser mayor que cero");
    }
    if (line.discount && line.discount->kind == Discount::Kind::Percent &&
        (line.discount->value < 0 || line.discount->value > 10000)) {
      throw ApiError(errc::kValidation, "El descuento debe estar entre 0 % y 100 %");
    }
  }
  if (orderDiscount && (orderDiscount->value < 0 ||
                        (orderDiscount->kind == Discount::Kind::Percent && orderDiscount->value > 10000))) {
    throw ApiError(errc::kValidation, "El descuento general no es válido");
  }
  if (tipBasisPoints < 0 || tipBasisPoints > 10000) {
    throw ApiError(errc::kValidation, "La propina no es válida");
  }

  SaleTotals totals;
  totals.lines.reserve(lines.size());
  std::vector<std::int64_t> afterLineDiscount;
  afterLineDiscount.reserve(lines.size());
  Cents pool = 0;
  for (const auto& line : lines) {
    LineTotals lineTotals;
    lineTotals.gross = lineAmount(line.unitPrice, line.quantity);
    lineTotals.lineDiscount = line.discount ? line.discount->applyTo(lineTotals.gross) : 0;
    lineTotals.taxRate = line.taxRate;
    afterLineDiscount.push_back(lineTotals.gross - lineTotals.lineDiscount);
    pool += afterLineDiscount.back();
    totals.lines.push_back(lineTotals);
  }

  if (pool > 0 && orderDiscount) {
    const auto shares = allocate(orderDiscount->applyTo(pool), afterLineDiscount);
    for (size_t i = 0; i < shares.size(); ++i) {
      totals.lines[i].orderDiscount = shares[i];
    }
  }

  for (const auto rate : kRatesInOrder) {
    bool present = false;
    Cents net = 0;
    for (const auto& line : totals.lines) {
      if (line.taxRate == rate) {
        present = true;
        net += line.net();
      }
    }
    if (!present) {
      continue;
    }
    TaxGroup group;
    group.rate = rate;
    if (priceMode == PriceMode::TaxIncluded) {
      group.taxableBase = roundDiv(checkedMul(net, 10000), 10000 + basisPoints(rate));
      group.tax = net - group.taxableBase;
    } else {
      group.taxableBase = net;
      group.tax = percentOf(net, basisPoints(rate));
    }
    totals.taxGroups.push_back(group);
  }

  totals.tip = percentOf(totals.subtotal(), tipBasisPoints);
  return totals;
}

PaymentSummary summarizePayments(Cents total, const std::vector<Payment>& payments) {
  Cents withoutChange = 0;
  Cents paid = 0;
  for (const auto& payment : payments) {
    if (payment.amount <= 0) {
      throw ApiError(errc::kValidation, "Cada pago debe ser mayor que cero");
    }
    if (payment.method != PaymentMethod::Cash) {
      withoutChange += payment.amount;
    }
    paid += payment.amount;
  }
  if (withoutChange > total) {
    throw ApiError(errc::kValidation, "Tarjeta, transferencia y fiao no pueden pasar del total");
  }
  return PaymentSummary{total, paid};
}

}  // namespace voxon::domain
