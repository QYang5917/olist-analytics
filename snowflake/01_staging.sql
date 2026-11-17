-- 01_staging.sql (Snowflake version of sql/01_staging.sql)
-- Dialect changes from the DuckDB version are marked with 'SNOWFLAKE:'.
-- Clean, reusable views. Every business rule lives here ONCE so all five
-- analyses use the same definitions. Each rule is justified by a profiling
-- result documented in docs/data_quality_audit.md.

-- ---------------------------------------------------------------------------
-- order_totals: ONE row per order with its item revenue.
-- order_items has one row per item, so we aggregate BEFORE joining anything
-- else; joining raw items to payments (also many rows per order) would
-- multiply rows and double-count revenue.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW order_totals AS
SELECT
    order_id,
    COUNT(*)                      AS n_items,
    SUM(price)                    AS product_revenue,
    SUM(freight_value)            AS freight_revenue,
    SUM(price + freight_value)    AS gross_revenue
FROM order_items
GROUP BY order_id;

-- ---------------------------------------------------------------------------
-- orders_clean: one row per order, tied to the REAL customer.
--   * customer_unique_id = the person. customer_id is regenerated per order,
--     so it cannot be used for retention.
--   * canceled / unavailable orders never produced revenue -> excluded.
--   * analysis window = Jan 2017 .. Aug 2018. 2016 has ~330 orders (and zero
--     in Nov 2016) and Sep/Oct 2018 have 20 orders total: the export is
--     truncated, so those months would create fake growth/collapse.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW orders_clean AS
SELECT
    o.order_id,
    c.customer_unique_id,
    c.customer_state,
    o.order_status,
    o.order_purchase_timestamp,
    DATE_TRUNC('month', o.order_purchase_timestamp)::DATE AS order_month,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    t.n_items,
    t.product_revenue,
    t.freight_revenue,
    t.gross_revenue
FROM orders o
JOIN customers c   ON c.customer_id = o.customer_id      -- 1:1, verified
JOIN order_totals t ON t.order_id   = o.order_id         -- inner join drops 775 orders with no items (almost all canceled/unavailable)
WHERE o.order_status NOT IN ('canceled', 'unavailable')
  AND o.order_purchase_timestamp >= TIMESTAMP '2017-01-01'
  AND o.order_purchase_timestamp <  TIMESTAMP '2018-09-01';

-- ---------------------------------------------------------------------------
-- reviews_dedup: ONE review per order.
-- 547 orders have 2+ reviews (customer re-reviewed). Keep the most recent
-- answer so each order is counted once in review averages.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW reviews_dedup AS
SELECT order_id, review_score, review_creation_date
FROM (
    SELECT
        order_id,
        review_score,
        review_creation_date,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            -- SNOWFLAKE: NULLS LAST written out. Snowflake sorts NULLs first on DESC,
            -- DuckDB sorts them last; stating it keeps the two identical.
            ORDER BY review_answer_timestamp DESC NULLS LAST, review_creation_date DESC NULLS LAST, review_id
        ) AS rn
    FROM order_reviews
)
WHERE rn = 1;

-- ---------------------------------------------------------------------------
-- deliveries: delivered orders with delivery metrics.
--   * Only status = 'delivered' AND a non-null delivery date (8 delivered
--     orders have no date; 6 non-delivered orders have one -> both dropped).
--   * The estimated date is a DATE stored as midnight, so lateness is
--     compared at DATE level. A timestamp comparison would call a package
--     that arrived at 3pm on the promised day "late" (+1,292 false lates).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW deliveries AS
SELECT
    order_id,
    customer_unique_id,
    customer_state,
    order_month,
    -- SNOWFLAKE: DATEDIFF (one word) instead of DuckDB's DATE_DIFF. Same arguments, same result.
    DATEDIFF('day', order_purchase_timestamp::DATE, order_delivered_customer_date::DATE)       AS delivery_days,
    DATEDIFF('day', order_estimated_delivery_date::DATE, order_delivered_customer_date::DATE)  AS days_vs_estimate, -- >0 = late
    order_delivered_customer_date::DATE > order_estimated_delivery_date::DATE                 AS is_late
FROM orders_clean
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NOT NULL;

-- ---------------------------------------------------------------------------
-- items_with_category: item-level rows with an English category name.
-- 623 products have no category -> 'unknown'. Two Portuguese categories are
-- missing from the translation file -> fall back to the Portuguese name.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW items_with_category AS
SELECT
    i.order_id,
    o.order_month,
    i.price,
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category
FROM order_items i
JOIN orders_clean o              ON o.order_id = i.order_id
LEFT JOIN products p             ON p.product_id = i.product_id
LEFT JOIN category_translation t ON t.product_category_name = p.product_category_name;
