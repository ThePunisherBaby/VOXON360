-- Operaciones que la base debe rechazar. Cada caso corre sobre una copia
-- de fixtures.sql. Formato de la cabecera:  -- case: <nombre> => <error esperado>

-- case: una venta cobrada no se modifica => voxon:sale_immutable
UPDATE sales SET discount_cents = 100 WHERE id = 's-1';

-- case: una venta no se borra => voxon:sale_immutable
DELETE FROM sales WHERE id = 's-1';

-- case: las líneas de una venta no se editan => voxon:sale_immutable
UPDATE sale_items SET net_cents = 0 WHERE id = 'si-1';

-- case: no se agregan pagos a una venta anulada => voxon:sale_immutable
INSERT INTO sale_payments (id, sale_id, method, amount_cents) VALUES ('sp-x', 's-3', 'cash', 100);

-- case: el total de una venta debe cuadrar => CHECK constraint failed
INSERT INTO sales (id, number, status, price_mode, cashier_id, cash_session_id,
                   subtotal_cents, discount_cents, tax_cents, tip_cents, total_cents)
VALUES ('s-x', 99, 'completed', 'tax_included', 'u-owner', 'cs-1', 100, 0, 18, 0, 120);

-- case: solo puede haber una caja abierta => ux_cash_sessions_open
INSERT INTO cash_sessions (id, opened_by, opening_float_cents) VALUES ('cs-2', 'u-owner', 0);

-- case: no se vende con la caja cerrada => voxon:cash_session_closed
UPDATE cash_sessions SET closed_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), closed_by = 'u-owner',
       expected_cash_cents = 0, counted_cash_cents = 0 WHERE id = 'cs-1';
INSERT INTO sales (id, number, status, price_mode, cashier_id, cash_session_id,
                   subtotal_cents, discount_cents, tax_cents, tip_cents, total_cents)
VALUES ('s-x', 99, 'completed', 'tax_included', 'u-owner', 'cs-1', 100, 0, 0, 0, 100);

-- case: una caja cerrada no cambia => voxon:cash_session_closed
UPDATE cash_sessions SET closed_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), closed_by = 'u-owner',
       expected_cash_cents = 0, counted_cash_cents = 0 WHERE id = 'cs-1';
UPDATE cash_sessions SET counted_cash_cents = 999999 WHERE id = 'cs-1';

-- case: no se anula una venta de una caja cerrada => voxon:cash_session_closed
UPDATE cash_sessions SET closed_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'), closed_by = 'u-owner',
       expected_cash_cents = 0, counted_cash_cents = 0 WHERE id = 'cs-1';
UPDATE sales SET status = 'voided', voided_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
       voided_by = 'u-owner', void_reason = 'tarde' WHERE id = 's-1';

-- case: los movimientos de caja no se borran => voxon:append_only
DELETE FROM cash_movements WHERE id = 'cm-1';

-- case: el fiao respeta el límite de crédito => voxon:credit_limit_exceeded
INSERT INTO credit_entries (id, customer_id, kind, amount_cents, sale_id, user_id)
VALUES ('ce-x', 'c-juan', 'charge', 80000, 's-2', 'u-owner');

-- case: un cliente con límite 0 no tiene fiao => voxon:credit_limit_exceeded
INSERT INTO credit_entries (id, customer_id, kind, amount_cents, sale_id, user_id)
VALUES ('ce-x', 'c-pedro', 'charge', 100, 's-2', 'u-owner');

-- case: un abono no puede pasar de la deuda => voxon:payment_exceeds_balance
INSERT INTO credit_entries (id, customer_id, kind, amount_cents, cash_session_id, method, user_id)
VALUES ('ce-x', 'c-juan', 'payment', -40000, 'cs-1', 'cash', 'u-owner');

-- case: un abono en efectivo necesita caja => CHECK constraint failed
INSERT INTO credit_entries (id, customer_id, kind, amount_cents, method, user_id)
VALUES ('ce-x', 'c-juan', 'payment', -1000, 'cash', 'u-owner');

-- case: el libro del fiao no se borra => voxon:append_only
DELETE FROM credit_entries WHERE id = 'ce-1';

-- case: el libro de inventario no se edita => voxon:append_only
UPDATE stock_movements SET quantity_milli = 1;

-- case: no se compra la presentación al detalle => voxon:purchase_requires_base_product
INSERT INTO purchase_items (id, purchase_id, position, product_id, quantity_milli, unit_cost_cents)
VALUES ('pi-x', 'pu-1', 9, 'p-cajetilla', 1000, 12000);

-- case: la secuencia fiscal no retrocede => voxon:fiscal_sequence_rewind
INSERT INTO fiscal_sequences (id, document_type, range_from, range_to, next_number)
VALUES ('fs-x', 'B02', 1, 100, 10);
UPDATE fiscal_sequences SET next_number = 5 WHERE id = 'fs-x';

-- case: el contador de tickets no retrocede => voxon:counter_rewind
UPDATE document_counters SET next_value = 0 WHERE name = 'sale';

-- case: una orden cerrada no recibe productos => voxon:order_not_open
INSERT INTO dining_tables (id, name) VALUES ('t-1', 'Mesa 1');
INSERT INTO orders (id, number, kind, status, table_id, waiter_id, closed_at)
VALUES ('o-1', 1, 'dine_in', 'closed', 't-1', 'u-owner', strftime('%Y-%m-%dT%H:%M:%fZ', 'now'));
INSERT INTO order_items (id, order_id, product_id, quantity_milli, unit_price_cents, station, created_by)
VALUES ('oi-1', 'o-1', 'p-arroz', 1000, 3500, 'kitchen', 'u-owner');

-- case: una mesa no tiene dos órdenes abiertas => UNIQUE constraint failed: orders.table_id
INSERT INTO dining_tables (id, name) VALUES ('t-1', 'Mesa 1');
INSERT INTO orders (id, number, kind, status, table_id, waiter_id) VALUES ('o-1', 1, 'dine_in', 'open', 't-1', 'u-owner');
INSERT INTO orders (id, number, kind, status, table_id, waiter_id) VALUES ('o-2', 2, 'dine_in', 'open', 't-1', 'u-owner');

-- case: una orden en mesa necesita mesa => CHECK constraint failed
INSERT INTO orders (id, number, kind, status, waiter_id) VALUES ('o-1', 1, 'dine_in', 'open', 'u-owner');

-- case: la bitácora no se borra => voxon:append_only
INSERT INTO audit_log (action, user_id) VALUES ('prueba', 'u-owner');
DELETE FROM audit_log;

-- case: el RNC debe tener 9 u 11 dígitos => CHECK constraint failed
UPDATE business_profile SET rnc = '12345' WHERE id = 1;

-- case: una venta exige un cajero existente => FOREIGN KEY constraint failed
INSERT INTO sales (id, number, status, price_mode, cashier_id, cash_session_id,
                   subtotal_cents, discount_cents, tax_cents, tip_cents, total_cents)
VALUES ('s-x', 99, 'completed', 'tax_included', 'u-nadie', 'cs-1', 100, 0, 0, 0, 100);
