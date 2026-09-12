import 'package:test/test.dart';
import 'package:voxon_domain/voxon_domain.dart';

SaleLineInput line(
  String price,
  TaxRate rate, {
  String quantity = '1',
  Discount? discount,
}) => SaleLineInput(
  unitPrice: Money.parse(price),
  quantity: Quantity.parse(quantity),
  taxRate: rate,
  discount: discount,
);

void main() {
  test('restaurante: propina 10 % sobre la base y sin ITBIS', () {
    final totals = SaleCalculator.calculate(
      lines: [line('1000', TaxRate.standard)],
      priceMode: PriceMode.taxExcluded,
      tipBasisPoints: SaleCalculator.legalTipBasisPoints,
    );

    expect(totals.subtotal, Money.parse('1000'));
    expect(totals.tip, Money.parse('100'));
    expect(totals.tax, Money.parse('180'));
    expect(totals.total, Money.parse('1280'));
  });

  test('colmado: precios con ITBIS incluido y tasas mixtas', () {
    final totals = SaleCalculator.calculate(
      lines: [
        line('35', TaxRate.exempt, quantity: '2'), // arroz por libra
        line('116', TaxRate.reduced), // café
        line('59', TaxRate.standard, quantity: '2'), // refrescos
      ],
      priceMode: PriceMode.taxIncluded,
    );

    expect(totals.total, Money.parse('304'));
    expect(totals.subtotal, Money.parse('270'));
    expect(totals.tax, Money.parse('34'));
    expect(
      [
        for (final group in totals.taxGroups)
          (group.rate, group.taxableBase, group.tax),
      ],
      [
        (TaxRate.exempt, Money.parse('70'), Money.zero),
        (TaxRate.reduced, Money.parse('100'), Money.parse('16')),
        (TaxRate.standard, Money.parse('100'), Money.parse('18')),
      ],
    );
  });

  test('el descuento de línea se aplica antes del ITBIS', () {
    final totals = SaleCalculator.calculate(
      lines: [
        line('1180', TaxRate.standard, discount: const Discount.percent(1000)),
      ],
      priceMode: PriceMode.taxIncluded,
    );

    expect(totals.discount, Money.parse('118'));
    expect(totals.total, Money.parse('1062'));
    expect(totals.subtotal, Money.parse('900'));
    expect(totals.tax, Money.parse('162'));
  });

  test('el descuento general se reparte entre líneas sin perder centavos', () {
    final totals = SaleCalculator.calculate(
      lines: [line('100', TaxRate.standard), line('50', TaxRate.exempt)],
      priceMode: PriceMode.taxIncluded,
      orderDiscount: Discount.amount(Money.parse('15')),
    );

    expect(totals.lines.map((line) => line.net), [
      Money.parse('90'),
      Money.parse('45'),
    ]);
    expect(totals.discount, Money.parse('15'));
    expect(totals.total, Money.parse('135'));
    expect(totals.tax, Money.parse('13.73'));
  });

  test('restaurante con descuento: la propina usa la base ya descontada', () {
    final totals = SaleCalculator.calculate(
      lines: [line('1000', TaxRate.standard)],
      priceMode: PriceMode.taxExcluded,
      orderDiscount: Discount.amount(Money.parse('100')),
      tipBasisPoints: SaleCalculator.legalTipBasisPoints,
    );

    expect(totals.subtotal, Money.parse('900'));
    expect(totals.tip, Money.parse('90'));
    expect(totals.tax, Money.parse('162'));
    expect(totals.total, Money.parse('1152'));
  });

  test('media libra se cobra redondeada al centavo', () {
    final totals = SaleCalculator.calculate(
      lines: [line('35', TaxRate.exempt, quantity: '0.5')],
      priceMode: PriceMode.taxIncluded,
    );

    expect(totals.total, Money.parse('17.50'));
  });

  test('un descuento mayor que la línea la deja en cero', () {
    final totals = SaleCalculator.calculate(
      lines: [
        line(
          '50',
          TaxRate.standard,
          discount: Discount.amount(Money.parse('80')),
        ),
      ],
      priceMode: PriceMode.taxIncluded,
    );

    expect(totals.discount, Money.parse('50'));
    expect(totals.total, Money.zero);
  });

  test('una venta vacía da cero', () {
    final totals = SaleCalculator.calculate(
      lines: const [],
      priceMode: PriceMode.taxIncluded,
      orderDiscount: const Discount.percent(1000),
    );

    expect(totals.total, Money.zero);
    expect(totals.taxGroups, isEmpty);
  });

  test('rechaza precios negativos', () {
    expect(
      () => SaleCalculator.calculate(
        lines: [line('-5', TaxRate.standard)],
        priceMode: PriceMode.taxIncluded,
      ),
      throwsArgumentError,
    );
  });
}
