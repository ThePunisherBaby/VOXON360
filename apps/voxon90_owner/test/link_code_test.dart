import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:voxon90_owner/domain/link_code.dart';

void main() {
  test('el código evita letras y números que se confunden', () {
    for (var i = 0; i < 200; i++) {
      final code = generateLinkCode();
      expect(code, hasLength(linkCodeLength));
      expect(RegExp(r'^[A-HJ-NP-Z2-9]+$').hasMatch(code), isTrue, reason: code);
    }
  });

  test('con la misma semilla sale el mismo código', () {
    expect(generateLinkCode(Random(7)), generateLinkCode(Random(7)));
  });

  test('se muestra en dos grupos para dictarlo', () {
    expect(formatLinkCode('ABCD2345'), 'ABCD-2345');
    expect(formatLinkCode('CORTO'), 'CORTO');
  });

  test('la cuenta regresiva termina al vencer', () {
    final now = DateTime(2026, 9, 11, 15);
    expect(
      timeLeft(now.add(const Duration(minutes: 14, seconds: 5)), now),
      isNotNull,
    );
    expect(
      formatCountdown(
        timeLeft(now.add(const Duration(minutes: 14, seconds: 5)), now)!,
      ),
      '14:05',
    );
    expect(formatCountdown(const Duration(seconds: 9)), '00:09');
    expect(timeLeft(now.subtract(const Duration(seconds: 1)), now), isNull);
    expect(timeLeft(now, now), isNull);
  });

  test('el vínculo dura menos de los 30 minutos que aceptan las reglas', () {
    expect(linkCodeLifetime, lessThan(const Duration(minutes: 30)));
  });
}
