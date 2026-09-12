/// Divide redondeando al entero más cercano; las mitades se alejan de cero
/// (redondeo comercial).
int roundDiv(int numerator, int denominator) {
  if (denominator <= 0) {
    throw ArgumentError.value(
      denominator,
      'denominator',
      'Debe ser mayor que cero',
    );
  }
  final quotient = numerator ~/ denominator;
  final remainder = numerator.remainder(denominator);
  if (remainder.abs() * 2 >= denominator) {
    return numerator.isNegative ? quotient - 1 : quotient + 1;
  }
  return quotient;
}
