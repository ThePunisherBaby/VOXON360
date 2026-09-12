import 'package:voxon_domain/src/money.dart';

/// Forma en que el cliente paga.
enum PaymentMethod {
  cash,
  card,
  transfer,

  /// Fiao: el monto queda como deuda en la cuenta del cliente.
  credit;

  /// Solo el efectivo puede dar vuelto.
  bool get givesChange => this == cash;
}

final class Payment {
  const Payment(this.method, this.amount);

  final PaymentMethod method;
  final Money amount;
}

/// Estado del cobro de una venta: cuánto falta y cuánto vuelto hay que dar.
final class PaymentSummary {
  const PaymentSummary._({required this.total, required this.paid});

  factory PaymentSummary.of(Money total, List<Payment> payments) {
    if (payments.any((payment) => !payment.amount.isPositive)) {
      throw ArgumentError.value(
        payments,
        'payments',
        'Cada pago debe ser mayor que cero',
      );
    }
    final withoutChange = Money.sum(
      payments
          .where((payment) => !payment.method.givesChange)
          .map((payment) => payment.amount),
    );
    if (withoutChange > total) {
      throw ArgumentError.value(
        payments,
        'payments',
        'Tarjeta, transferencia y fiao no pueden pasar del total',
      );
    }
    return PaymentSummary._(
      total: total,
      paid: Money.sum(payments.map((payment) => payment.amount)),
    );
  }

  final Money total;
  final Money paid;

  bool get isSettled => paid >= total;

  Money get remaining => isSettled ? Money.zero : total - paid;

  /// Como los pagos sin vuelto no pasan del total, el vuelto siempre sale
  /// del efectivo entregado.
  Money get change => paid > total ? paid - total : Money.zero;
}
