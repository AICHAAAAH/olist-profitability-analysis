-- =========================================================
-- 03_profitability_view.sql
--
-- Business question:
-- "Which product categories and regions generate strong
--  revenue but weak margin, once shipping cost is factored
--  in — and where should the business investigate further?"
--
-- Note on methodology:
-- Olist's public dataset does not include cost-of-goods-sold
-- or discount fields, so a literal "profit" figure is not
-- available. We use (price - freight_value) as a MARGIN PROXY:
-- it approximates how much of each sale is absorbed by
-- shipping cost, which is a real and meaningful driver of
-- profitability for e-commerce businesses. This assumption
-- is stated explicitly in the README.
-- =========================================================

DROP VIEW IF EXISTS order_item_margin CASCADE;

-- Line-item level margin proxy
CREATE VIEW order_item_margin AS
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    ct.product_category_name_english          AS category,
    o.customer_id,
    c.customer_state,
    c.customer_city,
    o.order_purchase_timestamp,
    oi.price,
    oi.freight_value,
    (oi.price - oi.freight_value)              AS margin_proxy,
    ROUND(
        (oi.price - oi.freight_value) / NULLIF(oi.price, 0) * 100, 2
    )                                           AS margin_pct
FROM order_items oi
JOIN orders o        ON oi.order_id = o.order_id
JOIN customers c     ON o.customer_id = c.customer_id
JOIN products p      ON oi.product_id = p.product_id
LEFT JOIN category_translation ct
       ON p.product_category_name = ct.product_category_name
WHERE o.order_status = 'delivered';   -- only count completed sales

-- =========================================================
-- Category-level summary: revenue, margin proxy, and margin %
-- This is the main table your Power BI dashboard will read from.
-- =========================================================
DROP VIEW IF EXISTS category_profitability CASCADE;

CREATE VIEW category_profitability AS
SELECT
    category,
    COUNT(*)                          AS items_sold,
    ROUND(SUM(price), 2)              AS total_revenue,
    ROUND(SUM(freight_value), 2)      AS total_freight_cost,
    ROUND(SUM(margin_proxy), 2)       AS total_margin_proxy,
    ROUND(AVG(margin_pct), 2)         AS avg_margin_pct,
    RANK() OVER (ORDER BY SUM(margin_proxy) DESC) AS margin_rank,
    RANK() OVER (ORDER BY SUM(price) DESC)        AS revenue_rank
FROM order_item_margin
WHERE category IS NOT NULL
GROUP BY category
ORDER BY total_revenue DESC;

-- =========================================================
-- Two key insight queries.
--
-- rank_gap = margin_rank - revenue_rank
--   POSITIVE gap = margin_rank number is HIGHER (worse) than
--   revenue_rank number => category sells well but margin
--   lags behind => "revenue is flattering this category"
--   NEGATIVE gap = margin outperforms revenue rank =>
--   "hidden gem" => quietly strong margin relative to sales
-- =========================================================

-- (A) MARGIN-RISK categories: strong revenue, weaker margin.
-- This is the finding to lead your executive summary with.
SELECT
    category,
    total_revenue,
    total_margin_proxy,
    avg_margin_pct,
    revenue_rank,
    margin_rank,
    (margin_rank - revenue_rank) AS rank_gap
FROM category_profitability
WHERE revenue_rank <= 20          -- focus on categories that already matter (top 20 by revenue)
ORDER BY rank_gap DESC
LIMIT 10;

-- (B) HIDDEN GEMS: margin outperforms what revenue rank suggests.
-- Good secondary finding — "invest more here" candidates.
SELECT
    category,
    total_revenue,
    total_margin_proxy,
    avg_margin_pct,
    revenue_rank,
    margin_rank,
    (margin_rank - revenue_rank) AS rank_gap
FROM category_profitability
ORDER BY rank_gap ASC
LIMIT 10;

-- =========================================================
-- (C) MARGIN EFFICIENCY among top revenue categories.
-- This turned out to be the sharper insight: category-level
-- rank_gap barely moves (shipping cost scales roughly with
-- price), but avg_margin_pct varies meaningfully even among
-- similarly-sized categories. This is likely your strongest
-- memo finding.
-- =========================================================
SELECT
    category,
    total_revenue,
    avg_margin_pct,
    revenue_rank
FROM category_profitability
WHERE revenue_rank <= 15
ORDER BY avg_margin_pct ASC
LIMIT 10;