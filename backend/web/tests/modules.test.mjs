import { test } from 'node:test';
import assert from 'node:assert/strict';

// Importar cada pantalla en Node detecta nombres de importación equivocados
// (un error de enlace del módulo) sin necesidad de un navegador.
test('cada pantalla exporta la función que usa app.js', async () => {
  const views = {
    login: 'renderLogin',
    setup: 'renderSetup',
    pos: 'renderPos',
    tables: 'renderTables',
    kitchen: 'renderKitchen',
    dashboard: 'renderDashboard',
  };
  for (const [file, exported] of Object.entries(views)) {
    const module = await import(`../js/views/${file}.js`);
    assert.equal(typeof module[exported], 'function', `${file}.js debe exportar ${exported}`);
  }
});
