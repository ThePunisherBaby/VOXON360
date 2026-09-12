import 'package:test/test.dart';
import 'package:voxon_domain/voxon_domain.dart';

void main() {
  final total = Money.parse('304');

  test('efectivo exacto', () {
    final summary = PaymentSummary.of(total, [
      Payment(PaymentMethod.cash, total),
    ]);

    expect(summary.isSettled, isTrue);
    expect(summary.change, Money.zero);
  });

  test('efectivo con vuelto', () {
    final summary = PaymentSummary.of(total, [
      Payment(PaymentMethod.cash, Money.parse('500')),
    ]);

    expect(summary.change, Money.parse('196'));
    expect(summary.remaining, Money.zero);
  });

  test('pago mixto: el vuelto sale del efectivo', () {
    final summary = PaymentSummary.of(total, [
      Payment(PaymentMethod.card, Money.parse('200')),
      Payment(PaymentMethod.cash, Money.parse('200')),
    ]);

    expect(summary.change, Money.parse('96'));
  });

  test('un pago parcial deja saldo pendiente', () {
    final summary = PaymentSummary.of(total, [
      Payment(PaymentMethod.transfer, Money.parse('100')),
    ]);

    expect(summary.isSettled, isFalse);
    expect(summary.remaining, Money.parse('204'));
  });

  test('tarjeta, transferencia o fiao no pueden pasar del total', () {
    expect(
      () => PaymentSummary.of(total, [
        Payment(PaymentMethod.card, Money.parse('305')),
      ]),
      throwsArgumentError,
    );
    expect(
      () => PaymentSummary.of(total, [
        Payment(PaymentMethod.credit, Money.parse('400')),
      ]),
      throwsArgumentError,
    );
  });

  test('rechaza pagos en cero', () {
    expect(
      () => PaymentSummary.of(total, [Payment(PaymentMethod.cash, Money.zero)]),
      throwsArgumentError,
    );
  });
}
