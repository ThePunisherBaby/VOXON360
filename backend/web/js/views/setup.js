// Configuración inicial: datos del negocio y del dueño.

import { h, mount, toast } from '../dom.js';
import { errorText, field, option, withBusy } from '../ui.js';

export function renderSetup(root, { api, onDone }) {
  const error = errorText();
  const submitButton = h('button', { class: 'primary', type: 'submit' }, 'Guardar y empezar');

  const form = h(
    'form',
    {
      class: 'panel form',
      onSubmit: async (event) => {
        event.preventDefault();
        const data = new FormData(form);
        error.textContent = '';
        await withBusy(submitButton, async () => {
          try {
            await api.call('business.setup', {
              business: {
                name: data.get('name'),
                businessType: data.get('businessType'),
                rnc: data.get('rnc') || null,
                phone: data.get('phone') || null,
              },
              owner: { name: data.get('ownerName'), pin: data.get('pin') },
            });
            toast('Negocio configurado. Entra con tu PIN.');
            onDone();
          } catch (failure) {
            error.textContent = failure.message;
          }
        });
      },
    },
    h('h1', {}, 'Bienvenido a VOXON90'),
    h('p', { class: 'muted' }, 'Configura tu negocio. Todo se guarda en este equipo, sin internet.'),
    field('Nombre del negocio', h('input', { name: 'name', required: true, maxlength: 80, autocomplete: 'organization' })),
    field(
      'Tipo de negocio',
      h('select', { name: 'businessType' }, option('colmado', 'Colmado'), option('store', 'Tienda'), option('restaurant', 'Restaurante')),
      'Los restaurantes usan precios sin ITBIS y propina legal del 10 %.',
    ),
    field('RNC o cédula (opcional)', h('input', { name: 'rnc', inputmode: 'numeric', maxlength: 13 })),
    field('Teléfono (opcional)', h('input', { name: 'phone', inputmode: 'tel', maxlength: 30 })),
    h('h2', {}, 'Dueño'),
    field('Tu nombre', h('input', { name: 'ownerName', required: true, maxlength: 60, autocomplete: 'name' })),
    field(
      'PIN',
      h('input', { name: 'pin', type: 'password', required: true, inputmode: 'numeric', pattern: '\\d{4,6}', autocomplete: 'new-password' }),
      'De 4 a 6 dígitos. Con él entrarás a vender.',
    ),
    error,
    submitButton,
  );
  mount(root, form);
}
