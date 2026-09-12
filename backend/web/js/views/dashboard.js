// Resumen del dueño o gerente: el día en números, la caja y lo que requiere atención.

import { h, mount } from '../dom.js';
import { formatMoney, formatQuantity, parseMoney, unitLabel } from '../money.js';
import { emptyState, field, paymentLabel, withBusy } from '../ui.js';

function tile(label, value, detail = null) {
  return h('div', { class: 'tile' }, h('span', { class: 'muted' }, label), h('span', { class: 'value' }, value), detail && h('small', { class: 'muted' }, detail));
}

export function renderDashboard(root, { api, notify }) {
  let disposed = false;
  let reloadTimer = null;

  async function load() {
    try {
      const [dashboard, lowStock, receivables] = await Promise.all([
        api.call('reports.dashboard'),
        api.call('inventory.lowStock'),
        api.call('reports.receivables'),
      ]);
      if (!disposed) {
        render(dashboard, lowStock, receivables);
      }
    } catch (error) {
      notify(error.message, 'error');
    }
  }

  function scheduleReload() {
    clearTimeout(reloadTimer);
    reloadTimer = setTimeout(load, 500);
  }

  function cashBlock(session) {
    if (!session) {
      return h('div', { class: 'panel' }, h('h2', {}, 'Caja'), h('p', { class: 'muted' }, 'La caja está cerrada. Se abre desde la pantalla Vender.'));
    }
    const counted = h('input', { inputmode: 'decimal', placeholder: formatMoney(session.expectedCashCents), 'aria-label': 'Efectivo contado' });
    const button = h(
      'button',
      {
        class: 'primary',
        type: 'button',
        onClick: () =>
          withBusy(button, async () => {
            const cents = parseMoney(counted.value);
            if (cents === null || cents < 0) {
              notify('Escribe el efectivo que contaste', 'error');
              return;
            }
            try {
              const closed = await api.call('cash.close', { countedCashCents: cents });
              const difference = closed.differenceCents;
              notify(
                difference === 0
                  ? 'Caja cerrada: cuadró exacto'
                  : `Caja cerrada con ${difference > 0 ? 'sobrante' : 'faltante'} de ${formatMoney(Math.abs(difference))}`,
                difference === 0 ? 'info' : 'error',
              );
              await load();
            } catch (error) {
              notify(error.message, 'error');
            }
          }),
      },
      'Cerrar caja',
    );
    return h(
      'div',
      { class: 'panel field' },
      h('h2', {}, 'Caja abierta'),
      h('p', {}, 'Debe haber ', h('strong', {}, formatMoney(session.expectedCashCents)), ' en efectivo.'),
      field('Efectivo contado', counted),
      button,
    );
  }

  function backupButton() {
    const button = h(
      'button',
      {
        type: 'button',
        onClick: () =>
          withBusy(button, async () => {
            try {
              const result = await api.call('system.backup', {});
              notify(`Respaldo guardado en ${result.path}`);
            } catch (error) {
              notify(error.message, 'error');
            }
          }),
      },
      'Hacer respaldo',
    );
    return button;
  }

  function render(dashboard, lowStock, receivables) {
    const sales = dashboard.sales;
    mount(
      root,
      h(
        'section',
        { class: 'field' },
        h(
          'div',
          { class: 'row' },
          h('h1', {}, `Resumen del ${dashboard.day}`),
          h('span', { class: 'spacer' }),
          api.user.role === 'owner' ? backupButton() : null,
        ),
        h(
          'div',
          { class: 'card-grid' },
          tile('Ventas', formatMoney(sales.totalCents), `${sales.count} tickets · promedio ${formatMoney(sales.averageTicketCents)}`),
          tile('ITBIS cobrado', formatMoney(sales.taxCents)),
          tile('Propina legal', formatMoney(sales.tipCents)),
          tile('Fiao por cobrar', formatMoney(dashboard.receivablesCents)),
          tile('Anuladas', String(dashboard.voidedSales)),
          tile('Órdenes abiertas', String(dashboard.openOrders)),
        ),
        h(
          'div',
          { class: 'pos' },
          h(
            'div',
            { class: 'field' },
            h(
              'div',
              { class: 'panel' },
              h('h2', {}, 'Lo más vendido hoy'),
              dashboard.topProducts.length
                ? h(
                    'table',
                    { class: 'list' },
                    h('thead', {}, h('tr', {}, h('th', {}, 'Producto'), h('th', { class: 'num' }, 'Cantidad'), h('th', { class: 'num' }, 'Vendido'))),
                    h(
                      'tbody',
                      {},
                      dashboard.topProducts.map((product) =>
                        h(
                          'tr',
                          {},
                          h('td', {}, product.description),
                          h('td', { class: 'num' }, formatQuantity(product.quantityMilli)),
                          h('td', { class: 'num' }, formatMoney(product.netCents)),
                        ),
                      ),
                    ),
                  )
                : emptyState('Todavía no hay ventas hoy'),
            ),
            h(
              'div',
              { class: 'panel' },
              h('h2', {}, 'Bajo el mínimo'),
              lowStock.length
                ? lowStock.map((product) =>
                    h('p', {}, h('strong', {}, product.name), ` · quedan ${formatQuantity(product.stockMilli)} ${unitLabel(product.unit)}`),
                  )
                : emptyState('Inventario en orden'),
            ),
            h(
              'div',
              { class: 'panel' },
              h('h2', {}, 'Clientes que deben'),
              receivables.customers.length
                ? receivables.customers.slice(0, 10).map((customer) =>
                    h('p', {}, h('strong', {}, customer.name), ` · ${formatMoney(customer.balanceCents)}`, customer.phone ? ` · ${customer.phone}` : ''),
                  )
                : emptyState('Nadie debe'),
            ),
          ),
          h(
            'div',
            { class: 'field' },
            cashBlock(dashboard.openCashSession),
            h(
              'div',
              { class: 'panel' },
              h('h2', {}, 'Cobros de hoy'),
              dashboard.payments.length
                ? dashboard.payments.map((payment) => h('p', {}, `${paymentLabel(payment.method)}: `, h('strong', {}, formatMoney(payment.amountCents))))
                : emptyState('Sin cobros'),
            ),
          ),
        ),
      ),
    );
  }

  mount(root, emptyState('Cargando resumen…'));
  load();
  const unsubscribe = api.subscribe((change) => {
    if (/^(sales|cash|customers|inventory|restaurant)\./.test(change.method)) {
      scheduleReload();
    }
  });
  return () => {
    disposed = true;
    clearTimeout(reloadTimer);
    unsubscribe();
  };
}
