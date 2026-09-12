import 'package:flutter_test/flutter_test.dart';

import 'package:voxon90_owner/format.dart';

void main() {
  test('montos en pesos dominicanos', () {
    expect(formatMoney(0), r'RD$0.00');
    expect(formatMoney(5900), r'RD$59.00');
    expect(formatMoney(125075), r'RD$1,250.75');
    expect(formatMoney(123456789), r'RD$1,234,567.89');
    expect(formatMoney(-2500), r'-RD$25.00');
  });

  test('cantidades sin ceros de más', () {
    expect(formatQuantity(2000), '2');
    expect(formatQuantity(1500), '1.5');
    expect(formatQuantity(500), '0.5');
    expect(formatQuantity(1250), '1.25');
  });

  test('los días se leen en español', () {
    expect(formatDay('2026-09-11'), 'viernes 11 de septiembre');
    expect(formatDay('no es fecha'), 'no es fecha');

    final now = DateTime(2026, 9, 11, 20, 30);
    expect(formatDayLabel('2026-09-11', now), 'Hoy');
    expect(formatDayLabel('2026-09-10', now), 'Ayer');
    expect(formatDayLabel('2026-09-08', now), 'martes 8 de septiembre');
  });

  test('hora y formas de pago', () {
    expect(formatTime(DateTime(2026, 9, 11, 9, 5)), '09:05');
    expect(paymentLabel('cash'), 'Efectivo');
    expect(paymentLabel('credit'), 'Fiao');
    expect(paymentLabel('card'), 'Tarjeta');
    expect(paymentLabel('transfer'), 'Transferencia');
  });
}
