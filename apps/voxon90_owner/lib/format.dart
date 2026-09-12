/// Formatos en español dominicano, sin dependencias: montos en centavos y
/// cantidades en milésimas, igual que el motor.
library;

const _months = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

const _weekdays = [
  'lunes',
  'martes',
  'miércoles',
  'jueves',
  'viernes',
  'sábado',
  'domingo',
];

/// 125075 → "RD$1,250.75".
String formatMoney(int cents) {
  final negative = cents < 0;
  final value = cents.abs();
  final units = (value ~/ 100).toString();
  final decimals = (value % 100).toString().padLeft(2, '0');
  final buffer = StringBuffer();
  for (var i = 0; i < units.length; i++) {
    if (i > 0 && (units.length - i) % 3 == 0) buffer.write(',');
    buffer.write(units[i]);
  }
  return '${negative ? '-' : ''}RD\$$buffer.$decimals';
}

/// 1500 → "1.5"; 2000 → "2".
String formatQuantity(int milli) {
  final text = (milli / 1000).toStringAsFixed(3);
  return text.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// "2026-09-11" → "jueves 11 de septiembre".
String formatDay(String day) {
  final date = DateTime.tryParse(day);
  if (date == null) return day;
  return '${_weekdays[date.weekday - 1]} ${date.day} de ${_months[date.month - 1]}';
}

/// "2026-09-11" → "Hoy", "Ayer" o la fecha escrita.
String formatDayLabel(String day, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime.tryParse(day);
  if (date == null) return day;
  final difference = today
      .difference(DateTime(date.year, date.month, date.day))
      .inDays;
  return switch (difference) {
    0 => 'Hoy',
    1 => 'Ayer',
    _ => formatDay(day),
  };
}

/// "15:04" en la hora del celular.
String formatTime(DateTime moment) {
  final local = moment.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

/// Método de pago del motor en palabras.
String paymentLabel(String method) => switch (method) {
  'card' => 'Tarjeta',
  'transfer' => 'Transferencia',
  'credit' => 'Fiao',
  _ => 'Efectivo',
};
