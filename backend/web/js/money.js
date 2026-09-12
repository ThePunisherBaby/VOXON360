// Montos en centavos enteros y cantidades en milésimas, igual que el motor C++.
// El formato se hace a mano para que sea idéntico en cualquier navegador.

function assertInteger(value, what) {
  if (!Number.isSafeInteger(value)) {
    throw new TypeError(`El ${what} debe ser un número entero`);
  }
}

/** 125075 → "RD$1,250.75" */
export function formatMoney(cents) {
  assertInteger(cents, 'monto en centavos');
  const sign = cents < 0 ? '-' : '';
  const abs = Math.abs(cents);
  const whole = Math.trunc(abs / 100)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  const fraction = String(abs % 100).padStart(2, '0');
  return `${sign}RD$${whole}.${fraction}`;
}

/** "1,250.75", "RD$ 99" o "150.5" → centavos; null si no es un monto válido. */
export function parseMoney(text) {
  const normalized = String(text ?? '').replace(/RD\$|\$|,|\s/gi, '');
  const match = /^(-?)(\d+)(?:\.(\d{1,2}))?$/.exec(normalized);
  if (!match) {
    return null;
  }
  const cents = Number(match[2]) * 100 + Number((match[3] ?? '').padEnd(2, '0'));
  if (!Number.isSafeInteger(cents)) {
    return null;
  }
  return match[1] === '-' ? -cents : cents;
}

/** 500 → "0.5", 1250 → "1.25", 3000 → "3" */
export function formatQuantity(milli) {
  assertInteger(milli, 'cantidad en milésimas');
  const sign = milli < 0 ? '-' : '';
  const abs = Math.abs(milli);
  const whole = Math.trunc(abs / 1000);
  const fraction = abs % 1000;
  if (fraction === 0) {
    return `${sign}${whole}`;
  }
  return `${sign}${whole}.${String(fraction).padStart(3, '0').replace(/0+$/, '')}`;
}

/** "0.5" → 500; null si no es una cantidad válida (hasta tres decimales). */
export function parseQuantity(text) {
  const match = /^(\d+)(?:\.(\d{1,3}))?$/.exec(String(text ?? '').trim());
  if (!match) {
    return null;
  }
  const milli = Number(match[1]) * 1000 + Number((match[2] ?? '').padEnd(3, '0'));
  return Number.isSafeInteger(milli) ? milli : null;
}

const UNIT_LABELS = { unit: 'und', pound: 'lb', kilogram: 'kg', ounce: 'oz', liter: 'L' };

/** "pound" → "lb" */
export function unitLabel(unit) {
  return UNIT_LABELS[unit] ?? unit;
}

/** Importe estimado de una línea: precio × cantidad, redondeado al centavo. */
export function lineAmount(unitPriceCents, quantityMilli) {
  assertInteger(unitPriceCents, 'precio');
  assertInteger(quantityMilli, 'cantidad');
  return Math.round((unitPriceCents * quantityMilli) / 1000);
}
