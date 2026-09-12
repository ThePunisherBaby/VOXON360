import 'package:voxon_domain/src/money.dart';

/// Descuento sobre una línea o sobre toda la venta.
sealed class Discount {
  const Discount();

  const factory Discount.amount(Money amount) = AmountDiscount;

  const factory Discount.percent(int basisPoints) = PercentDiscount;

  /// Monto a descontar de [base]: nunca negativo ni mayor que [base].
  Money applyTo(Money base);
}

/// Descuento de un monto fijo, por ejemplo RD$50.
final class AmountDiscount extends Discount {
  const AmountDiscount(this.amount);

  final Money amount;

  @override
  Money applyTo(Money base) => _clamp(amount, base);
}

/// Descuento porcentual en puntos básicos: `1000` equivale a 10 %.
final class PercentDiscount extends Discount {
  const PercentDiscount(this.basisPoints);

  final int basisPoints;

  @override
  Money applyTo(Money base) => _clamp(base.percent(basisPoints), base);
}

Money _clamp(Money value, Money max) {
  if (value.isNegative) return Money.zero;
  return value > max ? max : value;
}
