import 'dart:math';

/// Alfabeto sin 0, O, 1 ni I, para dictar el código sin equivocarse. Debe
/// coincidir con `CloudSync.LINK_CODE` del servidor (backend/server).
const linkCodeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const linkCodeLength = 8;

/// Las reglas de Firestore no aceptan códigos que duren más de 30 minutos.
const linkCodeLifetime = Duration(minutes: 15);

String generateLinkCode([Random? random]) {
  final source = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < linkCodeLength; i++)
      linkCodeAlphabet.codeUnitAt(source.nextInt(linkCodeAlphabet.length)),
  ]);
}

/// "ABCD-2345": más fácil de leer en voz alta. La caja acepta las dos formas.
String formatLinkCode(String code) => code.length == linkCodeLength
    ? '${code.substring(0, 4)}-${code.substring(4)}'
    : code;

/// Lo que falta para que venza, o null si ya venció.
Duration? timeLeft(DateTime expiresAt, DateTime now) {
  final left = expiresAt.difference(now);
  return left.isNegative || left == Duration.zero ? null : left;
}

/// "14:05" para una cuenta regresiva.
String formatCountdown(Duration left) {
  final minutes = left.inMinutes.toString().padLeft(2, '0');
  final seconds = (left.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
