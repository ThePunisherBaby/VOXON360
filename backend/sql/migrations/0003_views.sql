-- VOXON90 · Vistas de reportes.
--
-- Los reportes por día usan la hora de República Dominicana (UTC-4, sin
-- horario de verano): date(created_at, '-4 hours').

-- Cobro neto de cada venta por forma de pago: al efectivo se le resta el vuelto.
CREATE VIEW v_sale_payment_totals AS
SELECT s.id                            AS sale_id,
       s.cash_session_id               AS cash_session_id,
       date(s.created_at, '-4 hours')  AS day,
       p.method                        AS method,
       sum(p.amount_cents) - CASE WHEN p.method = 'cash' THEN s.change_cents ELSE 0 END AS amount_cents
FROM sales AS s
JOIN sale_payments AS p ON p.sale_id = s.id
WHERE s.status = 'completed'
GROUP BY s.id, p.method;

CREATE VIEW v_daily_sales AS
SELECT date(created_at, '-4 hours') AS day,
       count(*)                     AS sales_count,
       sum(subtotal_cents)          AS subtotal_cents,
       sum(discount_cents)          AS discount_cents,
       sum(tax_cents)               AS tax_cents,
       sum(tip_cents)               AS tip_cents,
       sum(delivery_fee_cents)      AS delivery_fee_cents,
       sum(total_cents)             AS total_cents
FROM sales
WHERE status = 'completed'
GROUP BY day;

CREATE VIEW v_daily_payments AS
SELECT day, method, sum(amount_cents) AS amount_cents
FROM v_sale_payment_totals
GROUP BY day, method;

-- Ventas por producto con costo y margen.
CREATE VIEW v_product_sales AS
SELECT date(s.created_at, '-4 hours')                               AS day,
       i.product_id                                                 AS product_id,
       i.description                                                AS description,
       sum(i.quantity_milli)                                        AS quantity_milli,
       sum(i.net_cents)                                             AS net_cents,
       sum((i.quantity_milli * i.unit_cost_cents + 500) / 1000)     AS cost_cents,
       sum(i.net_cents) - sum((i.quantity_milli * i.unit_cost_cents + 500) / 1000) AS margin_cents
FROM sale_items AS i
JOIN sales AS s ON s.id = i.sale_id
WHERE s.status = 'completed'
GROUP BY day, i.product_id, i.description;

-- Cuadre de caja. El motor usa esta vista como única fuente del efectivo esperado.
CREATE VIEW v_cash_session_balance AS
SELECT b.*,
       b.opening_float_cents + b.cash_sales_cents + b.cash_in_cents - b.cash_out_cents
         + b.credit_cash_payments_cents - b.cash_purchases_cents AS expected_cash_cents,
       CASE
         WHEN b.counted_cash_cents IS NULL THEN NULL
         ELSE b.counted_cash_cents - (b.opening_float_cents + b.cash_sales_cents + b.cash_in_cents
              - b.cash_out_cents + b.credit_cash_payments_cents - b.cash_purchases_cents)
       END AS difference_cents
FROM (
  SELECT cs.id                  AS session_id,
         cs.opened_by           AS opened_by,
         cs.opened_at           AS opened_at,
         cs.closed_by           AS closed_by,
         cs.closed_at           AS closed_at,
         cs.opening_float_cents AS opening_float_cents,
         cs.counted_cash_cents  AS counted_cash_cents,
         coalesce((SELECT sum(t.amount_cents) FROM v_sale_payment_totals AS t
                   WHERE t.cash_session_id = cs.id AND t.method = 'cash'), 0) AS cash_sales_cents,
         coalesce((SELECT sum(m.amount_cents) FROM cash_movements AS m
                   WHERE m.session_id = cs.id AND m.kind = 'cash_in'), 0) AS cash_in_cents,
         coalesce((SELECT sum(m.amount_cents) FROM cash_movements AS m
                   WHERE m.session_id = cs.id AND m.kind = 'cash_out'), 0) AS cash_out_cents,
         coalesce((SELECT -sum(c.amount_cents) FROM credit_entries AS c
                   WHERE c.cash_session_id = cs.id AND c.method = 'cash'), 0) AS credit_cash_payments_cents,
         coalesce((SELECT sum(p.total_cents) FROM purchases AS p
                   WHERE p.cash_session_id = cs.id AND p.payment_method = 'cash'), 0) AS cash_purchases_cents
  FROM cash_sessions AS cs
) AS b;

-- Totales por forma de pago de cada caja, para el reporte de cierre.
CREATE VIEW v_cash_session_payments AS
SELECT cash_session_id AS session_id, method, sum(amount_cents) AS amount_cents, count(*) AS sales_count
FROM v_sale_payment_totals
GROUP BY cash_session_id, method;

CREATE VIEW v_low_stock AS
SELECT id AS product_id, name, stock_milli, min_stock_milli, unit
FROM products
WHERE active = 1 AND track_stock = 1 AND stock_source_id IS NULL AND stock_milli <= min_stock_milli;

-- Clientes que deben, del más endeudado al menos.
CREATE VIEW v_customer_balances AS
SELECT c.id AS customer_id,
       c.name,
       c.phone,
       c.balance_cents,
       c.credit_limit_cents,
       (SELECT max(e.created_at) FROM credit_entries AS e WHERE e.customer_id = c.id AND e.kind = 'payment') AS last_payment_at
FROM customers AS c
WHERE c.balance_cents > 0;

-- Pantalla de cocina y bar: lo enviado que aún no se ha servido.
CREATE VIEW v_kitchen_queue AS
SELECT oi.id          AS item_id,
       oi.station     AS station,
       oi.status      AS status,
       o.id           AS order_id,
       o.number       AS order_number,
       o.kind         AS order_kind,
       t.name         AS table_name,
       p.name         AS product_name,
       oi.quantity_milli,
       oi.notes,
       oi.sent_at,
       oi.ready_at
FROM order_items AS oi
JOIN orders AS o ON o.id = oi.order_id
JOIN products AS p ON p.id = oi.product_id
LEFT JOIN dining_tables AS t ON t.id = o.table_id
WHERE oi.station <> 'none' AND oi.status IN ('sent', 'preparing', 'ready');

CREATE VIEW v_open_orders AS
SELECT o.id AS order_id,
       o.number,
       o.kind,
       o.table_id,
       t.name AS table_name,
       o.waiter_id,
       u.name AS waiter_name,
       o.guests,
       o.opened_at,
       count(oi.id) AS item_count,
       coalesce(sum((oi.quantity_milli * oi.unit_price_cents + 500) / 1000), 0) AS gross_cents
FROM orders AS o
JOIN users AS u ON u.id = o.waiter_id
LEFT JOIN dining_tables AS t ON t.id = o.table_id
LEFT JOIN order_items AS oi ON oi.order_id = o.id AND oi.status <> 'cancelled'
WHERE o.status = 'open'
GROUP BY o.id;

CREATE VIEW v_fiscal_sequence_status AS
SELECT id,
       document_type,
       range_from,
       range_to,
       next_number,
       range_to - next_number + 1 AS remaining,
       expires_on,
       CASE WHEN expires_on IS NOT NULL AND expires_on < date('now', '-4 hours') THEN 1 ELSE 0 END AS expired,
       active
FROM fiscal_sequences;

-- Compras del período para preparar el formato 606 de la DGII.
CREATE VIEW v_purchases_606 AS
SELECT substr(p.invoice_date, 1, 7) AS period,
       s.document_id                AS supplier_document_id,
       s.name                       AS supplier_name,
       p.ncf,
       p.invoice_date,
       p.subtotal_cents,
       p.tax_cents,
       p.total_cents,
       p.payment_method
FROM purchases AS p
LEFT JOIN suppliers AS s ON s.id = p.supplier_id;

-- Ventas con comprobante fiscal del período.
CREATE VIEW v_fiscal_sales AS
SELECT substr(date(s.created_at, '-4 hours'), 1, 7) AS period,
       s.id AS sale_id,
       s.number,
       s.fiscal_document_type,
       s.ncf,
       s.buyer_document_id,
       date(s.created_at, '-4 hours') AS day,
       s.subtotal_cents,
       s.tax_cents,
       s.tip_cents,
       s.total_cents,
       s.status
FROM sales AS s
WHERE s.ncf IS NOT NULL;
