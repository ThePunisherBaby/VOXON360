import 'package:voxon_domain/voxon_domain.dart';

final _thousands = RegExp(r'\B(?=(\d{3})+(?!\d))');

/// 125075 → "RD$1,250.75"
String formatMoney(int cents) {
  final parts = Money.cents(cents.abs()).toDecimalString().split('.');
  final whole = parts[0].replaceAllMapped(_thousands, (_) => ',');
  return '${cents < 0 ? '-' : ''}RD\$$whole.${parts[1]}';
}

/// 500 → "0.5"
String formatQuantity(int milli) => Quantity.milli(milli).toDecimalString();

/// "1,250.75" o "RD$ 99" → centavos; null si no es un monto.
int? parseMoney(String text) => Money.tryParse(text)?.cents;

/// "0.5" o "0,5" → milésimas; null si no es una cantidad mayor que cero.
int? parseQuantity(String text) {
  final milli = Quantity.tryParse(text.trim().replaceAll(',', '.'))?.milli;
  return milli == null || milli <= 0 ? null : milli;
}

/// Abreviatura de la unidad de venta.
String unitLabel(String unit) => switch (unit) {
  'pound' => 'lb',
  'kilogram' => 'kg',
  'ounce' => 'oz',
  'liter' => 'L',
  _ => 'und',
};
