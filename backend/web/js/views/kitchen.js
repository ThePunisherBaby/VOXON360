// Pantalla de cocina y bar: lo enviado por los meseros, agrupado por orden.

import { h, mount } from '../dom.js';
import { groupQueue, nextActions, orderLabel, STATUS_LABELS } from '../kitchen-model.js';
import { formatQuantity } from '../money.js';
import { emptyState, minutesSince, withBusy } from '../ui.js';

const STATIONS = [
  { value: null, label: 'Todo' },
  { value: 'kitchen', label: 'Cocina' },
  { value: 'bar', label: 'Bar' },
];

export function renderKitchen(root, { api, notify }) {
  let station = null;
  let queue = [];
  let disposed = false;
  const filters = h('div', { class: 'row' });
  const board = h('div', { class: 'card-grid', 'aria-live': 'polite' });

  async function load() {
    try {
      queue = await api.call('restaurant.kitchen.queue', station ? { station } : {});
      if (!disposed) {
        renderBoard();
      }
    } catch (error) {
      notify(error.message, 'error');
    }
  }

  function renderFilters() {
    mount(
      filters,
      STATIONS.map((option) =>
        h(
          'button',
          {
            type: 'button',
            'aria-pressed': String(option.value === station),
            class: option.value === station ? 'primary' : null,
            onClick: () => {
              station = option.value;
              renderFilters();
              load();
            },
          },
          option.label,
        ),
      ),
    );
  }

  async function advance(button, item, status) {
    await withBusy(button, async () => {
      try {
        await api.call('restaurant.kitchen.updateItem', { itemId: item.itemId, status });
        await load();
      } catch (error) {
        notify(error.message, 'error');
      }
    });
  }

  function renderBoard() {
    const orders = groupQueue(queue);
    if (!orders.length) {
      mount(board, emptyState('No hay nada pendiente. ¡Todo al día!'));
      return;
    }
    mount(
      board,
      orders.map((order) => {
        const waited = minutesSince(order.oldestSentAt);
        return h(
          'article',
          { class: 'card' },
          h(
            'div',
            { class: 'row' },
            h('h3', {}, `#${order.orderNumber} · ${orderLabel(order)}`),
            h('span', { class: 'spacer' }),
            h('span', { class: `badge ${waited >= 20 ? 'danger' : waited >= 10 ? 'warn' : 'ok'}` }, `${waited} min`),
          ),
          order.items.map((item) =>
            h(
              'div',
              { class: 'cart-line' },
              h('strong', {}, `${formatQuantity(item.quantityMilli)} × ${item.productName}`),
              h('span', { class: 'badge' }, STATUS_LABELS[item.status] ?? item.status),
              item.notes ? h('span', { class: 'muted' }, item.notes) : null,
              h(
                'div',
                { class: 'row' },
                nextActions(item.status).map((status) => {
                  const button = h(
                    'button',
                    { type: 'button', class: status === 'ready' ? 'primary' : null, onClick: () => advance(button, item, status) },
                    STATUS_LABELS[status],
                  );
                  return button;
                }),
              ),
            ),
          ),
        );
      }),
    );
  }

  renderFilters();
  mount(root, h('section', {}, h('div', { class: 'row' }, h('h1', {}, 'Cocina'), h('span', { class: 'spacer' }), filters), board));
  load();

  const unsubscribe = api.subscribe((change) => {
    if (change.method.startsWith('restaurant.')) {
      load();
    }
  });
  // Refresca los minutos de espera y sirve de respaldo si se corta la conexión en vivo.
  const timer = setInterval(load, 20000);

  return () => {
    disposed = true;
    clearInterval(timer);
    unsubscribe();
  };
}
