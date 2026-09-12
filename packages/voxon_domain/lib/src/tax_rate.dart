/// Tasas de ITBIS vigentes en República Dominicana.
enum TaxRate {
  /// Exento: canasta básica (carnes frescas, huevos, arroz, habichuelas,
  /// víveres, leche fresca...).
  exempt(0),

  /// Tasa reducida: café, azúcar, aceites comestibles, mantequilla, yogur,
  /// cacao y chocolate.
  reduced(1600),

  /// Tasa general. También aplica a la comida servida en restaurantes.
  standard(1800);

  const TaxRate(this.basisPoints);

  /// Tasa en puntos básicos: `1800` equivale a 18 %.
  final int basisPoints;
}
