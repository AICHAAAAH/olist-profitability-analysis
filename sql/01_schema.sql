-- =========================================================
-- Olist Profitability Analysis
-- 01_schema.sql
-- Creates the core tables needed to analyze margin drivers
-- (price vs. freight cost) by product category, region, and
-- customer segment.
--
-- Source: Kaggle "Brazilian E-Commerce Public Dataset by Olist"
-- =========================================================

DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS order_payments CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS customers CASCADE;
DROP TABLE IF EXISTS sellers CASCADE;
DROP TABLE IF EXISTS category_translation CASCADE;

-- Customers: one row per customer *order* (customer_unique_id
-- links repeat customers across orders)
CREATE TABLE customers (
    customer_id             VARCHAR(50) PRIMARY KEY,
    customer_unique_id      VARCHAR(50) NOT NULL,
    customer_zip_code_prefix VARCHAR(10),
    customer_city           VARCHAR(100),
    customer_state          VARCHAR(2)
);

-- Orders: one row per order
CREATE TABLE orders (
    order_id                      VARCHAR(50) PRIMARY KEY,
    customer_id                   VARCHAR(50) REFERENCES customers(customer_id),
    order_status                  VARCHAR(20),
    order_purchase_timestamp      TIMESTAMP,
    order_approved_at             TIMESTAMP,
    order_delivered_carrier_date  TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP
);

-- Sellers
CREATE TABLE sellers (
    seller_id               VARCHAR(50) PRIMARY KEY,
    seller_zip_code_prefix  VARCHAR(10),
    seller_city             VARCHAR(100),
    seller_state            VARCHAR(2)
);

-- Product category name → English translation
CREATE TABLE category_translation (
    product_category_name          VARCHAR(100) PRIMARY KEY,
    product_category_name_english  VARCHAR(100)
);

-- Products
CREATE TABLE products (
    product_id                   VARCHAR(50) PRIMARY KEY,
    product_category_name        VARCHAR(100),  -- FK removed: a few categories in the raw
                                                  -- data (e.g. "pc_gamer") have no matching
                                                  -- row in the translation table. Handled via
                                                  -- LEFT JOIN + NULL filtering in the views.
    product_name_lenght          INT,
    product_description_lenght   INT,
    product_photos_qty           INT,
    product_weight_g             INT,
    product_length_cm            INT,
    product_height_cm            INT,
    product_width_cm             INT
);

-- Order items: one row per item within an order.
-- price = sale price customer paid for the item
-- freight_value = shipping cost charged to the customer
-- (price - freight_value) is our margin proxy per item.
CREATE TABLE order_items (
    order_id            VARCHAR(50) REFERENCES orders(order_id),
    order_item_id        INT,
    product_id           VARCHAR(50) REFERENCES products(product_id),
    seller_id            VARCHAR(50) REFERENCES sellers(seller_id),
    shipping_limit_date  TIMESTAMP,
    price                NUMERIC(10,2),
    freight_value        NUMERIC(10,2),
    PRIMARY KEY (order_id, order_item_id)
);

-- Payments: an order can have multiple payment rows
-- (installments, mixed payment types)
CREATE TABLE order_payments (
    order_id             VARCHAR(50) REFERENCES orders(order_id),
    payment_sequential   INT,
    payment_type         VARCHAR(20),
    payment_installments INT,
    payment_value        NUMERIC(10,2),
    PRIMARY KEY (order_id, payment_sequential)
);

-- Helpful indexes for the joins we'll run in 03_profitability_view.sql
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_items_order ON order_items(order_id);
CREATE INDEX idx_items_product ON order_items(product_id);
CREATE INDEX idx_payments_order ON order_payments(order_id);