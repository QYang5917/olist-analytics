-- ab_02_summary.sql (Snowflake version of sql/ab_02_summary.sql)
-- Dialect changes from the DuckDB version are marked with 'SNOWFLAKE:'.
-- SNOWFLAKE: every COUNT(*) FILTER (WHERE x) became COUNT_IF(x), and every other
-- aggregate with FILTER became the same aggregate over CASE WHEN x THEN value END.
-- SNOWFLAKE: ::FLOAT inside every AVG of whole numbers. Snowflake's AVG of integers keeps
-- only 6 decimals (NUMBER(38,6)); DuckDB's returns a full-precision DOUBLE. Without the
-- cast, a value rounded again later can land 0.001 away from DuckDB's.
-- Descriptive tables for the A/B test. The statistics (z-test, CIs, power)
-- are in ab_test.py because SQL has no normal-distribution functions.

-- @export: ab_cleaning_log.csv
-- How many rows / users each cleaning rule removed.
-- Plain English: count rows and distinct users at each stage using
-- conditional aggregation over the flagged view.
SELECT 'raw data'                                   AS stage,
       COUNT(*)                                     AS rows_,
       COUNT(DISTINCT user_id)                      AS users
FROM ab_flagged
UNION ALL
SELECT 'mismatched rows (group != page)',
       COUNT_IF(is_mismatch),
       COUNT(DISTINCT CASE WHEN is_mismatch THEN user_id END)
FROM ab_flagged
UNION ALL
SELECT 'users who saw both pages (dropped entirely)',
       COUNT_IF(saw_both_pages),
       COUNT(DISTINCT CASE WHEN saw_both_pages THEN user_id END)
FROM ab_flagged
UNION ALL
SELECT 'users with 2+ rows (all causes)',
       COUNT_IF(rows_for_user > 1),
       COUNT(DISTINCT CASE WHEN rows_for_user > 1 THEN user_id END)
FROM ab_flagged
UNION ALL
SELECT 'clean: one row per user', COUNT(*), COUNT(DISTINCT user_id)
FROM ab_clean;

-- @export: ab_mismatch_by_group.csv
-- Is the mismatch bug symmetric? If it hit one group far more, the bug
-- itself could bias the test.
SELECT "GROUP",
       COUNT(*)                                            AS rows_,
       COUNT_IF(is_mismatch)                               AS mismatched_rows,
       ROUND(100.0 * COUNT_IF(is_mismatch) / COUNT(*), 3)  AS mismatch_pct
FROM ab_flagged
GROUP BY "GROUP"
ORDER BY "GROUP";

-- @export: ab_daily_conversion.csv
-- Daily conversion per group: checks for novelty effects (new page spikes
-- early then fades) and for days where one arm broke.
-- Plain English: one row per day; CASE WHEN splits each metric by group.
SELECT
    "TIMESTAMP"::DATE                                                         AS day,
    COUNT_IF("GROUP" = 'control')                                             AS control_users,
    COUNT_IF("GROUP" = 'treatment')                                           AS treatment_users,
    ROUND(100.0 * AVG(CASE WHEN "GROUP" = 'control'   THEN converted::FLOAT END), 3) AS control_cr_pct,
    ROUND(100.0 * AVG(CASE WHEN "GROUP" = 'treatment' THEN converted::FLOAT END), 3) AS treatment_cr_pct
FROM ab_clean
GROUP BY day
ORDER BY day;

-- @export: ab_group_totals.csv
-- SNOWFLAKE: added for verification. In the DuckDB project this query lives inside
-- ab_test.py, which then runs the z-test, confidence intervals and power in Python.
-- Exporting it here lets compare_results.py check those inputs match too.
SELECT 'ab_clean' AS cleaning, "GROUP", COUNT(*) AS n, SUM(converted) AS conv
FROM ab_clean GROUP BY "GROUP"
UNION ALL
SELECT 'ab_clean_alt', "GROUP", COUNT(*), SUM(converted)
FROM ab_clean_alt GROUP BY "GROUP"
ORDER BY cleaning, "GROUP";
