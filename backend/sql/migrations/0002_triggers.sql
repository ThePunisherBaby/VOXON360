-- VOXON90 · Reglas de integridad dentro de la base de datos.
--
-- Aunque alguien escriba en la base sin pasar por el motor, estas reglas se
-- cumplen. Los errores usan mensajes 'voxon:<codigo>' que el motor C++
-- traduce a códigos de error de la API.

-- Marcas de actualización -----------------------------------------------------

CREATE TRIGGER trg_business_profile_touch AFTER UPDATE ON business_profile
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE business_profile SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_users_touch AFTER UPDATE ON users
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE users SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_products_touch AFTER UPDATE ON products
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE products SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

CREATE TRIGGER trg_customers_touch AFTER UPDATE ON customers
WHEN NEW.updated_at = OLD.updated_at
BEGIN
  UPDATE customers SET updated_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now') WHERE id = NEW.id;
END;

-- Contadores y secuencias fiscales: nunca retroceden ------------------------

CREATE TRIGGER trg_document_counters_no_rewind BEFORE UPDATE OF next_value ON document_counters
WHEN NEW.next_value < OLD.next_value
BEGIN
  SELECT RAISE(ABORT, 'voxon:counter_rewind');
END;

CREATE TRIGGER trg_fiscal_sequences_no_rewind BEFORE UPDATE OF next_number ON fiscal_sequences
WHEN NEW.next_number < OLD.next_number
BEGIN
  SELECT RAISE(ABORT, 'voxon:fiscal_sequence_rewind');
END;

-- Inventario -----------------------------------------------------------------

-- La existencia se deriva del libro de movimientos, que solo acepta agregados.
CREATE TRIGGER trg_stock_movements_apply AFTER INSERT ON stock_movements
BEGIN
  UPDATE products SET stock_milli = stock_milli + NEW.quantity_milli WHERE id = NEW.product_id;
END;

CREATE TRIGGER trg_stock_movements_no_update BEFORE UPDATE ON stock_movements
BEGIN
  SELECT RAISE(ABORT, 'voxon:append_only');
END;

CREATE TRIGGER trg_stock_movements_no_delete BEFORE DELETE ON stock_movements
BEGIN
  SELECT RAISE(ABORT, 'voxon:append_only');
END;

-- Vender descuenta del producto, o de su producto base si se vende al detalle
-- (una cajetilla descuenta 20 cigarrillos).
CREATE TRIGGER trg_sale_items_stock AFTER INSERT ON sale_items
WHEN NEW.product_id IS NOT NULL
BEGIN
  INSERT INTO stock_movements (product_id, kind, quantity_milli, unit_cost_cents, sale_item_id, user_id)
  SELECT base.id,
         'sale',
         -((NEW.quantity_milli * item.stock_factor_milli + 500) / 1000),
         base.cost_cents,
         NEW.id,
         sale.cashier_id
  FROM products AS item
  JOIN products AS base ON base.id = coalesce(item.stock_source_id, item.id)
  JOIN sales AS sale ON sale.id = NEW.sale_id
  WHERE item.id = NEW.product_id
    AND base.track_stock = 1
    AND (NEW.quantity_milli * item.stock_factor_milli + 500) / 1000 > 0;
END;

-- Anular una venta devuelve la mercancía al inventario.
CREATE TRIGGER trg_sales_void_stock AFTER UPDATE OF status ON sales
WHEN OLD.status = 'completed' AND NEW.status = 'voided'
BEGIN
  INSERT INTO stock_movements (product_id, kind, quantity_milli, unit_cost_cents, sale_item_id, user_id, note)
  SELECT m.product_id, 'sale_void', -m.quantity_milli, m.unit_cost_cents, m.sale_item_id, NEW.voided_by, NEW.void_reason
  FROM stock_movements AS m
  JOIN sale_items AS i ON i.id = m.sale_item_id
  WHERE i.sale_id = NEW.id AND m.kind = 'sale';
END;

-- Las compras se registran sobre el producto base, no sobre su presentación al detalle.
CREATE TRIGGER trg_purchase_items_base_product BEFORE INSERT ON purchase_items
WHEN (SELECT stock_source_id FROM products WHERE id = NEW.product_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'voxon:purchase_requires_base_product');
END;

-- Comprar suma existencia y recalcula el costo promedio ponderado.
CREATE TRIGGER trg_purchase_items_stock AFTER INSERT ON purchase_items
BEGIN
  UPDATE products
  SET cost_cents = CASE
        WHEN stock_milli <= 0 THEN NEW.unit_cost_cents
        ELSE (stock_milli * cost_cents + NEW.quantity_milli * NEW.unit_cost_cents
              + (stock_milli + NEW.quantity_milli) / 2) / (stock_milli + NEW.quantity_milli)
      END
  WHERE id = NEW.product_id;

  INSERT INTO stock_movements (product_id, kind, quantity_milli, unit_cost_cents, purchase_item_id, user_id)
  SELECT NEW.product_id, 'purchase', NEW.quantity_milli, NEW.unit_cost_cents, NEW.id, p.user_id
  FROM purchases AS p
  WHERE p.id = NEW.purchase_id;
END;

CREATE TRIGGER trg_purchase_items_no_update BEFORE UPDATE ON purchase_items
BEGIN
  SELECT RAISE(ABORT, 'voxon:append_only');
END;

CREATE TRIGGER trg_purchase_items_no_delete BEFORE DELETE ON purchase_items
BEGIN
  SELECT RAISE(ABORT, 'voxon:append_only');
END;

CREATE TRIGGER trg_purchases_no_delete BEFORE DELETE ON purchases
BEGIN
  SELECT RAISE(ABORT, 'voxon:append_only');
END;

-- Caja -----------------------------------------------------------------------

CREATE TRIGGER trg_cash_sessions_closed_immutable BEFORE UPDATE ON cash_sessions
WHEN OLD.closed_at IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'voxon:cash_session_closed');
END;

CREATE TRIGGER trg_cash_sessions_no_delete BEFORE DELETE ON cash_sessions
BEGIN
  SELECT RAISE(ABORT, 'voxon:append_only');
END;

CREATE TRIGGER trg_cash_movements_open_session BEFORE INSERT ON cash_movements
WHEN (SELECT closed_at FROM cash_sessions WHERE id = NEW.session_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'voxon:cash_session_closed');
END;

CREATE TRIGGER trg_cash_movements_no_update BEFORE UPDATE ON cash_movements
BEGIN
  SELECT RAISE(ABORT, 'voxon:append_only');
END;

CREATE TRIGGER trg_cash_movements_no_delete BEFORE DELETE ON cash_movements
BEGIN
  SELECT RAISE(ABORT, 'voxon:append_only');
END;

CREATE TRIGGER trg_purchases_open_session BEFORE INSERT ON purchases
WHEN NEW.cash_session_id IS NOT NULL
  AND (SELECT closed_at FROM cash_sessions WHERE id = NEW.cash_session_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'voxon:cash_session_closed');
END;

-- Ventas ---------------------------------------------------------------------

CREATE TRIGGER trg_sales_open_session BEFORE INSERT ON sales
WHEN (SELECT closed_at FROM cash_sessions WHERE id = NEW.cash_session_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'voxon:cash_session_closed');
END;

-- Una venta cobrada no se modifica: solo puede anularse, y mientras su caja
-- siga abierta (así el cuadre de una caja cerrada nunca cambia).
CREATE TRIGGER trg_sales_only_void BEFORE UPDATE ON sales
WHEN NOT (
  OLD.status = 'completed' AND NEW.status = 'voided'
  AND NEW.id = OLD.id
  AND NEW.number = OLD.number
  AND NEW.price_mode = OLD.price_mode
  AND NEW.cashier_id = OLD.cashier_id
  AND NEW.cash_session_id = OLD.cash_session_id
  AND NEW.customer_id IS OLD.customer_id
  AND NEW.order_id IS OLD.order_id
  AND NEW.fiscal_document_type IS OLD.fiscal_document_type
  AND NEW.ncf IS OLD.ncf
  AND NEW.buyer_document_id IS OLD.buyer_document_id
  AND NEW.subtotal_cents = OLD.subtotal_cents
  AND NEW.discount_cents = OLD.discount_cents
  AND NEW.tax_cents = OLD.tax_cents
  AND NEW.tip_cents = OLD.tip_cents
  AND NEW.delivery_fee_cents = OLD.delivery_fee_cents
  AND NEW.total_cents = OLD.total_cents
  AND NEW.change_cents = OLD.change_cents
  AND NEW.created_at = OLD.created_at
)
BEGIN
  SELECT RAISE(ABORT, 'voxon:sale_immutable');
END;

CREATE TRIGGER trg_sales_void_open_session BEFORE UPDATE OF status ON sales
WHEN NEW.status = 'voided'
  AND (SELECT closed_at FROM cash_sessions WHERE id = OLD.cash_session_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'voxon:cash_session_closed');
END;

CREATE TRIGGER trg_sales_no_delete BEFORE DELETE ON sales
BEGIN
  SELECT RAISE(ABORT, 'voxon:sale_immutable');
END;

CREATE TRIGGER trg_sale_items_completed_sale BEFORE INSERT ON sale_items
WHEN (SELECT status FROM sales WHERE id = NEW.sale_id) IS NOT 'completed'
BEGIN
  SELECT RAISE(ABORT, 'voxon:sale_immutable');
END;

CREATE TRIGGER trg_sale_items_no_update BEFORE UPDATE ON sale_items
BEGIN
  SELECT RAISE(ABORT, 'voxon:sale_immutable');
END;

CREATE TRIGGER trg_sale_items_no_delete BEFORE DELETE ON sale_items
BEGIN
  SELECT RAISE(ABORT, 'voxon:sale_immutable');
END;

CREATE TRIGGER trg_sale_payments_completed_sale BEFORE INSERT ON sale_payments
WHEN (SELECT status FROM sales WHERE id = NEW.sale_id) IS NOT 'completed'
BEGIN
  SELECT RAISE(ABORT, 'voxon:sale_immutable');
END;

CREATE TRIGGER trg_sale_payments_no_update BEFORE UPDATE ON sale_payments
BEGIN
  SELECT RAISE(ABORT, 'voxon:sale_immutable');
END;

CREATE TRIGGER trg_sale_payments_no_delete BEFORE DELETE ON sale_payments
BEGIN
  SELECT RAISE(ABORT, 'voxon:sale_immutable');
END;

-- Fiao -----------------------------------------------------------------------

CREATE TRIGGER trg_credit_entries_open_session BEFORE INSERT ON credit_entries
WHEN NEW.cash_session_id IS NOT NULL
  AND (SELECT closed_at FROM cash_sessions WHERE id = NEW.cash_session_id) IS NOT NULL
BEGIN
  SELECT RAISE(ABORT, 'voxon:cash_session_closed');
END;

CREATE TRIGGER trg_credit_entries_active_customer BEFORE INSERT ON credit_entries
WHEN NEW.kind = 'charge' AND (SELECT active FROM customers WHERE id = NEW.customer_id) = 0
BEGIN
  SELECT RAISE(ABORT, 'voxon:customer_inactive');
END;

-- Un límite de 0 significa que el cliente no tiene fiao autorizado.
CREATE TRIGGER trg_credit_entries_limit BEFORE INSERT ON credit_entries
WHEN NEW.kind = 'charge'
  AND (SELECT balance_cents + NEW.amount_cents > credit_limit_cents FROM customers WHERE id = NEW.customer_id)
BEGIN
  SELECT RAISE(ABORT, 'voxon:credit_limit_exceeded');
END;

CREATE TRIGGER trg_credit_entries_overpayment BEFORE INSERT ON credit_entries
WHEN NEW.kind = 'payment'
  AND (SELECT balance_cents + NEW.amount_cents < 0 FROM customers WHERE id = NEW.customer_id)
BEGIN
  SELECT RAISE(ABORT, 'voxon:payment_exceeds_balance');
END;

CREATE TRIGGER trg_credit_entries_apply AFTER INSERT ON credit_entries
BEGIN
  UPDATE customers SET balance_cents = balance_cents + NEW.amount_cents WHERE id = NEW.customer_id;
END;

CREATE TRIGGER trg_credit_entries_no_update BEFORE UPDATE ON credit_entries
BEGIN
  SELECT RAISE(ABORT, 'voxon:append_only');
END;

CREATE TRIGGER trg_credit_entries_no_delete BEFORE DELETE ON credit_entries
BEGIN
  SELECT RAISE(ABORT, 'voxon:append_only');
END;

-- Restaurante ----------------------------------------------------------------

CREATE TRIGGER trg_order_items_open_order BEFORE INSERT ON order_items
WHEN (SELECT status FROM orders WHERE id = NEW.order_id) IS NOT 'open'
BEGIN
  SELECT RAISE(ABORT, 'voxon:order_not_open');
END;

CREATE TRIGGER trg_orders_closed_immutable BEFORE UPDATE ON orders
WHEN OLD.status <> 'open'
BEGIN
  SELECT RAISE(ABORT, 'voxon:order_not_open');
END;

-- Bitácora -------------------------------------------------------------------

CREATE TRIGGER trg_audit_log_no_update BEFORE UPDATE ON audit_log
BEGIN
  SELECT RAISE(ABORT, 'voxon:append_only');
END;

CREATE TRIGGER trg_audit_log_no_delete BEFORE DELETE ON audit_log
BEGIN
  SELECT RAISE(ABORT, 'voxon:append_only');
END;
