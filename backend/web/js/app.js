// Arranque del cliente web: configuración inicial, ingreso con PIN y
// pantallas según el rol del empleado.

import { ApiClient } from './api.js';
import { h, mount, toast } from './dom.js';
import { renderDashboard } from './views/dashboard.js';
import { renderKitchen } from './views/kitchen.js';
import { renderLogin } from './views/login.js';
import { renderPos } from './views/pos.js';
import { renderSetup } from './views/setup.js';
import { renderTables } from './views/tables.js';

const api = new ApiClient({ storage: window.sessionStorage });
const root = document.getElementById('app');
const topbar = document.getElementById('topbar');

const ROUTES = {
  dashboard: { title: 'Resumen', render: renderDashboard, roles: ['owner', 'manager'] },
  pos: { title: 'Vender', render: renderPos, roles: ['owner', 'manager', 'cashier'] },
  tables: { title: 'Mesas', render: renderTables, roles: ['owner', 'manager', 'cashier', 'waiter'] },
  kitchen: { title: 'Cocina', render: renderKitchen, roles: ['owner', 'manager', 'waiter', 'kitchen'] },
};

const HOME_BY_ROLE = { owner: 'dashboard', manager: 'dashboard', cashier: 'pos', waiter: 'tables', kitchen: 'kitchen' };

let business = null;
let configured = false;
let cleanup = null;

function show(render, context) {
  if (cleanup) {
    cleanup();
    cleanup = null;
  }
  const result = render(root, context);
  if (typeof result === 'function') {
    cleanup = result;
  }
}

async function start() {
  try {
    const status = await api.call('business.status');
    business = status.business;
    configured = status.configured;
    if (!configured) {
      topbar.hidden = true;
      show(renderSetup, { api, onDone: start });
      return;
    }
    route();
  } catch (error) {
    topbar.hidden = true;
    mount(
      root,
      h(
        'section',
        { class: 'panel form' },
        h('h2', {}, 'No se pudo conectar'),
        h('p', {}, error.message),
        h('button', { class: 'primary', onClick: start }, 'Reintentar'),
      ),
    );
  }
}

function route() {
  if (!configured) {
    return;
  }
  if (!api.isLoggedIn) {
    topbar.hidden = true;
    show(renderLogin, {
      api,
      business,
      onLogin: () => {
        location.hash = `#/${HOME_BY_ROLE[api.user.role]}`;
        route();
      },
    });
    return;
  }
  const role = api.user.role;
  const name = location.hash.replace(/^#\//, '') || HOME_BY_ROLE[role];
  const target = ROUTES[name];
  if (!target || !target.roles.includes(role)) {
    const home = `#/${HOME_BY_ROLE[role]}`;
    if (location.hash !== home) {
      location.hash = home;
      return;
    }
  }
  const active = target && target.roles.includes(role) ? name : HOME_BY_ROLE[role];
  renderTopbar(active);
  show(ROUTES[active].render, { api, business, notify: toast });
}

function renderTopbar(active) {
  topbar.hidden = false;
  const links = Object.entries(ROUTES)
    .filter(([, routeInfo]) => routeInfo.roles.includes(api.user.role))
    .map(([name, routeInfo]) =>
      h('a', { href: `#/${name}`, class: name === active ? 'active' : null, 'aria-current': name === active ? 'page' : null }, routeInfo.title),
    );
  mount(
    topbar,
    h('strong', { class: 'brand' }, business?.name ?? 'VOXON90'),
    h('nav', { 'aria-label': 'Secciones' }, links),
    h('span', { class: 'muted' }, api.user.name),
    h(
      'button',
      {
        class: 'link',
        onClick: async () => {
          await api.logout();
          route();
        },
      },
      'Salir',
    ),
  );
}

api.onUnauthorized(() => {
  toast('Tu sesión terminó. Entra de nuevo con tu PIN.', 'error');
  route();
});
window.addEventListener('hashchange', route);
start();
