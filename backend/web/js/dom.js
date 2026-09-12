// Ayudantes mínimos para construir la interfaz sin frameworks.
// Los textos siempre se insertan como texto, nunca como HTML: así un nombre de
// producto o cliente no puede inyectar código en la página.

/**
 * Crea un elemento. Atributos "on*" con funciones se vuelven eventos.
 * h('button', { class: 'primary', onClick: pagar }, 'Cobrar')
 */
export function h(tag, attributes = {}, ...children) {
  const element = document.createElement(tag);
  for (const [key, value] of Object.entries(attributes ?? {})) {
    if (value === null || value === undefined || value === false) {
      continue;
    }
    if (key.startsWith('on') && typeof value === 'function') {
      element.addEventListener(key.slice(2).toLowerCase(), value);
    } else if (key === 'class') {
      element.className = value;
    } else if (key === 'dataset') {
      Object.assign(element.dataset, value);
    } else if (key === 'value') {
      element.value = value;
    } else {
      element.setAttribute(key, value === true ? '' : String(value));
    }
  }
  for (const child of children.flat(Infinity)) {
    if (child === null || child === undefined || child === false) {
      continue;
    }
    element.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return element;
}

/** Reemplaza el contenido de `container`. */
export function mount(container, ...children) {
  container.replaceChildren(...children.flat(Infinity).filter((child) => child !== null && child !== undefined));
}

/** Aviso breve en la parte inferior de la pantalla. */
export function toast(message, kind = 'info') {
  const region = document.getElementById('toasts');
  if (!region) {
    return;
  }
  const item = h('div', { class: `toast toast-${kind}`, role: kind === 'error' ? 'alert' : 'status' }, message);
  region.append(item);
  setTimeout(() => item.remove(), kind === 'error' ? 6000 : 3000);
}
