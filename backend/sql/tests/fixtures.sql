-- Datos de ejemplo: un colmado con una compra, ventas al detalle y por
-- fracción, fiao con abono y una venta anulada.

INSERT INTO business_profile (id, name, business_type, price_mode)
VALUES (1, 'Colmado La Esquina', 'colmado', 'tax_included');

INSERT INTO users (id, name, role, pin_hash, pin_salt, pin_iterations)
VALUES ('u-owner', 'Ana', 'owner', printf('%064d', 0), printf('%032d', 0), 1);

INSERT INTO products (id, name, search_name, price_cents, tax_rate, unit, allows_fraction, min_stock_milli)
VALUES ('p-cig',       'Cigarrillo', 'cigarrillo', 1000,  'standard', 'unit',  0, 20000),
       ('p-cajetilla', 'Cajetilla',  'cajetilla',  18000, 'standard', 'unit',  0, 0),
       ('p-arroz',     'Arroz',      'arroz',      3500,  'exempt',   'pound', 1, 50000),
       ('p-recarga',   'Recarga',    'recarga',    0,     'exempt',   'unit',  0, 0);

-- Una cajetilla son 20 cigarrillos; la recarga no lleva inventario.
UPDATE products SET stock_source_id = 'p-cig', stock_factor_milli = 20000 WHERE id = 'p-cajetilla';
UPDATE products SET track_stock = 0 WHERE id = 'p-recarga';

INSERT INTO customers (id, name, search_name, credit_limit_cents)
VALUES ('c-juan', 'Juan', 'juan', 100000),
       ('c-pedro', 'Pedro', 'pedro', 0);

INSERT INTO suppliers (id, name, document_id) VALUES ('s-dist', 'Distribuidora', '101000001');

INSERT INTO cash_sessions (id, opened_by, opening_float_cents) VALUES ('cs-1', 'u-owner', 100000);

-- Compra por transferencia: 100 cigarrillos a RD$6.00 y 50 lb de arroz a RD$25.00.
INSERT INTO purchases (id, supplier_id, ncf, invoice_date, subtotal_cents, tax_cents, total_cents, payment_method, user_id)
VALUES ('pu-1', 's-dist', 'B0100000001', '2026-09-10', 185000, 0, 185000, 'transfer', 'u-owner');

INSERT INTO purchase_items (id, purchase_id, position, product_id, quantity_milli, unit_cost_cents)
VALUES ('pi-1', 'pu-1', 0, 'p-cig', 100000, 600),
       ('pi-2', 'pu-1', 1, 'p-arroz', 50000, 2500);

-- Venta 1 en efectivo: 1 cajetilla (RD$180.00) + media libra de arroz (RD$17.50),
-- paga con RD$200.00 y recibe RD$2.50 de vuelto.
INSERT INTO sales (id, number, status, price_mode, cashier_id, cash_session_id,
                   subtotal_cents, discount_cents, tax_cents, tip_cents, total_cents, change_cents)
VALUES ('s-1', 1, 'completed', 'tax_included', 'u-owner', 'cs-1', 17004, 0, 2746, 0, 19750, 250);

INSERT INTO sale_items (id, sale_id, position, product_id, description, unit_price_cents, quantity_milli,
                        tax_rate, net_cents, unit_cost_cents)
VALUES ('si-1', 's-1', 0, 'p-cajetilla', 'Cajetilla', 18000, 1000, 'standard', 18000, 0),
       ('si-2', 's-1', 1, 'p-arroz',     'Arroz',     3500,  500,  'exempt',   1750,  2500);

INSERT INTO sale_payments (id, sale_id, method, amount_cents) VALUES ('sp-1', 's-1', 'cash', 20000);

-- Venta 2 fiada a Juan: recarga de RD$500.00.
INSERT INTO sales (id, number, status, price_mode, cashier_id, cash_session_id, customer_id,
                   subtotal_cents, discount_cents, tax_cents, tip_cents, total_cents)
VALUES ('s-2', 2, 'completed', 'tax_included', 'u-owner', 'cs-1', 'c-juan', 50000, 0, 0, 0, 50000);

INSERT INTO sale_items (id, sale_id, position, product_id, description, unit_price_cents, quantity_milli, tax_rate, net_cents)
VALUES ('si-3', 's-2', 0, 'p-recarga', 'Recarga', 50000, 1000, 'exempt', 50000);

INSERT INTO sale_payments (id, sale_id, method, amount_cents) VALUES ('sp-2', 's-2', 'credit', 50000);

INSERT INTO credit_entries (id, customer_id, kind, amount_cents, sale_id, user_id)
VALUES ('ce-1', 'c-juan', 'charge', 50000, 's-2', 'u-owner');

-- Juan abona RD$200.00 en efectivo.
INSERT INTO credit_entries (id, customer_id, kind, amount_cents, cash_session_id, method, user_id)
VALUES ('ce-2', 'c-juan', 'payment', -20000, 'cs-1', 'cash', 'u-owner');

-- Entra menudo y se paga el hielo.
INSERT INTO cash_movements (id, session_id, kind, amount_cents, reason, user_id)
VALUES ('cm-1', 'cs-1', 'cash_in', 5000, 'Menudo', 'u-owner'),
       ('cm-2', 'cs-1', 'cash_out', 3000, 'Hielo', 'u-owner');

-- Venta 3 con tarjeta (2 lb de arroz), luego anulada.
INSERT INTO sales (id, number, status, price_mode, cashier_id, cash_session_id,
                   subtotal_cents, discount_cents, tax_cents, tip_cents, total_cents)
VALUES ('s-3', 3, 'completed', 'tax_included', 'u-owner', 'cs-1', 7000, 0, 0, 0, 7000);

INSERT INTO sale_items (id, sale_id, position, product_id, description, unit_price_cents, quantity_milli,
                        tax_rate, net_cents, unit_cost_cents)
VALUES ('si-4', 's-3', 0, 'p-arroz', 'Arroz', 3500, 2000, 'exempt', 7000, 2500);

INSERT INTO sale_payments (id, sale_id, method, amount_cents, reference) VALUES ('sp-3', 's-3', 'card', 7000, '123456');

UPDATE sales
SET status = 'voided',
    voided_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
    voided_by = 'u-owner',
    void_reason = 'El cliente devolvió el arroz'
WHERE id = 's-3';
