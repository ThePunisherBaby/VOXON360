-- VOXON90 · Esquema local (SQLite 3.53+, tablas STRICT).
--
-- Convenciones:
--   * Montos en centavos enteros (*_cents) y cantidades en milésimas (*_milli).
--   * Fechas en texto ISO-8601 UTC: 2026-09-11T14:30:00.000Z.
--   * Identificadores UUID v4 en texto, generados por el motor C++.
--   * Booleanos como INTEGER 0/1.
-- Todo funciona sin conexión: no hay tablas de sincronización con la nube.

-- Datos del negocio: una sola fila.
CREATE TABLE business_profile (
  id                INTEGER PRIMARY KEY CHECK (id = 1),
  name              TEXT    NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 80),
  business_type     TEXT    NOT NULL CHECK (business_type IN ('colmado', 'store', 'restaurant')),
  rnc               TEXT    CHECK (rnc IS NULL OR (rnc NOT GLOB '*[^0-9]*' AND length(rnc) IN (9, 11))),
  address           TEXT,
  phone             TEXT,
  price_mode        TEXT    NOT NULL CHECK (price_mode IN ('tax_included', 'tax_excluded')),
  legal_tip_enabled INTEGER NOT NULL DEFAULT 0 CHECK (legal_tip_enabled IN (0, 1)),
  receipt_footer    TEXT,
  created_at        TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at        TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT;

-- Contadores de documentos visibles (tickets, órdenes) sin huecos por concurrencia.
CREATE TABLE document_counters (
  name       TEXT    PRIMARY KEY,
  next_value INTEGER NOT NULL CHECK (next_value > 0)
) STRICT;

INSERT INTO document_counters (name, next_value) VALUES ('sale', 1), ('order', 1);

-- Preferencias locales del equipo (impresora, puerto del servidor...).
CREATE TABLE settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
) STRICT;

CREATE TABLE users (
  id             TEXT    PRIMARY KEY,
  name           TEXT    NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 60),
  role           TEXT    NOT NULL CHECK (role IN ('owner', 'manager', 'cashier', 'waiter', 'kitchen')),
  -- PBKDF2-HMAC-SHA256 en hexadecimal. El PIN nunca se guarda en claro.
  pin_hash       TEXT    NOT NULL CHECK (length(pin_hash) = 64),
  pin_salt       TEXT    NOT NULL CHECK (length(pin_salt) = 32),
  pin_iterations INTEGER NOT NULL CHECK (pin_iterations > 0),
  active         INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  created_at     TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at     TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT;

CREATE TABLE categories (
  id         TEXT    PRIMARY KEY,
  name       TEXT    NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 40),
  sort_order INTEGER NOT NULL DEFAULT 0,
  active     INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  created_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT;

CREATE UNIQUE INDEX ux_categories_name ON categories (lower(name)) WHERE active = 1;

CREATE TABLE products (
  id                    TEXT    PRIMARY KEY,
  category_id           TEXT    REFERENCES categories (id) ON DELETE SET NULL,
  name                  TEXT    NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 80),
  -- Nombre en minúsculas y sin acentos para búsquedas ("cafe" encuentra "Café").
  search_name           TEXT    NOT NULL,
  barcode               TEXT    UNIQUE CHECK (barcode IS NULL OR length(trim(barcode)) > 0),
  price_cents           INTEGER NOT NULL CHECK (price_cents >= 0),
  wholesale_price_cents INTEGER CHECK (wholesale_price_cents IS NULL OR wholesale_price_cents >= 0),
  -- Costo promedio ponderado, actualizado con cada compra.
  cost_cents            INTEGER NOT NULL DEFAULT 0 CHECK (cost_cents >= 0),
  tax_rate              TEXT    NOT NULL CHECK (tax_rate IN ('exempt', 'reduced', 'standard')),
  unit                  TEXT    NOT NULL DEFAULT 'unit'
                                CHECK (unit IN ('unit', 'pound', 'kilogram', 'ounce', 'liter')),
  allows_fraction       INTEGER NOT NULL DEFAULT 0 CHECK (allows_fraction IN (0, 1)),
  track_stock           INTEGER NOT NULL DEFAULT 1 CHECK (track_stock IN (0, 1)),
  -- Existencia en milésimas. Puede quedar negativa: vender nunca se bloquea.
  stock_milli           INTEGER NOT NULL DEFAULT 0,
  min_stock_milli       INTEGER NOT NULL DEFAULT 0 CHECK (min_stock_milli >= 0),
  -- Venta al detalle: una "cajetilla" descuenta 20 unidades de "cigarrillo".
  stock_source_id       TEXT    REFERENCES products (id),
  stock_factor_milli    INTEGER NOT NULL DEFAULT 1000 CHECK (stock_factor_milli > 0),
  -- Estación de preparación en restaurantes.
  station               TEXT    NOT NULL DEFAULT 'none' CHECK (station IN ('none', 'kitchen', 'bar')),
  active                INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  created_at            TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at            TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  CHECK (stock_source_id IS NULL OR stock_source_id <> id)
) STRICT;

CREATE INDEX ix_products_search   ON products (search_name) WHERE active = 1;
CREATE INDEX ix_products_category ON products (category_id);
CREATE INDEX ix_products_source   ON products (stock_source_id) WHERE stock_source_id IS NOT NULL;

-- Clientes con cuenta de fiao.
CREATE TABLE customers (
  id                 TEXT    PRIMARY KEY,
  name               TEXT    NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 80),
  search_name        TEXT    NOT NULL,
  phone              TEXT,
  -- RNC (9 dígitos) o cédula (11 dígitos).
  document_id        TEXT    CHECK (document_id IS NULL OR (document_id NOT GLOB '*[^0-9]*' AND length(document_id) IN (9, 11))),
  address            TEXT,
  credit_limit_cents INTEGER NOT NULL DEFAULT 0 CHECK (credit_limit_cents >= 0),
  -- Deuda actual; la mantienen los triggers de credit_entries.
  balance_cents      INTEGER NOT NULL DEFAULT 0,
  active             INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  created_at         TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at         TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT;

CREATE INDEX ix_customers_search ON customers (search_name) WHERE active = 1;

CREATE TABLE cash_sessions (
  id                  TEXT    PRIMARY KEY,
  opened_by           TEXT    NOT NULL REFERENCES users (id),
  opened_at           TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  opening_float_cents INTEGER NOT NULL CHECK (opening_float_cents >= 0),
  closed_by           TEXT    REFERENCES users (id),
  closed_at           TEXT,
  expected_cash_cents INTEGER,
  counted_cash_cents  INTEGER CHECK (counted_cash_cents IS NULL OR counted_cash_cents >= 0),
  notes               TEXT,
  CHECK ((closed_at IS NULL) = (closed_by IS NULL)),
  CHECK (closed_at IS NULL OR (expected_cash_cents IS NOT NULL AND counted_cash_cents IS NOT NULL))
) STRICT;

-- Solo puede haber una caja abierta a la vez.
CREATE UNIQUE INDEX ux_cash_sessions_open ON cash_sessions (ifnull(closed_at, 'open')) WHERE closed_at IS NULL;

CREATE TABLE cash_movements (
  id           TEXT    PRIMARY KEY,
  session_id   TEXT    NOT NULL REFERENCES cash_sessions (id),
  kind         TEXT    NOT NULL CHECK (kind IN ('cash_in', 'cash_out')),
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  reason       TEXT    NOT NULL CHECK (length(trim(reason)) > 0),
  user_id      TEXT    NOT NULL REFERENCES users (id),
  created_at   TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT;

CREATE INDEX ix_cash_movements_session ON cash_movements (session_id);

-- Rangos de comprobantes fiscales autorizados por la DGII (NCF y e-NCF).
CREATE TABLE fiscal_sequences (
  id            TEXT    PRIMARY KEY,
  document_type TEXT    NOT NULL
                        CHECK (document_type IN ('B01', 'B02', 'B04', 'B14', 'B15', 'E31', 'E32', 'E33', 'E34')),
  range_from    INTEGER NOT NULL CHECK (range_from > 0),
  range_to      INTEGER NOT NULL,
  next_number   INTEGER NOT NULL,
  expires_on    TEXT    CHECK (expires_on IS NULL OR expires_on GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  active        INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  created_at    TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  CHECK (range_to >= range_from),
  CHECK (next_number BETWEEN range_from AND range_to + 1)
) STRICT;

CREATE INDEX ix_fiscal_sequences_type ON fiscal_sequences (document_type, active);

CREATE TABLE dining_areas (
  id         TEXT    PRIMARY KEY,
  name       TEXT    NOT NULL UNIQUE CHECK (length(trim(name)) BETWEEN 1 AND 40),
  sort_order INTEGER NOT NULL DEFAULT 0,
  active     INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1))
) STRICT;

CREATE TABLE dining_tables (
  id      TEXT    PRIMARY KEY,
  area_id TEXT    REFERENCES dining_areas (id),
  name    TEXT    NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 20),
  seats   INTEGER NOT NULL DEFAULT 4 CHECK (seats > 0),
  active  INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  UNIQUE (area_id, name)
) STRICT;

CREATE TABLE orders (
  id               TEXT    PRIMARY KEY,
  number           INTEGER NOT NULL UNIQUE CHECK (number > 0),
  kind             TEXT    NOT NULL CHECK (kind IN ('dine_in', 'takeout', 'delivery')),
  status           TEXT    NOT NULL CHECK (status IN ('open', 'closed', 'cancelled')),
  table_id         TEXT    REFERENCES dining_tables (id),
  waiter_id        TEXT    NOT NULL REFERENCES users (id),
  guests           INTEGER CHECK (guests IS NULL OR guests > 0),
  customer_name    TEXT,
  delivery_address TEXT,
  delivery_fee_cents INTEGER NOT NULL DEFAULT 0 CHECK (delivery_fee_cents >= 0),
  notes            TEXT,
  opened_at        TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  closed_at        TEXT,
  CHECK ((status = 'open') = (closed_at IS NULL)),
  CHECK (kind <> 'dine_in' OR table_id IS NOT NULL)
) STRICT;

-- Una mesa no puede tener dos órdenes abiertas.
CREATE UNIQUE INDEX ux_orders_open_table ON orders (table_id) WHERE status = 'open' AND table_id IS NOT NULL;

CREATE TABLE order_items (
  id               TEXT    PRIMARY KEY,
  order_id         TEXT    NOT NULL REFERENCES orders (id),
  product_id       TEXT    NOT NULL REFERENCES products (id),
  quantity_milli   INTEGER NOT NULL CHECK (quantity_milli > 0),
  unit_price_cents INTEGER NOT NULL CHECK (unit_price_cents >= 0),
  notes            TEXT,
  station          TEXT    NOT NULL CHECK (station IN ('none', 'kitchen', 'bar')),
  status           TEXT    NOT NULL DEFAULT 'pending'
                           CHECK (status IN ('pending', 'sent', 'preparing', 'ready', 'served', 'cancelled')),
  created_by       TEXT    NOT NULL REFERENCES users (id),
  created_at       TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  sent_at          TEXT,
  ready_at         TEXT
) STRICT;

CREATE INDEX ix_order_items_order   ON order_items (order_id);
CREATE INDEX ix_order_items_kitchen ON order_items (station, status) WHERE status IN ('sent', 'preparing', 'ready');

CREATE TABLE sales (
  id                   TEXT    PRIMARY KEY,
  number               INTEGER NOT NULL UNIQUE CHECK (number > 0),
  status               TEXT    NOT NULL CHECK (status IN ('completed', 'voided')),
  price_mode           TEXT    NOT NULL CHECK (price_mode IN ('tax_included', 'tax_excluded')),
  cashier_id           TEXT    NOT NULL REFERENCES users (id),
  cash_session_id      TEXT    NOT NULL REFERENCES cash_sessions (id),
  customer_id          TEXT    REFERENCES customers (id),
  order_id             TEXT    UNIQUE REFERENCES orders (id),
  fiscal_document_type TEXT,
  ncf                  TEXT    UNIQUE,
  -- RNC o cédula del comprador (obligatorio para crédito fiscal B01/E31).
  buyer_document_id    TEXT,
  subtotal_cents       INTEGER NOT NULL CHECK (subtotal_cents >= 0),
  discount_cents       INTEGER NOT NULL CHECK (discount_cents >= 0),
  tax_cents            INTEGER NOT NULL CHECK (tax_cents >= 0),
  tip_cents            INTEGER NOT NULL CHECK (tip_cents >= 0),
  delivery_fee_cents   INTEGER NOT NULL DEFAULT 0 CHECK (delivery_fee_cents >= 0),
  total_cents          INTEGER NOT NULL CHECK (total_cents >= 0),
  change_cents         INTEGER NOT NULL DEFAULT 0 CHECK (change_cents >= 0),
  created_at           TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  voided_at            TEXT,
  voided_by            TEXT    REFERENCES users (id),
  void_reason          TEXT,
  CHECK (total_cents = subtotal_cents + tax_cents + tip_cents + delivery_fee_cents),
  CHECK ((status = 'voided') = (voided_at IS NOT NULL)),
  CHECK (voided_at IS NULL OR (voided_by IS NOT NULL AND length(trim(void_reason)) > 0)),
  CHECK ((fiscal_document_type IS NULL) = (ncf IS NULL))
) STRICT;

CREATE INDEX ix_sales_session  ON sales (cash_session_id);
CREATE INDEX ix_sales_created  ON sales (created_at);
CREATE INDEX ix_sales_customer ON sales (customer_id) WHERE customer_id IS NOT NULL;

CREATE TABLE sale_items (
  id               TEXT    PRIMARY KEY,
  sale_id          TEXT    NOT NULL REFERENCES sales (id),
  position         INTEGER NOT NULL CHECK (position >= 0),
  product_id       TEXT    REFERENCES products (id),
  description      TEXT    NOT NULL CHECK (length(trim(description)) > 0),
  unit_price_cents INTEGER NOT NULL CHECK (unit_price_cents >= 0),
  quantity_milli   INTEGER NOT NULL CHECK (quantity_milli > 0),
  tax_rate         TEXT    NOT NULL CHECK (tax_rate IN ('exempt', 'reduced', 'standard')),
  -- Descuento de la línea más su parte del descuento general.
  discount_cents   INTEGER NOT NULL DEFAULT 0 CHECK (discount_cents >= 0),
  net_cents        INTEGER NOT NULL CHECK (net_cents >= 0),
  -- Costo unitario al momento de vender, para calcular margen.
  unit_cost_cents  INTEGER NOT NULL DEFAULT 0 CHECK (unit_cost_cents >= 0),
  UNIQUE (sale_id, position)
) STRICT;

CREATE INDEX ix_sale_items_product ON sale_items (product_id);

CREATE TABLE sale_payments (
  id           TEXT    PRIMARY KEY,
  sale_id      TEXT    NOT NULL REFERENCES sales (id),
  method       TEXT    NOT NULL CHECK (method IN ('cash', 'card', 'transfer', 'credit')),
  amount_cents INTEGER NOT NULL CHECK (amount_cents > 0),
  -- Aprobación del voucher o referencia de la transferencia.
  reference    TEXT
) STRICT;

CREATE INDEX ix_sale_payments_sale ON sale_payments (sale_id);

-- Libro del fiao: cargos (ventas a crédito) y abonos.
CREATE TABLE credit_entries (
  id              TEXT    PRIMARY KEY,
  customer_id     TEXT    NOT NULL REFERENCES customers (id),
  kind            TEXT    NOT NULL CHECK (kind IN ('charge', 'payment', 'charge_void')),
  -- Positivo aumenta la deuda; negativo la reduce.
  amount_cents    INTEGER NOT NULL CHECK (amount_cents <> 0),
  sale_id         TEXT    REFERENCES sales (id),
  cash_session_id TEXT    REFERENCES cash_sessions (id),
  method          TEXT    CHECK (method IS NULL OR method IN ('cash', 'card', 'transfer')),
  note            TEXT,
  user_id         TEXT    NOT NULL REFERENCES users (id),
  created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  CHECK (
    (kind = 'charge'      AND amount_cents > 0 AND sale_id IS NOT NULL) OR
    (kind = 'charge_void' AND amount_cents < 0 AND sale_id IS NOT NULL) OR
    (kind = 'payment'     AND amount_cents < 0 AND method IS NOT NULL)
  ),
  -- Un abono en efectivo entra a la caja abierta.
  CHECK (method IS NOT 'cash' OR cash_session_id IS NOT NULL)
) STRICT;

CREATE INDEX ix_credit_entries_customer ON credit_entries (customer_id, created_at);
CREATE INDEX ix_credit_entries_session  ON credit_entries (cash_session_id) WHERE cash_session_id IS NOT NULL;

CREATE TABLE suppliers (
  id          TEXT    PRIMARY KEY,
  name        TEXT    NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 80),
  document_id TEXT    CHECK (document_id IS NULL OR (document_id NOT GLOB '*[^0-9]*' AND length(document_id) IN (9, 11))),
  phone       TEXT,
  active      INTEGER NOT NULL DEFAULT 1 CHECK (active IN (0, 1)),
  created_at  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT;

-- Compras a suplidores: alimentan el inventario, el costo promedio y el formato 606.
CREATE TABLE purchases (
  id             TEXT    PRIMARY KEY,
  supplier_id    TEXT    REFERENCES suppliers (id),
  ncf            TEXT,
  invoice_date   TEXT    NOT NULL CHECK (invoice_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'),
  subtotal_cents INTEGER NOT NULL CHECK (subtotal_cents >= 0),
  tax_cents      INTEGER NOT NULL CHECK (tax_cents >= 0),
  total_cents    INTEGER NOT NULL CHECK (total_cents >= 0),
  payment_method TEXT    NOT NULL CHECK (payment_method IN ('cash', 'card', 'transfer', 'credit')),
  -- Pago en efectivo desde la caja abierta.
  cash_session_id TEXT   REFERENCES cash_sessions (id),
  user_id        TEXT    NOT NULL REFERENCES users (id),
  created_at     TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  CHECK (total_cents = subtotal_cents + tax_cents),
  UNIQUE (supplier_id, ncf)
) STRICT;

CREATE INDEX ix_purchases_date ON purchases (invoice_date);

CREATE TABLE purchase_items (
  id              TEXT    PRIMARY KEY,
  purchase_id     TEXT    NOT NULL REFERENCES purchases (id),
  position        INTEGER NOT NULL CHECK (position >= 0),
  product_id      TEXT    NOT NULL REFERENCES products (id),
  quantity_milli  INTEGER NOT NULL CHECK (quantity_milli > 0),
  unit_cost_cents INTEGER NOT NULL CHECK (unit_cost_cents >= 0),
  UNIQUE (purchase_id, position)
) STRICT;

-- Movimientos de inventario. La existencia de products se actualiza por trigger.
CREATE TABLE stock_movements (
  id              INTEGER PRIMARY KEY,
  product_id      TEXT    NOT NULL REFERENCES products (id),
  kind            TEXT    NOT NULL CHECK (kind IN ('sale', 'sale_void', 'purchase', 'adjustment', 'waste')),
  -- Positivo entra, negativo sale.
  quantity_milli  INTEGER NOT NULL CHECK (quantity_milli <> 0),
  unit_cost_cents INTEGER CHECK (unit_cost_cents IS NULL OR unit_cost_cents >= 0),
  sale_item_id    TEXT    REFERENCES sale_items (id),
  purchase_item_id TEXT   REFERENCES purchase_items (id),
  note            TEXT,
  user_id         TEXT    REFERENCES users (id),
  created_at      TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT;

CREATE INDEX ix_stock_movements_product ON stock_movements (product_id, created_at);

-- Bitácora de acciones sensibles (anulaciones, descuentos, cierres de caja...).
CREATE TABLE audit_log (
  id         INTEGER PRIMARY KEY,
  action     TEXT    NOT NULL,
  user_id    TEXT    REFERENCES users (id),
  entity     TEXT,
  entity_id  TEXT,
  details    TEXT    CHECK (details IS NULL OR json_valid(details)),
  created_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
) STRICT;

CREATE INDEX ix_audit_log_entity ON audit_log (entity, entity_id);
CREATE INDEX ix_audit_log_created ON audit_log (created_at);
