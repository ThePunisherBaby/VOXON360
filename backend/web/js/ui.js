// Piezas de interfaz que comparten las pantallas.

import { h } from './dom.js';

export function field(label, control, hint = null) {
  return h('label', { class: 'field' }, h('span', { class: 'field-label' }, label), control, hint && h('small', { class: 'muted' }, hint));
}

export function option(value, label, selected = false) {
  return h('option', { value, selected }, label);
}

export function emptyState(text) {
  return h('p', { class: 'empty' }, text);
}

export function errorText() {
  return h('p', { class: 'form-error', role: 'alert' });
}

/** Desactiva el botón mientras corre la acción, para evitar cobros dobles. */
export async function withBusy(button, action) {
  button.disabled = true;
  try {
    return await action();
  } finally {
    button.disabled = false;
  }
}

const timeFormat = new Intl.DateTimeFormat('es-DO', { hour: '2-digit', minute: '2-digit' });

export function formatTime(iso) {
  return iso ? timeFormat.format(new Date(iso)) : '';
}

/** Minutos enteros transcurridos desde una fecha ISO. */
export function minutesSince(iso, now = Date.now()) {
  const time = Date.parse(iso);
  return Number.isNaN(time) ? 0 : Math.max(0, Math.floor((now - time) / 60000));
}

const PAYMENT_LABELS = { cash: 'Efectivo', card: 'Tarjeta', transfer: 'Transferencia', credit: 'Fiao' };

export function paymentLabel(method) {
  return PAYMENT_LABELS[method] ?? method;
}

const ROLE_LABELS = { owner: 'Dueño', manager: 'Gerente', cashier: 'Cajero', waiter: 'Mesero', kitchen: 'Cocina' };

export function roleLabel(role) {
  return ROLE_LABELS[role] ?? role;
}
