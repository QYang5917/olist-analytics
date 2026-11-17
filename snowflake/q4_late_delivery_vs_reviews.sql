-- Q4. Does late delivery hurt review scores? Quantify the difference.
-- Snowflake version of sql/q4_late_delivery_vs_reviews.sql.
-- Dialect changes from the DuckDB version are marked with 'SNOWFLAKE:'.
-- SNOWFLAKE: ::FLOAT inside every AVG of whole numbers. Snowflake's AVG of integers keeps
-- only 6 decimals (NUMBER(38,6)); DuckDB's returns a full-precision DOUBLE. Without the
-- cast, a value rounded again later can land 0.001 away from DuckDB's.
--
-- Plain English:
--   1. joined: one row per delivered order with its (deduplicated) review.
--   2. Summary: average score, % of 1-2 star ("bad") reviews and % of 5-star
--      reviews for late vs on-time orders.
--   3. We also compute a 95% confidence interval for the difference in mean
--      score (Welch's formula: SE = sqrt(s1^2/n1 + s2^2/n2)) so we can say
--      whether the gap is real, not just noise.
--   4. AUDIT NOTE: Olist sends the review survey around the ESTIMATED date, so
--      most late orders are reviewed before the package arrives. The score
--      therefore measures "you broke your promise", not product quality.

-- @export: q4a_late_vs_ontime.csv
WITH joined AS (
    SELECT d.order_id, d.is_late, d.days_vs_estimate, r.review_score,
           r.review_creation_date::DATE < o.order_delivered_customer_date::DATE AS reviewed_before_arrival
    FROM deliveries d
    JOIN reviews_dedup r USING (order_id)
    JOIN orders o        USING (order_id)
),
grp AS (
    SELECT
        CASE WHEN is_late THEN 'late' ELSE 'on_time' END        AS delivery_status,
        COUNT(*)                                                AS orders,
        AVG(review_score::FLOAT)                                AS avg_score,
        STDDEV_SAMP(review_score)                               AS sd_score,
        100.0 * AVG((CASE WHEN review_score <= 2 THEN 1 ELSE 0 END)::FLOAT) AS pct_1_2_star,
        100.0 * AVG((CASE WHEN review_score = 5  THEN 1 ELSE 0 END)::FLOAT) AS pct_5_star,
        100.0 * AVG((CASE WHEN reviewed_before_arrival THEN 1 ELSE 0 END)::FLOAT) AS pct_reviewed_before_arrival
    FROM joined
    GROUP BY 1
)
SELECT
    g.delivery_status,
    g.orders,
    ROUND(100.0 * g.orders / SUM(g.orders) OVER (), 2)       AS pct_of_orders,
    ROUND(g.avg_score, 3)                                    AS avg_score,
    ROUND(g.pct_1_2_star, 2)                                 AS pct_1_2_star,
    ROUND(g.pct_5_star, 2)                                   AS pct_5_star,
    ROUND(g.pct_reviewed_before_arrival, 1)                  AS pct_reviewed_before_arrival,
    -- difference vs on-time with 95% CI. AUDIT FIX: NULL on the on_time row
    -- (comparing a group to itself is meaningless).
    CASE WHEN g.delivery_status = 'late' THEN ROUND(g.avg_score - o.avg_score, 3) END AS score_diff_vs_ontime,
    -- SNOWFLAKE: POWER(x, 2) replaces x^2. Snowflake has no ^ operator for powers.
    CASE WHEN g.delivery_status = 'late' THEN ROUND(g.avg_score - o.avg_score - 1.96 * SQRT(POWER(g.sd_score, 2) / g.orders + POWER(o.sd_score, 2) / o.orders), 3) END AS diff_ci95_low,
    CASE WHEN g.delivery_status = 'late' THEN ROUND(g.avg_score - o.avg_score + 1.96 * SQRT(POWER(g.sd_score, 2) / g.orders + POWER(o.sd_score, 2) / o.orders), 3) END AS diff_ci95_high
FROM grp g
CROSS JOIN (SELECT * FROM grp WHERE delivery_status = 'on_time') o
ORDER BY g.delivery_status DESC NULLS LAST;   -- SNOWFLAKE: NULLS LAST written out

-- @export: q4c_late_gap_by_state.csv
-- Confounding check: maybe late orders just come from states that review
-- harshly anyway. Compare late vs on-time WITHIN each state. If the gap holds
-- in every state, geography doesn't explain it.
WITH joined AS (
    SELECT d.customer_state, d.is_late, r.review_score
    FROM deliveries d
    JOIN reviews_dedup r USING (order_id)
)
SELECT
    customer_state,
    -- SNOWFLAKE: no FILTER (WHERE ...) clause. COUNT_IF(condition) for counts, and
    -- AVG(CASE WHEN condition THEN value END) for averages (AVG skips the NULLs).
    COUNT_IF(is_late)                                                 AS late_orders,
    COUNT_IF(NOT is_late)                                             AS on_time_orders,
    ROUND(AVG(CASE WHEN is_late THEN review_score::FLOAT END), 3)            AS avg_score_late,
    ROUND(AVG(CASE WHEN NOT is_late THEN review_score::FLOAT END), 3)        AS avg_score_on_time,
    ROUND(AVG(CASE WHEN is_late THEN review_score::FLOAT END)
        - AVG(CASE WHEN NOT is_late THEN review_score::FLOAT END), 3)        AS late_gap
FROM joined
GROUP BY customer_state
HAVING COUNT_IF(is_late) >= 30                    -- need enough late orders for a stable mean
ORDER BY late_gap;

-- @export: q4b_score_by_days_late.csv
-- Dose-response: does the damage grow with how late the package is?
-- Bucketing days_vs_estimate shows whether "1 day late" is already harmful.
WITH joined AS (
    SELECT d.days_vs_estimate, r.review_score
    FROM deliveries d
    JOIN reviews_dedup r USING (order_id)
),
bucketed AS (
    SELECT
        CASE
            WHEN days_vs_estimate <= -15 THEN '1. 15+ days early'
            WHEN days_vs_estimate <= -8  THEN '2. 8-14 days early'
            WHEN days_vs_estimate <= -1  THEN '3. 1-7 days early'
            WHEN days_vs_estimate =  0   THEN '4. on estimated day'
            WHEN days_vs_estimate <= 3   THEN '5. 1-3 days late'
            WHEN days_vs_estimate <= 7   THEN '6. 4-7 days late'
            WHEN days_vs_estimate <= 14  THEN '7. 8-14 days late'
            ELSE                              '8. 15+ days late'
        END AS delivery_bucket,
        review_score
    FROM joined
)
SELECT
    delivery_bucket,
    COUNT(*)                                                       AS orders,
    ROUND(AVG(review_score::FLOAT), 3)                             AS avg_score,
    ROUND(100.0 * AVG((CASE WHEN review_score <= 2 THEN 1 ELSE 0 END)::FLOAT), 2) AS pct_1_2_star
FROM bucketed
GROUP BY delivery_bucket
ORDER BY delivery_bucket;
