// Carrito de venta. Solo guarda productos y cantidades: los totales oficiales
// (ITBIS, descuentos, propina) los calcula el motor con sales.quote.

import { lineAmount } from './money.js';

export class Cart {
  #lines = [];

  /** Copia de las líneas: {productId, name, unit, unitPriceCents, allowsFraction, quantityMilli}. */
  get lines() {
    return this.#lines.map((line) => ({ ...line }));
  }

  get isEmpty() {
    return this.#lines.length === 0;
  }

  /**
   * Agrega un producto del catálogo (como lo devuelve catalog.products.list).
   * Si ya está en el carrito, suma la cantidad.
   */
  add(product, quantityMilli = 1000) {
    validateQuantity(product, quantityMilli);
    const existing = this.#lines.find((line) => line.productId === product.id);
    if (existing) {
      existing.quantityMilli += quantityMilli;
      return;
    }
    this.#lines.push({
      productId: product.id,
      name: product.name,
      unit: product.unit,
      unitPriceCents: product.priceCents,
      allowsFraction: Boolean(product.allowsFraction),
      quantityMilli,
    });
  }

  /** Cambia la cantidad; cero la quita del carrito. */
  setQuantity(productId, quantityMilli) {
    const line = this.#lines.find((item) => item.productId === productId);
    if (!line) {
      return;
    }
    if (quantityMilli === 0) {
      this.remove(productId);
      return;
    }
    validateQuantity({ name: line.name, allowsFraction: line.allowsFraction }, quantityMilli);
    line.quantityMilli = quantityMilli;
  }

  remove(productId) {
    this.#lines = this.#lines.filter((line) => line.productId !== productId);
  }

  clear() {
    this.#lines = [];
  }

  /** Líneas para sales.quote y sales.complete. */
  toSaleLines() {
    return this.#lines.map(({ productId, quantityMilli }) => ({ productId, quantityMilli }));
  }

  /** Suma de precios × cantidades mientras llega la cotización del motor. */
  estimatedGrossCents() {
    return this.#lines.reduce((total, line) => total + lineAmount(line.unitPriceCents, line.quantityMilli), 0);
  }
}

function validateQuantity(product, quantityMilli) {
  if (!Number.isSafeInteger(quantityMilli) || quantityMilli <= 0) {
    throw new RangeError('La cantidad debe ser mayor que cero');
  }
  if (!product.allowsFraction && quantityMilli % 1000 !== 0) {
    throw new RangeError(`${product.name} se vende por unidades enteras`);
  }
}
