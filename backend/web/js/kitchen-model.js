// Lógica de la pantalla de cocina, separada de la interfaz para poder probarla.

export const STATUS_LABELS = { sent: 'Nuevo', preparing: 'Preparando', ready: 'Listo', served: 'Servido' };

const NEXT_ACTIONS = { sent: ['preparing', 'ready'], preparing: ['ready'], ready: ['served'] };

/** Estados a los que puede pasar un producto; el motor no permite retroceder. */
export function nextActions(status) {
  return NEXT_ACTIONS[status] ?? [];
}

/** "Mesa 4", "Para llevar" o "Delivery". */
export function orderLabel(order) {
  if (order.orderKind === 'dine_in') {
    return order.tableName ?? 'Mesa';
  }
  return order.orderKind === 'takeout' ? 'Para llevar' : 'Delivery';
}

/**
 * Agrupa la cola de restaurant.kitchen.queue por orden, de la más antigua a
 * la más reciente, para atender primero lo que lleva más tiempo esperando.
 */
export function groupQueue(items) {
  const orders = new Map();
  for (const item of items) {
    let order = orders.get(item.orderId);
    if (!order) {
      order = {
        orderId: item.orderId,
        orderNumber: item.orderNumber,
        orderKind: item.orderKind,
        tableName: item.tableName,
        oldestSentAt: item.sentAt ?? null,
        items: [],
      };
      orders.set(item.orderId, order);
    }
    order.items.push(item);
    if (item.sentAt && (!order.oldestSentAt || item.sentAt < order.oldestSentAt)) {
      order.oldestSentAt = item.sentAt;
    }
  }
  return [...orders.values()].sort(
    (a, b) => (a.oldestSentAt ?? '').localeCompare(b.oldestSentAt ?? '') || a.orderNumber - b.orderNumber,
  );
}
