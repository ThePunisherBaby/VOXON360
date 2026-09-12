-- Resultados que deben cumplirse sobre fixtures.sql.
-- Cada fila de t_results con ok distinto de 1 es una falla.

CREATE TEMP TABLE t_results (name TEXT PRIMARY KEY, ok INTEGER);

INSERT INTO t_results VALUES
('la cajetilla descuenta 20 cigarrillos del producto base',
  (SELECT stock_milli FROM products WHERE id = 'p-cig') = 80000),
('la cajetilla no lleva existencia propia',
  (SELECT stock_milli FROM products WHERE id = 'p-cajetilla') = 0),
('media libra descuenta 500 milésimas y la venta anulada devuelve lo suyo',
  (SELECT stock_milli FROM products WHERE id = 'p-arroz') = 49500),
('un producto sin inventario no genera movimientos',
  (SELECT count(*) FROM stock_movements WHERE product_id = 'p-recarga') = 0),
('la anulación queda registrada en el libro de inventario',
  (SELECT count(*) FROM stock_movements WHERE kind = 'sale_void' AND quantity_milli = 2000) = 1),
('la primera compra fija el costo',
  (SELECT cost_cents FROM products WHERE id = 'p-cig') = 600),
('el fiao de Juan queda en RD$300.00 tras su abono',
  (SELECT balance_cents FROM customers WHERE id = 'c-juan') = 30000),
('cuadre: 1,000 + (200 − 2.50) + 50 − 30 + 200 de abono = 1,417.50',
  (SELECT expected_cash_cents FROM v_cash_session_balance WHERE session_id = 'cs-1') = 141750),
('la caja abierta aún no tiene diferencia',
  (SELECT difference_cents FROM v_cash_session_balance WHERE session_id = 'cs-1') IS NULL),
('la venta anulada no cuenta en las ventas del día',
  (SELECT sales_count = 2 AND total_cents = 69750 FROM v_daily_sales)),
('efectivo neto del día descuenta el vuelto',
  (SELECT amount_cents FROM v_daily_payments WHERE method = 'cash') = 19750),
('el fiao aparece como forma de pago',
  (SELECT amount_cents FROM v_daily_payments WHERE method = 'credit') = 50000),
('la tarjeta anulada no aparece en los pagos',
  (SELECT count(*) FROM v_daily_payments WHERE method = 'card') = 0),
('margen del arroz: vendió 17.50 con costo 12.50',
  (SELECT net_cents = 1750 AND cost_cents = 1250 AND margin_cents = 500
   FROM v_product_sales WHERE product_id = 'p-arroz')),
('el arroz está bajo el mínimo y la cajetilla no se lista',
  (SELECT count(*) FROM v_low_stock WHERE product_id = 'p-arroz') = 1
  AND (SELECT count(*) FROM v_low_stock WHERE product_id = 'p-cajetilla') = 0),
('Juan aparece entre los deudores y Pedro no',
  (SELECT balance_cents FROM v_customer_balances WHERE customer_id = 'c-juan') = 30000
  AND (SELECT count(*) FROM v_customer_balances WHERE customer_id = 'c-pedro') = 0),
('la compra aparece en el 606 del período',
  (SELECT count(*) FROM v_purchases_606 WHERE period = '2026-09' AND ncf = 'B0100000001') = 1);

-- Segunda compra: 100 cigarrillos a RD$8.00 sobre 80 en existencia a RD$6.00.
INSERT INTO purchases (id, supplier_id, ncf, invoice_date, subtotal_cents, tax_cents, total_cents, payment_method, cash_session_id, user_id)
VALUES ('pu-2', 's-dist', 'B0100000002', '2026-09-11', 80000, 0, 80000, 'cash', 'cs-1', 'u-owner');
INSERT INTO purchase_items (id, purchase_id, position, product_id, quantity_milli, unit_cost_cents)
VALUES ('pi-3', 'pu-2', 0, 'p-cig', 100000, 800);

INSERT INTO t_results VALUES
('costo promedio ponderado: (80 × 6.00 + 100 × 8.00) / 180 = 7.11',
  (SELECT cost_cents FROM products WHERE id = 'p-cig') = 711),
('la compra suma existencia',
  (SELECT stock_milli FROM products WHERE id = 'p-cig') = 180000),
('una compra en efectivo sale de la caja',
  (SELECT expected_cash_cents FROM v_cash_session_balance WHERE session_id = 'cs-1') = 61750);

-- Cierre de caja con RD$10.00 de faltante.
UPDATE cash_sessions
SET closed_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now'),
    closed_by = 'u-owner',
    expected_cash_cents = 61750,
    counted_cash_cents = 60750
WHERE id = 'cs-1';

INSERT INTO t_results VALUES
('el cierre muestra el faltante',
  (SELECT difference_cents FROM v_cash_session_balance WHERE session_id = 'cs-1') = -1000);

INSERT INTO fiscal_sequences (id, document_type, range_from, range_to, next_number, expires_on)
VALUES ('fs-1', 'E32', 1, 100, 1, '2027-12-31');

INSERT INTO t_results VALUES
('la secuencia fiscal informa lo disponible',
  (SELECT remaining = 100 AND expired = 0 FROM v_fiscal_sequence_status WHERE id = 'fs-1'));

SELECT CASE WHEN ok IS 1 THEN 'ok     ' ELSE 'FALLA  ' END || name FROM t_results ORDER BY rowid;
