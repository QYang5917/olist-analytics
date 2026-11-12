-- Q2. Top product categories by revenue, and which are growing vs shrinking
--
-- Growth is measured on the SAME calendar months (Jan-Aug 2018 vs Jan-Aug 2017)
-- because 2018 data stops in August and November has Black Friday.
--
-- AUDIT FIX: the whole platform grew +138% over this period, so raw growth %
-- labelled almost every category "growing fast". A category growing +50%
-- while the market grows +138% is actually LOSING ground. So the trend label
-- is now based on SHARE of revenue: did the category's slice of the pie get
-- bigger or smaller? Raw YoY % is kept as a column for reference.
--
-- Revenue = item price only (freight is a shipping charge, not a product sale).
--
-- Plain English:
--   1. by_period: one row per category; revenue in each period via
--      conditional aggregation (SUM ... FILTER (WHERE ...)) -- a pivot in one pass.
--   2. ranked: RANK() orders categories by total revenue. SUM(x) OVER () puts the
--      grand total on every row, so x / SUM(x) OVER () = share of total.
--   3. Final SELECT: share change in percentage points decides the label.
--      Categories under R$20k in Jan-Aug 2017 are too small to judge.

-- @export: q2_category_revenue.csv
WITH by_period AS (
    SELECT
        category,
        SUM(price)                                                       AS revenue,
        COUNT(DISTINCT order_id)                                         AS orders,
        COALESCE(SUM(price) FILTER (WHERE order_month BETWEEN DATE '2017-01-01' AND DATE '2017-08-01'), 0) AS rev_2017,
        COALESCE(SUM(price) FILTER (WHERE order_month BETWEEN DATE '2018-01-01' AND DATE '2018-08-01'), 0) AS rev_2018
    FROM items_with_category
    GROUP BY category
),
ranked AS (
    SELECT
        *,
        RANK() OVER (ORDER BY revenue DESC)              AS revenue_rank,
        100.0 * revenue  / SUM(revenue)  OVER ()         AS revenue_share_pct,
        100.0 * rev_2017 / SUM(rev_2017) OVER ()         AS share_2017_pct,
        100.0 * rev_2018 / SUM(rev_2018) OVER ()         AS share_2018_pct,
        100.0 * (rev_2018 - rev_2017) / NULLIF(rev_2017, 0)                   AS yoy_growth_pct,
        100.0 * (SUM(rev_2018) OVER () - SUM(rev_2017) OVER ()) / SUM(rev_2017) OVER () AS platform_growth_pct
    FROM by_period
)
SELECT
    revenue_rank,
    category,
    ROUND(revenue, 2)                        AS revenue,
    orders,
    ROUND(revenue_share_pct, 2)              AS revenue_share_pct,
    ROUND(rev_2017, 2)                       AS rev_jan_aug_2017,
    ROUND(rev_2018, 2)                       AS rev_jan_aug_2018,
    ROUND(yoy_growth_pct, 1)                 AS yoy_growth_pct,
    ROUND(platform_growth_pct, 1)            AS platform_growth_pct,
    ROUND(share_2018_pct - share_2017_pct, 2) AS share_change_pp,
    CASE
        WHEN rev_2017 < 20000                       THEN 'too small to judge'
        WHEN share_2018_pct - share_2017_pct >=  0.25 THEN 'gaining share'
        WHEN share_2018_pct - share_2017_pct <= -0.25 THEN 'losing share'
        ELSE 'stable share'
    END                                      AS trend
FROM ranked
ORDER BY revenue_rank
