// Punto de venta: buscar o escanear, armar la venta y cobrar.
// Los totales oficiales (ITBIS, propina) siempre vienen del motor (sales.quote).

import { Cart } from '../cart.js';
import { h, mount } from '../dom.js';
import { formatMoney, formatQuantity, lineAmount, parseMoney, parseQuantity, unitLabel } from '../money.js';
import { emptyState, field, paymentLabel, withBusy } from '../ui.js';

const METHODS = ['cash', 'card', 'transfer', 'credit'];

export function renderPos(root, { api, notify }) {
  const cart = new Cart();
  const state = {
    products: [],
    session: undefined,
    quote: null,
    quoteError: null,
    method: 'cash',
    received: '',
    customer: null,
    lastSale: null,
  };
  let disposed = false;
  let quoteSequence = 0;
  let quoteTimer = null;
  let searchTimer = null;

  const searchInput = h('input', {
    type: 'search',
    placeholder: 'Buscar producto o escanear código',
    autocomplete: 'off',
    'aria-label': 'Buscar producto',
  });
  const grid = h('div', { class: 'product-grid' });
  const cartPanel = h('aside', { class: 'panel cart', 'aria-label': 'Venta actual' });

  // --- Catálogo -----------------------------------------------------------------

  async function loadProducts() {
    try {
      state.products = await api.call('catalog.products.list', { search: searchInput.value, limit: 60 });
      if (!disposed) {
        renderGrid();
      }
    } catch (error) {
      notify(error.message, 'error');
    }
  }

  function renderGrid() {
    if (!state.products.length) {
      mount(grid, emptyState('No hay productos que coincidan'));
      return;
    }
    mount(
      grid,
      state.products.map((product) =>
        h(
          'button',
          { class: 'product', type: 'button', onClick: () => addProduct(product) },
          h('strong', {}, product.name),
          h('span', {}, formatMoney(product.priceCents), product.unit === 'unit' ? '' : ` / ${unitLabel(product.unit)}`),
          product.trackStock
            ? h(
                'small',
                { class: product.availableMilli <= product.minStockMilli ? 'badge warn' : 'muted' },
                `Quedan ${formatQuantity(product.availableMilli)}`,
              )
            : null,
        ),
      ),
    );
  }

  function addProduct(product) {
    try {
      cart.add(product, 1000);
      state.lastSale = null;
      cartChanged();
    } catch (error) {
      notify(error.message, 'error');
    }
  }

  // Un lector de código de barras escribe el código y presiona Enter.
  searchInput.addEventListener('keydown', async (event) => {
    if (event.key !== 'Enter' || !searchInput.value.trim()) {
      return;
    }
    event.preventDefault();
    try {
      const product = await api.call('catalog.products.get', { barcode: searchInput.value.trim() });
      addProduct(product);
      searchInput.value = '';
      loadProducts();
    } catch {
      loadProducts();
    }
  });
  searchInput.addEventListener('input', () => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(loadProducts, 200);
  });

  // --- Venta ----------------------------------------------------------------------

  function cartChanged() {
    renderCart();
    clearTimeout(quoteTimer);
    if (cart.isEmpty) {
      state.quote = null;
      state.quoteError = null;
      renderCart();
      return;
    }
    const sequence = ++quoteSequence;
    quoteTimer = setTimeout(async () => {
      try {
        const quote = await api.call('sales.quote', { lines: cart.toSaleLines() });
        if (sequence === quoteSequence) {
          state.quote = quote;
          state.quoteError = null;
        }
      } catch (error) {
        if (sequence === quoteSequence) {
          state.quote = null;
          state.quoteError = error.message;
        }
      }
      if (!disposed && sequence === quoteSequence) {
        renderCart();
      }
    }, 200);
  }

  function setQuantity(productId, quantityMilli) {
    try {
      cart.setQuantity(productId, quantityMilli);
      cartChanged();
    } catch (error) {
      notify(error.message, 'error');
    }
  }

  function quantityControl(line) {
    if (line.allowsFraction) {
      return h(
        'div',
        { class: 'qty' },
        h('input', {
          value: formatQuantity(line.quantityMilli),
          inputmode: 'decimal',
          'aria-label': `Cantidad de ${line.name}`,
          onChange: (event) => {
            const quantity = parseQuantity(event.target.value.replace(',', '.'));
            if (quantity) {
              setQuantity(line.productId, quantity);
            } else {
              notify('Cantidad inválida', 'error');
              renderCart();
            }
          },
        }),
        h('span', { class: 'muted' }, unitLabel(line.unit)),
      );
    }
    return h(
      'div',
      { class: 'qty' },
      h('button', { type: 'button', 'aria-label': `Quitar un ${line.name}`, onClick: () => setQuantity(line.productId, line.quantityMilli - 1000) }, '−'),
      h('span', {}, formatQuantity(line.quantityMilli)),
      h('button', { type: 'button', 'aria-label': `Agregar un ${line.name}`, onClick: () => setQuantity(line.productId, line.quantityMilli + 1000) }, '+'),
    );
  }

  function totalsBlock() {
    if (state.quoteError) {
      return h('p', { class: 'form-error' }, state.quoteError);
    }
    if (!state.quote) {
      return h('p', { class: 'muted' }, cart.isEmpty ? 'Agrega productos para vender' : `Calculando… ${formatMoney(cart.estimatedGrossCents())}`);
    }
    const quote = state.quote;
    return h(
      'div',
      { class: 'totals' },
      h('span', {}, 'Subtotal'),
      h('span', {}, formatMoney(quote.subtotalCents)),
      h('span', {}, 'ITBIS'),
      h('span', {}, formatMoney(quote.taxCents)),
      quote.tipCents ? [h('span', {}, 'Propina legal'), h('span', {}, formatMoney(quote.tipCents))] : null,
      h('span', { class: 'grand' }, 'Total'),
      h('span', { class: 'grand' }, formatMoney(quote.totalCents)),
    );
  }

  function customerPicker() {
    if (state.customer) {
      return h(
        'p',
        {},
        'Fiao a ',
        h('strong', {}, state.customer.name),
        ` (disponible ${formatMoney(state.customer.availableCreditCents)}) `,
        h('button', { class: 'link', type: 'button', onClick: () => { state.customer = null; renderCart(); } }, 'Cambiar'),
      );
    }
    const results = h('div', { class: 'row' });
    let timer = null;
    const input = h('input', {
      type: 'search',
      placeholder: 'Buscar cliente por nombre o teléfono',
      'aria-label': 'Cliente del fiao',
      onInput: () => {
        clearTimeout(timer);
        timer = setTimeout(async () => {
          try {
            const customers = await api.call('customers.list', { search: input.value, limit: 8 });
            mount(
              results,
              customers.map((customer) =>
                h(
                  'button',
                  { type: 'button', onClick: () => { state.customer = customer; renderCart(); } },
                  `${customer.name} · ${formatMoney(customer.availableCreditCents)}`,
                ),
              ),
            );
          } catch (error) {
            notify(error.message, 'error');
          }
        }, 200);
      },
    });
    return [input, results];
  }

  function paymentBlock() {
    const total = state.quote?.totalCents ?? null;
    const methodButtons = h(
      'div',
      { class: 'pay-methods', role: 'group', 'aria-label': 'Forma de pago' },
      METHODS.map((method) =>
        h(
          'button',
          { type: 'button', 'aria-pressed': String(state.method === method), onClick: () => { state.method = method; renderCart(); } },
          paymentLabel(method),
        ),
      ),
    );

    const changeText = h('strong', {});
    const updateChange = () => {
      const received = state.received.trim() === '' ? total : parseMoney(state.received);
      changeText.textContent =
        total === null || received === null ? '' : received >= total ? `Devuelta: ${formatMoney(received - total)}` : `Faltan ${formatMoney(total - received)}`;
    };

    let extra = null;
    if (state.method === 'cash') {
      extra = [
        field(
          'Efectivo recibido',
          h('input', {
            value: state.received,
            inputmode: 'decimal',
            placeholder: total === null ? '' : formatMoney(total),
            onInput: (event) => {
              state.received = event.target.value;
              updateChange();
            },
          }),
        ),
        changeText,
      ];
      updateChange();
    } else if (state.method === 'credit') {
      extra = customerPicker();
    }

    const chargeButton = h(
      'button',
      { class: 'primary', type: 'button', disabled: total === null, onClick: () => charge(chargeButton) },
      total === null ? 'Cobrar' : `Cobrar ${formatMoney(total)}`,
    );
    return [methodButtons, extra, chargeButton];
  }

  async function charge(button) {
    const total = state.quote?.totalCents;
    if (total === undefined || total === null) {
      return;
    }
    let payments;
    if (state.method === 'cash') {
      const received = state.received.trim() === '' ? total : parseMoney(state.received);
      if (received === null || received < total) {
        notify('El efectivo recibido no cubre el total', 'error');
        return;
      }
      payments = [{ method: 'cash', amountCents: received }];
    } else {
      if (state.method === 'credit' && !state.customer) {
        notify('Elige el cliente del fiao', 'error');
        return;
      }
      payments = total === 0 ? [] : [{ method: state.method, amountCents: total }];
    }

    await withBusy(button, async () => {
      try {
        const sale = await api.call('sales.complete', {
          lines: cart.toSaleLines(),
          payments,
          customerId: state.method === 'credit' ? state.customer.id : undefined,
        });
        cart.clear();
        Object.assign(state, { lastSale: sale, quote: null, received: '', customer: null, method: 'cash' });
        notify(`Venta #${sale.number} cobrada`);
        renderCart();
        loadProducts();
      } catch (error) {
        notify(error.message, 'error');
      }
    });
  }

  // --- Caja -----------------------------------------------------------------------

  async function loadSession() {
    try {
      state.session = await api.call('cash.current');
    } catch (error) {
      notify(error.message, 'error');
    }
    if (!disposed) {
      renderCart();
    }
  }

  function openCashForm() {
    const amount = h('input', { inputmode: 'decimal', placeholder: 'RD$0.00', 'aria-label': 'Fondo de caja' });
    const button = h(
      'button',
      {
        class: 'primary',
        type: 'button',
        onClick: () =>
          withBusy(button, async () => {
            const cents = amount.value.trim() === '' ? 0 : parseMoney(amount.value);
            if (cents === null || cents < 0) {
              notify('Monto inválido', 'error');
              return;
            }
            try {
              await api.call('cash.open', { openingFloatCents: cents });
              notify('Caja abierta');
              await loadSession();
            } catch (error) {
              notify(error.message, 'error');
            }
          }),
      },
      'Abrir caja',
    );
    return [h('h2', {}, 'Abrir caja'), h('p', { class: 'muted' }, '¿Con cuánto efectivo empiezas?'), amount, button];
  }

  function receipt(sale) {
    return [
      h('h2', {}, `Venta #${sale.number}`),
      h(
        'div',
        { class: 'totals' },
        h('span', {}, 'Total'),
        h('span', { class: 'grand' }, formatMoney(sale.totalCents)),
        sale.changeCents ? [h('span', {}, 'Devuelta'), h('strong', {}, formatMoney(sale.changeCents))] : null,
      ),
      sale.payments.map((payment) => h('p', { class: 'muted' }, `${paymentLabel(payment.method)}: ${formatMoney(payment.amountCents)}`)),
      h('button', { class: 'primary', type: 'button', onClick: () => { state.lastSale = null; renderCart(); searchInput.focus(); } }, 'Nueva venta'),
    ];
  }

  function renderCart() {
    if (state.session === undefined) {
      mount(cartPanel, emptyState('Cargando caja…'));
      return;
    }
    if (state.session === null) {
      mount(cartPanel, openCashForm());
      return;
    }
    if (state.lastSale) {
      mount(cartPanel, receipt(state.lastSale));
      return;
    }
    const quoteLines = state.quote?.lines ?? [];
    mount(
      cartPanel,
      h('h2', {}, 'Venta actual'),
      cart.lines.map((line, index) =>
        h(
          'div',
          { class: 'cart-line' },
          h('span', {}, line.name),
          h('strong', {}, formatMoney(quoteLines[index]?.netCents ?? lineAmount(line.unitPriceCents, line.quantityMilli))),
          quantityControl(line),
          h('button', { class: 'link', type: 'button', onClick: () => { cart.remove(line.productId); cartChanged(); } }, 'Quitar'),
        ),
      ),
      totalsBlock(),
      cart.isEmpty ? null : paymentBlock(),
    );
  }

  mount(root, h('div', { class: 'pos' }, h('section', {}, searchInput, grid), cartPanel));
  renderCart();
  loadProducts();
  loadSession();
  searchInput.focus();

  const unsubscribe = api.subscribe((change) => {
    if (/^(catalog|inventory|sales)\./.test(change.method)) {
      loadProducts();
    }
    if (change.method.startsWith('cash.')) {
      loadSession();
    }
  });

  return () => {
    disposed = true;
    clearTimeout(quoteTimer);
    clearTimeout(searchTimer);
    unsubscribe();
  };
}
