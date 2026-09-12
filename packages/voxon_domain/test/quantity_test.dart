import 'package:test/test.dart';
import 'package:voxon_domain/voxon_domain.dart';

void main() {
  test('parse acepta hasta tres decimales', () {
    expect(Quantity.parse('0.5'), const Quantity.milli(500));
    expect(Quantity.parse('1.25'), const Quantity.milli(1250));
    expect(Quantity.parse('2'), const Quantity.units(2));
    expect(Quantity.tryParse('1.2345'), isNull);
    expect(Quantity.tryParse('media'), isNull);
  });

  test('times redondea el importe al centavo', () {
    // Media libra de arroz a RD$35.00.
    expect(
      Quantity.parse('0.5').times(const Money.pesos(35)),
      const Money.cents(1750),
    );
    expect(
      Quantity.parse('0.333').times(const Money.pesos(100)),
      const Money.cents(3330),
    );
  });

  test('toDecimalString quita los ceros sobrantes', () {
    expect(const Quantity.milli(500).toDecimalString(), '0.5');
    expect(const Quantity.milli(1250).toDecimalString(), '1.25');
    expect(const Quantity.units(3).toDecimalString(), '3');
  });
}
