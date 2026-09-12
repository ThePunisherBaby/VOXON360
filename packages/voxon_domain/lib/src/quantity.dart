import 'package:voxon_domain/src/money.dart';

/// Cantidad vendida con hasta tres decimales, por ejemplo media libra (`0.5`).
///
/// Se guarda en milésimas enteras por la misma razón que [Money].
final class Quantity implements Comparable<Quantity> {
  const Quantity.milli(this.milli);

  const Quantity.units(int units) : milli = units * 1000;

  static const zero = Quantity.milli(0);

  static const one = Quantity.units(1);

  factory Quantity.parse(String input) {
    final quantity = tryParse(input);
    if (quantity == null) {
      throw FormatException('Cantidad inválida', input);
    }
    return quantity;
  }

  static Quantity? tryParse(String input) {
    final match = _pattern.firstMatch(input.replaceAll(_whitespace, ''));
    if (match == null) return null;
    final whole = int.parse(match.group(2)!);
    final fraction = int.parse((match.group(3) ?? '').padRight(3, '0'));
    final milli = whole * 1000 + fraction;
    return Quantity.milli(match.group(1) == '-' ? -milli : milli);
  }

  static final _whitespace = RegExp(r'\s');
  static final _pattern = RegExp(r'^(-?)(\d+)(?:\.(\d{1,3}))?$');

  final int milli;

  bool get isZero => milli == 0;

  bool get isNegative => milli < 0;

  bool get isWhole => milli % 1000 == 0;

  Quantity operator +(Quantity other) => Quantity.milli(milli + other.milli);

  Quantity operator -(Quantity other) => Quantity.milli(milli - other.milli);

  /// Importe de esta cantidad a [unitPrice], redondeado al centavo.
  Money times(Money unitPrice) => unitPrice.multiplyRatio(milli, 1000);

  /// `0.5`, `1.25`, `3`: sin ceros sobrantes.
  String toDecimalString() {
    final absMilli = milli.abs();
    final sign = isNegative ? '-' : '';
    final whole = absMilli ~/ 1000;
    final fraction = absMilli % 1000;
    if (fraction == 0) return '$sign$whole';
    final digits = fraction
        .toString()
        .padLeft(3, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    return '$sign$whole.$digits';
  }

  @override
  int compareTo(Quantity other) => milli.compareTo(other.milli);

  @override
  bool operator ==(Object other) => other is Quantity && other.milli == milli;

  @override
  int get hashCode => milli.hashCode;

  @override
  String toString() => 'Quantity(${toDecimalString()})';
}
