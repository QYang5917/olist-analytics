-- Q5. Which states have the longest delivery times and lowest review scores?
-- Snowflake version of sql/q5_state_delivery_reviews.sql.
-- Dialect changes from the DuckDB version are marked with 'SNOWFLAKE:'.
-- SNOWFLAKE: ::FLOAT inside every AVG of whole numbers. Snowflake's AVG of integers keeps
-- only 6 decimals (NUMBER(38,6)); DuckDB's returns a full-precision DOUBLE. Without the
-- cast, a value rounded again later can land 0.001 away from DuckDB's.
--
-- Plain English:
--   1. state_stats: per customer state, average AND median delivery days
--      (median resists a few 100-day outliers), late rate, average review.
--      LEFT JOIN to reviews so orders without a review still count toward
--      delivery time.
--   2. Final: RANK() twice -- once by slowest delivery, once by worst review --
--      so you can see if the same states top both lists. States with < 300
--      delivered orders are kept but flagged (averages on tiny samples are noisy).
--   3. CORR() over all states quantifies the link between delivery time and
--      review score at state level.
--   AUDIT FINDING: late RATE correlates far more strongly with reviews than
--   raw delivery DAYS. Slow states with honest (long) estimates, like AM and
--   AP, still review well -> customers punish broken promises, not distance.

-- @export: q5_state_delivery_reviews.csv
WITH state_stats AS (
    SELECT
        d.customer_state,
        COUNT(*)                                        AS delivered_orders,
        AVG(d.delivery_days::FLOAT)                     AS avg_delivery_days,
        MEDIAN(d.delivery_days)                         AS median_delivery_days,
        100.0 * AVG((CASE WHEN d.is_late THEN 1 ELSE 0 END)::FLOAT) AS late_rate_pct,
        AVG(r.review_score::FLOAT)                      AS avg_review_score,
        COUNT(r.review_score)                           AS reviewed_orders
    FROM deliveries d
    LEFT JOIN reviews_dedup r USING (order_id)
    GROUP BY d.customer_state
)
SELECT
    customer_state,
    delivered_orders,
    ROUND(avg_delivery_days, 1)                          AS avg_delivery_days,
    median_delivery_days,
    ROUND(late_rate_pct, 1)                              AS late_rate_pct,
    ROUND(avg_review_score, 3)                           AS avg_review_score,
    RANK() OVER (ORDER BY avg_delivery_days DESC NULLS LAST) AS slowest_rank,   -- SNOWFLAKE: NULLS LAST written out
    RANK() OVER (ORDER BY avg_review_score ASC)          AS worst_review_rank,
    delivered_orders < 300                               AS small_sample_flag,
    ROUND(CORR(avg_delivery_days, avg_review_score) OVER (), 3) AS corr_delivery_days_vs_review,
    ROUND(CORR(late_rate_pct,     avg_review_score) OVER (), 3) AS corr_late_rate_vs_review
FROM state_stats
ORDER BY avg_delivery_days DESC NULLS LAST
