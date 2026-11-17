-- Q1. Monthly revenue and order growth (month-over-month %)
-- Snowflake version of sql/q1_monthly_revenue_trend.sql.
-- SNOWFLAKE: no dialect changes needed. CTEs, LAG, NULLIF and running totals are standard SQL.
--
-- Plain English:
--   1. monthly: collapse orders to one row per month (revenue, orders, buyers).
--   2. with_prev: LAG() looks one row back (the previous month) and 12 rows back
--      (same month last year) so we can compare without a self-join.
--   3. Final SELECT turns those into growth %. NULLIF(x,0) avoids divide-by-zero.
--   Caution: early-2018 YoY looks huge (+705% in Jan) only because Jan 2017 was
--   the platform's ramp-up month. Late-2018 YoY (~+50-100%) is the honest read.

-- @export: q1_monthly_revenue.csv
WITH monthly AS (
    SELECT
        order_month,
        COUNT(*)                            AS orders,
        COUNT(DISTINCT customer_unique_id)  AS unique_customers,
        SUM(gross_revenue)                  AS revenue,
        SUM(product_revenue)                AS product_revenue
    FROM orders_clean
    GROUP BY order_month
),
with_prev AS (
    SELECT
        *,
        LAG(revenue)     OVER (ORDER BY order_month)     AS prev_revenue,
        LAG(orders)      OVER (ORDER BY order_month)     AS prev_orders,
        LAG(revenue, 12) OVER (ORDER BY order_month)     AS revenue_last_year
    FROM monthly
)
SELECT
    order_month,
    orders,
    unique_customers,
    ROUND(revenue, 2)                                                AS revenue,
    ROUND(revenue / orders, 2)                                       AS avg_order_value,
    ROUND(100.0 * (revenue - prev_revenue) / NULLIF(prev_revenue, 0), 1)  AS revenue_mom_pct,
    ROUND(100.0 * (orders - prev_orders)  / NULLIF(prev_orders, 0), 1)    AS orders_mom_pct,
    ROUND(100.0 * (revenue - revenue_last_year) / NULLIF(revenue_last_year, 0), 1) AS revenue_yoy_pct,
    ROUND(SUM(revenue) OVER (ORDER BY order_month), 2)               AS cumulative_revenue
FROM with_prev
ORDER BY order_month
