// Mesas y órdenes: el mesero abre la mesa, agrega productos y envía a cocina;
// el cajero (o el dueño) cobra la cuenta.

import { h, mount } from '../dom.js';
import { STATUS_LABELS } from '../kitchen-model.js';
import { formatMoney, formatQuantity, parseMoney, unitLabel } from '../money.js';
import { emptyState, field, paymentLabel, withBusy } from '../ui.js';

const CAN_CHARGE = ['owner', 'manager', 'cashier'];
const CAN_MANAGE = ['owner', 'manager'];

export function renderTables(root, { api, notify }) {
  const role = api.user.role;
  let disposed = false;
  let openOrderId = null;

  async function refresh() {
    if (disposed) {
      return;
    }
    if (openOrderId) {
      await showOrder(openOrderId);
    } else {
      await showFloor();
    }
  }

  // --- Salón ----------------------------------------------------------------------

  async function showFloor() {
    try {
      const [tables, orders] = await Promise.all([
        api.call('restaurant.tables.list'),
        api.call('restaurant.orders.list'),
      ]);
      if (disposed || openOrderId) {
        return;
      }
      const withoutTable = orders.filter((order) => !order.tableId);
      mount(
        root,
        h(
          'section',
          {},
          h(
            'div',
            { class: 'row' },
            h('h1', {}, 'Mesas'),
            h('span', { class: 'spacer' }),
            h('button', { type: 'button', onClick: () => openOrder({ kind: 'takeout' }) }, 'Para llevar'),
            h('button', { type: 'button', onClick: () => openOrder({ kind: 'delivery' }) }, 'Delivery'),
          ),
          tables.length
            ? h(
                'div',
                { class: 'card-grid' },
                tables.map((table) =>
                  h(
                    'button',
                    {
                      type: 'button',
                      class: `card ${table.orderId ? 'busy' : ''}`,
                      onClick: () => (table.orderId ? goToOrder(table.orderId) : openOrder({ kind: 'dine_in', tableId: table.id })),
                    },
                    h('h3', {}, table.name),
                    table.areaName ? h('span', { class: 'muted' }, table.areaName) : null,
                    table.orderId
                      ? [
                          h('span', { class: 'badge warn' }, `Orden #${table.orderNumber} · ${table.waiterName}`),
                          h('span', {}, `${table.itemCount} productos · ${formatMoney(table.grossCents)}`),
                        ]
                      : h('span', { class: 'badge ok' }, 'Libre'),
                  ),
                ),
              )
            : emptyState('No hay mesas registradas.'),
          CAN_MANAGE.includes(role) ? newTableForm() : null,
          withoutTable.length
            ? [
                h('h2', {}, 'Para llevar y delivery'),
                h(
                  'div',
                  { class: 'card-grid' },
                  withoutTable.map((order) =>
                    h(
                      'button',
                      { type: 'button', class: 'card busy', onClick: () => goToOrder(order.orderId) },
                      h('h3', {}, `#${order.number} · ${order.kind === 'takeout' ? 'Para llevar' : 'Delivery'}`),
                      h('span', {}, `${order.itemCount} productos · ${formatMoney(order.grossCents)}`),
                    ),
                  ),
                ),
              ]
            : null,
        ),
      );
    } catch (error) {
      notify(error.message, 'error');
    }
  }

  function newTableForm() {
    const name = h('input', { placeholder: 'Mesa 1', maxlength: 20, 'aria-label': 'Nombre de la mesa' });
    const button = h(
      'button',
      {
        type: 'button',
        onClick: () =>
          withBusy(button, async () => {
            try {
              await api.call('restaurant.tables.create', { name: name.value });
              notify('Mesa agregada');
              await showFloor();
            } catch (error) {
              notify(error.message, 'error');
            }
          }),
      },
      'Agregar mesa',
    );
    return h('div', { class: 'row panel' }, name, button);
  }

  async function openOrder(params) {
    try {
      const order = await api.call('restaurant.orders.open', params);
      goToOrder(order.id);
    } catch (error) {
      notify(error.message, 'error');
    }
  }

  function goToOrder(orderId) {
    openOrderId = orderId;
    showOrder(orderId);
  }

  // --- Orden ----------------------------------------------------------------------

  async function showOrder(orderId) {
    try {
      const order = await api.call('restaurant.orders.get', { id: orderId });
      if (disposed || openOrderId !== orderId) {
        return;
      }
      if (order.status !== 'open') {
        notify(order.status === 'closed' ? `Orden #${order.number} cobrada` : `Orden #${order.number} cancelada`);
        openOrderId = null;
        await showFloor();
        return;
      }
      renderOrder(order);
    } catch (error) {
      notify(error.message, 'error');
      openOrderId = null;
      await showFloor();
    }
  }

  function renderOrder(order) {
    const title = order.tableName ?? (order.kind === 'takeout' ? 'Para llevar' : 'Delivery');
    const pending = order.items.filter((item) => item.status === 'pending').length;
    const results = h('div', { class: 'product-grid' });
    let timer = null;
    const search = h('input', {
      type: 'search',
      placeholder: 'Agregar producto',
      'aria-label': 'Buscar producto para la orden',
      onInput: () => {
        clearTimeout(timer);
        timer = setTimeout(async () => {
          try {
            const products = await api.call('catalog.products.list', { search: search.value, limit: 24 });
            mount(
              results,
              products.map((product) =>
                h(
                  'button',
                  { type: 'button', class: 'product', onClick: () => addItem(order.id, product.id) },
                  h('strong', {}, product.name),
                  h('span', {}, formatMoney(product.priceCents), product.unit === 'unit' ? '' : ` / ${unitLabel(product.unit)}`),
                ),
              ),
            );
          } catch (error) {
            notify(error.message, 'error');
          }
        }, 200);
      },
    });

    const sendButton = h(
      'button',
      {
        class: 'primary',
        type: 'button',
        disabled: pending === 0,
        onClick: () =>
          withBusy(sendButton, async () => {
            try {
              const result = await api.call('restaurant.orders.send', { orderId: order.id });
              notify(result.tickets.length ? 'Comanda enviada' : 'Productos marcados como servidos');
              await showOrder(order.id);
            } catch (error) {
              notify(error.message, 'error');
            }
          }),
      },
      pending ? `Enviar ${pending} a cocina` : 'Nada por enviar',
    );

    mount(
      root,
      h(
        'div',
        { class: 'pos' },
        h(
          'section',
          {},
          h(
            'div',
            { class: 'row' },
            h('button', { type: 'button', onClick: () => { openOrderId = null; showFloor(); } }, '← Mesas'),
            h('h1', {}, `#${order.number} · ${title}`),
          ),
          search,
          results,
        ),
        h(
          'aside',
          { class: 'panel cart' },
          h('h2', {}, `Atiende ${order.waiterName}`),
          order.items.length
            ? order.items.map((item) =>
                h(
                  'div',
                  { class: 'cart-line' },
                  h('span', {}, `${formatQuantity(item.quantityMilli)} × ${item.productName}`),
                  h('strong', {}, formatMoney(item.grossCents)),
                  h('span', { class: `badge ${item.status === 'cancelled' ? 'danger' : ''}` }, STATUS_LABELS[item.status] ?? 'Cancelado'),
                  item.status === 'pending' || (CAN_MANAGE.includes(role) && !['served', 'cancelled'].includes(item.status))
                    ? h('button', { class: 'link', type: 'button', onClick: () => cancelItem(order.id, item.id) }, 'Quitar')
                    : h('span', {}),
                ),
              )
            : emptyState('Busca y agrega productos'),
          h(
            'div',
            { class: 'totals' },
            h('span', {}, 'ITBIS'),
            h('span', {}, formatMoney(order.estimate.taxCents)),
            order.estimate.tipCents ? [h('span', {}, 'Propina legal'), h('span', {}, formatMoney(order.estimate.tipCents))] : null,
            h('span', { class: 'grand' }, 'Cuenta'),
            h('span', { class: 'grand' }, formatMoney(order.estimate.totalCents)),
          ),
          sendButton,
          CAN_CHARGE.includes(role) && order.estimate.totalCents > 0 ? checkoutBlock(order) : null,
        ),
      ),
    );
  }

  async function addItem(orderId, productId) {
    try {
      await api.call('restaurant.orders.addItems', { orderId, items: [{ productId, quantityMilli: 1000 }] });
      await showOrder(orderId);
    } catch (error) {
      notify(error.message, 'error');
    }
  }

  async function cancelItem(orderId, itemId) {
    try {
      await api.call('restaurant.orders.cancelItem', { itemId });
      await showOrder(orderId);
    } catch (error) {
      notify(error.message, 'error');
    }
  }

  function checkoutBlock(order) {
    let method = 'cash';
    const received = h('input', { inputmode: 'decimal', placeholder: formatMoney(order.estimate.totalCents) });
    const receivedField = field('Efectivo recibido', received);
    const methods = h('div', { class: 'pay-methods', role: 'group', 'aria-label': 'Forma de pago' });
    const renderMethods = () => {
      mount(
        methods,
        ['cash', 'card', 'transfer'].map((value) =>
          h(
            'button',
            {
              type: 'button',
              'aria-pressed': String(method === value),
              onClick: () => {
                method = value;
                receivedField.hidden = method !== 'cash';
                renderMethods();
              },
            },
            paymentLabel(value),
          ),
        ),
      );
    };
    renderMethods();

    const button = h(
      'button',
      {
        class: 'primary',
        type: 'button',
        onClick: () =>
          withBusy(button, async () => {
            // La cuenta final la calcula el motor con los precios vigentes.
            const total = order.estimate.totalCents;
            let amount = total;
            if (method === 'cash' && received.value.trim() !== '') {
              amount = parseMoney(received.value);
              if (amount === null || amount < total) {
                notify('El efectivo recibido no cubre la cuenta', 'error');
                return;
              }
            }
            try {
              const result = await api.call('restaurant.orders.checkout', {
                orderId: order.id,
                payments: [{ method, amountCents: amount }],
              });
              const change = result.sale.changeCents ? ` · devuelta ${formatMoney(result.sale.changeCents)}` : '';
              notify(`Cobrada: ${formatMoney(result.sale.totalCents)}${change}`);
              openOrderId = null;
              await showFloor();
            } catch (error) {
              notify(error.message, 'error');
            }
          }),
      },
      'Cobrar cuenta',
    );
    return h('div', { class: 'field' }, h('h3', {}, 'Cobrar'), methods, receivedField, button);
  }

  showFloor();
  const unsubscribe = api.subscribe((change) => {
    if (change.method.startsWith('restaurant.')) {
      refresh();
    }
  });
  return () => {
    disposed = true;
    unsubscribe();
  };
}
