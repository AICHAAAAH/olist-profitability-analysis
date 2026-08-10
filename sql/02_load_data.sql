-- =========================================================
-- 02_load_data.sql
-- Loads the raw Kaggle CSVs into the tables created in
-- 01_schema.sql. Run 01_schema.sql first.
--
-- IMPORTANT: adjust the file paths below to match where you
-- unzipped the Kaggle download on your machine.
-- Order of loading matters (parents before children) to
-- satisfy foreign key constraints.
-- =========================================================

\copy customers FROM 'data/raw/olist_customers_dataset.csv' DELIMITER ',' CSV HEADER;

\copy sellers FROM 'data/raw/olist_sellers_dataset.csv' DELIMITER ',' CSV HEADER;

\copy category_translation FROM 'data/raw/product_category_name_translation.csv' DELIMITER ',' CSV HEADER;

\copy products FROM 'data/raw/olist_products_dataset.csv' DELIMITER ',' CSV HEADER;

\copy orders FROM 'data/raw/olist_orders_dataset.csv' DELIMITER ',' CSV HEADER;

\copy order_items FROM 'data/raw/olist_order_items_dataset.csv' DELIMITER ',' CSV HEADER;

\copy order_payments FROM 'data/raw/olist_order_payments_dataset.csv' DELIMITER ',' CSV HEADER;

-- Quick sanity check after loading — row counts per table
SELECT 'customers' AS table_name, COUNT(*) FROM customers
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL
SELECT 'order_payments', COUNT(*) FROM order_payments
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL
SELECT 'category_translation', COUNT(*) FROM category_translation;