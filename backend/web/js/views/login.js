// Ingreso con PIN: teclado grande para pantallas táctiles y teclado físico.

import { h, mount } from '../dom.js';

export function renderLogin(root, { api, business, onLogin }) {
  let pin = '';
  let sending = false;
  const display = h('div', { class: 'pin-display', 'aria-live': 'polite' });
  const message = h('p', { class: 'form-error', role: 'alert' });

  const refresh = () => {
    display.textContent = pin.length ? '•'.repeat(pin.length) : ' ';
  };
  const press = (digit) => {
    if (pin.length < 6) {
      pin += digit;
      refresh();
    }
  };
  const erase = () => {
    pin = pin.slice(0, -1);
    refresh();
  };
  const submit = async () => {
    if (sending) {
      return;
    }
    if (pin.length < 4) {
      message.textContent = 'El PIN tiene de 4 a 6 dígitos';
      return;
    }
    sending = true;
    message.textContent = '';
    try {
      await api.login(pin);
      onLogin();
    } catch (error) {
      message.textContent = error.message;
    } finally {
      pin = '';
      sending = false;
      refresh();
    }
  };

  const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9'].map((digit) =>
    h('button', { class: 'key', type: 'button', onClick: () => press(digit) }, digit),
  );
  keys.push(
    h('button', { class: 'key key-muted', type: 'button', 'aria-label': 'Borrar', onClick: erase }, '⌫'),
    h('button', { class: 'key', type: 'button', onClick: () => press('0') }, '0'),
    h('button', { class: 'key key-primary', type: 'button', onClick: submit }, 'Entrar'),
  );

  const onKeyDown = (event) => {
    if (/^\d$/.test(event.key)) {
      press(event.key);
    } else if (event.key === 'Backspace') {
      erase();
    } else if (event.key === 'Enter') {
      submit();
    }
  };
  document.addEventListener('keydown', onKeyDown);

  refresh();
  mount(
    root,
    h(
      'section',
      { class: 'login' },
      h('h1', {}, business?.name ?? 'VOXON90'),
      h('p', { class: 'muted' }, 'Entra con tu PIN'),
      display,
      message,
      h('div', { class: 'keypad' }, keys),
    ),
  );
  return () => document.removeEventListener('keydown', onKeyDown);
}
