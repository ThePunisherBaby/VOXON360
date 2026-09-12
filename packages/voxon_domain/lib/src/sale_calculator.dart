import 'package:voxon_domain/src/discount.dart';
import 'package:voxon_domain/src/money.dart';
import 'package:voxon_domain/src/quantity.dart';
import 'package:voxon_domain/src/tax_rate.dart';

/// Cómo están expresados los precios de los productos.
enum PriceMode {
  /// El precio ya incluye el ITBIS. Es lo habitual en colmados y tiendas.
  taxIncluded,

  /// El ITBIS se suma al precio. Es lo habitual en los menús de restaurante.
  taxExcluded,
}

/// Una línea de la venta tal como la arma el cajero.
final class SaleLineInput {
  const SaleLineInput({
    required this.unitPrice,
    required this.quantity,
    required this.taxRate,
    this.discount,
  });

  final Money unitPrice;
  final Quantity quantity;
  final TaxRate taxRate;
  final Discount? discount;
}

/// Montos de una línea, expresados según el [PriceMode] de la venta.
final class LineTotals {
  const LineTotals({
    required this.gross,
    required this.lineDiscount,
    required this.orderDiscount,
    required this.taxRate,
  });

  /// Precio por cantidad.
  final Money gross;

  /// Descuento propio de la línea.
  final Money lineDiscount;

  /// Parte del descuento general de la venta que le toca a esta línea.
  final Money orderDiscount;

  final TaxRate taxRate;

  Money get net => gross - lineDiscount - orderDiscount;
}

/// Base imponible e ITBIS de todas las líneas con la misma tasa.
final class TaxGroup {
  const TaxGroup({
    required this.rate,
    required this.taxableBase,
    required this.tax,
  });

  final TaxRate rate;
  final Money taxableBase;
  final Money tax;
}

/// Totales de una venta.
final class SaleTotals {
  const SaleTotals({
    required this.lines,
    required this.taxGroups,
    required this.tip,
  });

  final List<LineTotals> lines;

  /// Un grupo por cada tasa presente en la venta, en el orden de [TaxRate.values].
  final List<TaxGroup> taxGroups;

  /// Propina legal. No lleva ITBIS.
  final Money tip;

  Money get discount =>
      Money.sum(lines.map((line) => line.lineDiscount + line.orderDiscount));

  /// Suma de las bases imponibles, sin ITBIS ni propina.
  Money get subtotal => Money.sum(taxGroups.map((group) => group.taxableBase));

  Money get tax => Money.sum(taxGroups.map((group) => group.tax));

  Money get total => subtotal + tax + tip;
}

/// Calcula los totales de una venta con las reglas fiscales dominicanas.
///
/// - Los descuentos se aplican antes del ITBIS. El descuento general se
///   reparte entre las líneas en proporción a su importe.
/// - El ITBIS se calcula por tasa sobre el monto agrupado, no línea por
///   línea, para que el impuesto cuadre con los montos gravados del e-CF.
/// - La propina legal se calcula sobre la base sin ITBIS y no paga ITBIS
///   (Código de Trabajo, art. 228).
abstract final class SaleCalculator {
  /// Propina legal de los establecimientos de comida y bebida: 10 %.
  static const legalTipBasisPoints = 1000;

  static SaleTotals calculate({
    required List<SaleLineInput> lines,
    required PriceMode priceMode,
    Discount? orderDiscount,
    int tipBasisPoints = 0,
  }) {
    for (final line in lines) {
      if (line.unitPrice.isNegative || line.quantity.isNegative) {
        throw ArgumentError.value(
          line,
          'lines',
          'El precio y la cantidad no pueden ser negativos',
        );
      }
    }
    if (tipBasisPoints < 0) {
      throw ArgumentError.value(
        tipBasisPoints,
        'tipBasisPoints',
        'La propina no puede ser negativa',
      );
    }

    final gross = [
      for (final line in lines) line.quantity.times(line.unitPrice),
    ];
    final lineDiscounts = [
      for (var i = 0; i < lines.length; i++)
        lines[i].discount?.applyTo(gross[i]) ?? Money.zero,
    ];
    final afterLineDiscount = [
      for (var i = 0; i < lines.length; i++) gross[i] - lineDiscounts[i],
    ];

    final pool = Money.sum(afterLineDiscount);
    final orderShares = pool.isZero
        ? List.filled(lines.length, Money.zero)
        : (orderDiscount?.applyTo(pool) ?? Money.zero).allocate([
            for (final amount in afterLineDiscount) amount.cents,
          ]);

    final lineTotals = [
      for (var i = 0; i < lines.length; i++)
        LineTotals(
          gross: gross[i],
          lineDiscount: lineDiscounts[i],
          orderDiscount: orderShares[i],
          taxRate: lines[i].taxRate,
        ),
    ];

    final taxGroups = [
      for (final rate in TaxRate.values)
        if (lineTotals.any((line) => line.taxRate == rate))
          _taxGroup(
            rate,
            Money.sum(
              lineTotals
                  .where((line) => line.taxRate == rate)
                  .map((line) => line.net),
            ),
            priceMode,
          ),
    ];
    final subtotal = Money.sum(taxGroups.map((group) => group.taxableBase));

    return SaleTotals(
      lines: lineTotals,
      taxGroups: taxGroups,
      tip: subtotal.percent(tipBasisPoints),
    );
  }

  static TaxGroup _taxGroup(TaxRate rate, Money net, PriceMode priceMode) {
    switch (priceMode) {
      case PriceMode.taxIncluded:
        final base = net.multiplyRatio(10000, 10000 + rate.basisPoints);
        return TaxGroup(rate: rate, taxableBase: base, tax: net - base);
      case PriceMode.taxExcluded:
        return TaxGroup(
          rate: rate,
          taxableBase: net,
          tax: net.percent(rate.basisPoints),
        );
    }
  }
}
