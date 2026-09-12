import 'package:test/test.dart';
import 'package:voxon_domain/voxon_domain.dart';

void main() {
  group('Money.parse', () {
    test('acepta separador de miles, símbolo y decimales', () {
      expect(Money.parse('1,250.75'), const Money.cents(125075));
      expect(Money.parse('RD\$ 99'), const Money.cents(9900));
      expect(Money.parse('150.5'), const Money.cents(15050));
      expect(Money.parse('-3.25'), const Money.cents(-325));
    });

    test('rechaza texto que no es un monto', () {
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('1.234'), isNull);
      expect(Money.tryParse(''), isNull);
      expect(() => Money.parse('12a'), throwsFormatException);
    });
  });

  test('las mitades de centavo se alejan de cero', () {
    // 0.25 × 18 % = 0.045 → 0.05
    expect(const Money.cents(25).percent(1800), const Money.cents(5));
    expect(const Money.cents(-25).percent(1800), const Money.cents(-5));
    // 0.24 × 18 % = 0.0432 → 0.04
    expect(const Money.cents(24).percent(1800), const Money.cents(4));
  });

  group('allocate', () {
    test('reparte en partes iguales sin perder centavos', () {
      final parts = const Money.pesos(100).split(3);

      expect(parts, const [
        Money.cents(3334),
        Money.cents(3333),
        Money.cents(3333),
      ]);
      expect(Money.sum(parts), const Money.pesos(100));
    });

    test('respeta las proporciones', () {
      expect(const Money.pesos(15).allocate([100, 50]), const [
        Money.pesos(10),
        Money.pesos(5),
      ]);
    });

    test('rechaza pesos vacíos o que suman cero', () {
      expect(() => Money.zero.allocate([]), throwsArgumentError);
      expect(() => Money.zero.allocate([0, 0]), throwsArgumentError);
    });
  });

  test('toDecimalString', () {
    expect(const Money.cents(125075).toDecimalString(), '1250.75');
    expect(const Money.cents(-350).toDecimalString(), '-3.50');
    expect(Money.zero.toDecimalString(), '0.00');
  });
}
