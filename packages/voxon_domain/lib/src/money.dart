import 'package:voxon_domain/src/rounding.dart';

/// Monto en pesos dominicanos guardado en centavos enteros.
///
/// El dinero nunca se representa con `double`: así los cuadres de caja y los
/// montos que se reportan a la DGII no acumulan errores de redondeo.
final class Money implements Comparable<Money> {
  const Money.cents(this.cents);

  const Money.pesos(int pesos) : cents = pesos * 100;

  static const zero = Money.cents(0);

  /// Lee montos escritos como `150`, `150.5`, `1,250.75` o `RD$ 99`.
  factory Money.parse(String input) {
    final money = tryParse(input);
    if (money == null) {
      throw FormatException('Monto inválido', input);
    }
    return money;
  }

  static Money? tryParse(String input) {
    final match = _pattern.firstMatch(input.replaceAll(_noise, ''));
    if (match == null) return null;
    final whole = int.parse(match.group(2)!);
    final fraction = int.parse((match.group(3) ?? '').padRight(2, '0'));
    final cents = whole * 100 + fraction;
    return Money.cents(match.group(1) == '-' ? -cents : cents);
  }

  static final _noise = RegExp(r'RD\$|\$|,|\s', caseSensitive: false);
  static final _pattern = RegExp(r'^(-?)(\d+)(?:\.(\d{1,2}))?$');

  static Money sum(Iterable<Money> values) =>
      values.fold(zero, (total, value) => total + value);

  final int cents;

  bool get isZero => cents == 0;

  bool get isNegative => cents < 0;

  bool get isPositive => cents > 0;

  Money operator +(Money other) => Money.cents(cents + other.cents);

  Money operator -(Money other) => Money.cents(cents - other.cents);

  Money operator -() => Money.cents(-cents);

  bool operator <(Money other) => cents < other.cents;

  bool operator <=(Money other) => cents <= other.cents;

  bool operator >(Money other) => cents > other.cents;

  bool operator >=(Money other) => cents >= other.cents;

  /// Multiplica por `numerator / denominator` redondeando al centavo.
  Money multiplyRatio(int numerator, int denominator) =>
      Money.cents(roundDiv(cents * numerator, denominator));

  /// Porcentaje en puntos básicos: `1800` equivale a 18 %.
  Money percent(int basisPoints) => multiplyRatio(basisPoints, 10000);

  /// Reparte el monto en partes proporcionales a [weights] sin perder
  /// centavos: los sobrantes van a las partes con mayor residuo.
  List<Money> allocate(List<int> weights) {
    if (weights.isEmpty || weights.any((weight) => weight < 0)) {
      throw ArgumentError.value(
        weights,
        'weights',
        'Debe tener pesos no negativos',
      );
    }
    final totalWeight = weights.fold(0, (total, weight) => total + weight);
    if (totalWeight == 0) {
      throw ArgumentError.value(
        weights,
        'weights',
        'La suma de los pesos no puede ser cero',
      );
    }

    final absCents = cents.abs();
    final shares = [
      for (final weight in weights) absCents * weight ~/ totalWeight,
    ];
    var leftover = absCents - shares.fold(0, (total, share) => total + share);

    int remainderOf(int index) => absCents * weights[index] % totalWeight;
    final byRemainder = List.generate(weights.length, (index) => index)
      ..sort((a, b) {
        final byValue = remainderOf(b).compareTo(remainderOf(a));
        return byValue != 0 ? byValue : a.compareTo(b);
      });
    for (final index in byRemainder) {
      if (leftover == 0) break;
      shares[index]++;
      leftover--;
    }

    return [
      for (final share in shares) Money.cents(isNegative ? -share : share),
    ];
  }

  /// Divide en [parts] partes iguales; los centavos sobrantes van a las primeras.
  List<Money> split(int parts) => allocate(List.filled(parts, 1));

  /// Representación simple como `1250.75`. El formato con símbolo y
  /// separadores de miles corresponde a la interfaz.
  String toDecimalString() {
    final absCents = cents.abs();
    final sign = isNegative ? '-' : '';
    return '$sign${absCents ~/ 100}.${(absCents % 100).toString().padLeft(2, '0')}';
  }

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => 'Money(${toDecimalString()})';
}
