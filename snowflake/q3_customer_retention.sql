-- Q3. Customer retention
-- Snowflake version of sql/q3_customer_retention.sql.
-- Dialect changes from the DuckDB version are marked with 'SNOWFLAKE:'.
--   (a) What % of customers ever make a second purchase?
--   (b) Cohort retention: of customers whose first purchase was in month M,
--       what % bought again 1, 2, 3 ... months later?
--
-- Key definitions:
--   * Customer = customer_unique_id (customer_id changes on every order).
--   * A "purchase" = a distinct purchase DAY. One checkout with items from
--     several sellers is split into several orders on the same timestamp;
--     counting those as repeat purchases would inflate repeat rate ~40%.

-- @export: q3a_repeat_purchase_rate.csv
-- Plain English:
--   1. purchase_days: one row per customer per purchase DAY.
--   2. per_customer: first purchase date, number of purchase days, and whether
--      they came back within 180 days of the first purchase.
--   3. Final: repeat rates per first-purchase year, plus an 'all' total row
--      via GROUP BY ROLLUP.
-- AUDIT FIX: "ever repeated" is unfair to recent customers (someone who first
-- bought in Aug 2018 had days, not months, to return). repeat_180d_pct only
-- counts customers we could watch for a full 180 days (first purchase on or
-- before 2018-03-04), so every customer gets the same chance.
WITH purchase_days AS (
    SELECT DISTINCT customer_unique_id, order_purchase_timestamp::DATE AS purchase_date
    FROM orders_clean
),
first_purchase AS (
    SELECT customer_unique_id, MIN(purchase_date) AS first_purchase
    FROM purchase_days
    GROUP BY customer_unique_id
),
per_customer AS (
    SELECT
        f.customer_unique_id,
        f.first_purchase,
        COUNT(*)                                                         AS n_purchase_days,
        -- SNOWFLAKE: BOOLOR_AGG is Snowflake's name for BOOL_OR ("true if any row is true").
        -- SNOWFLAKE: DATEADD('day', n, date) replaces DuckDB's date + INTERVAL n DAY.
        BOOLOR_AGG(d.purchase_date >  f.first_purchase
            AND d.purchase_date <= DATEADD('day', 180, f.first_purchase)) AS repeat_within_180d,
        f.first_purchase <= DATEADD('day', -180, DATE '2018-08-31')       AS observable_180d
    FROM first_purchase f
    JOIN purchase_days d USING (customer_unique_id)
    GROUP BY f.customer_unique_id, f.first_purchase
)
SELECT
    COALESCE(CAST(YEAR(first_purchase) AS VARCHAR), 'all')                 AS first_purchase_year,
    COUNT(*)                                                               AS customers,
    -- SNOWFLAKE: COUNT_IF(condition) replaces COUNT(*) FILTER (WHERE condition).
    COUNT_IF(n_purchase_days >= 2)                                         AS repeat_customers_ever,
    ROUND(100.0 * COUNT_IF(n_purchase_days >= 2) / COUNT(*), 2)            AS repeat_rate_ever_pct,
    COUNT_IF(observable_180d)                                              AS customers_observable_180d,
    ROUND(100.0 * COUNT_IF(observable_180d AND repeat_within_180d)
          / NULLIF(COUNT_IF(observable_180d), 0), 2)                       AS repeat_180d_pct
FROM per_customer
GROUP BY ROLLUP (YEAR(first_purchase))
ORDER BY first_purchase_year;

-- @export: q3b_cohort_retention.csv
-- Plain English:
--   1. first_month: each customer's cohort = month of their first order.
--   2. activity: every (customer, month) they bought in, tagged with
--      month_number = months since their cohort month (0 = first month).
--   3. cohort_size: customers per cohort (the denominator).
--   4. Final: % of the cohort active in each later month.
--   Right-censoring: the Jan-2018 cohort can only be observed for 7 months,
--   so months we cannot observe yet are simply absent (not counted as 0%).
WITH first_month AS (
    SELECT customer_unique_id, MIN(order_month) AS cohort_month
    FROM orders_clean
    GROUP BY customer_unique_id
),
activity AS (
    SELECT DISTINCT
        o.customer_unique_id,
        f.cohort_month,
        DATEDIFF('month', f.cohort_month, o.order_month) AS month_number    -- SNOWFLAKE: DATEDIFF, not DATE_DIFF
    FROM orders_clean o
    JOIN first_month f USING (customer_unique_id)
),
cohort_size AS (
    SELECT cohort_month, COUNT(*) AS cohort_customers
    FROM first_month
    GROUP BY cohort_month
)
SELECT
    a.cohort_month,
    s.cohort_customers,
    a.month_number,
    COUNT(*)                                          AS active_customers,
    ROUND(100.0 * COUNT(*) / s.cohort_customers, 2)   AS retention_pct
FROM activity a
JOIN cohort_size s USING (cohort_month)
WHERE a.month_number >= 1          -- month 0 is 100% by definition
GROUP BY a.cohort_month, s.cohort_customers, a.month_number
ORDER BY a.cohort_month, a.month_number;
