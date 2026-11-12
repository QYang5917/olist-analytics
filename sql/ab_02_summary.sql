-- ab_02_summary.sql
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
       COUNT(*) FILTER (WHERE is_mismatch),
       COUNT(DISTINCT user_id) FILTER (WHERE is_mismatch)
FROM ab_flagged
UNION ALL
SELECT 'users who saw both pages (dropped entirely)',
       COUNT(*) FILTER (WHERE saw_both_pages),
       COUNT(DISTINCT user_id) FILTER (WHERE saw_both_pages)
FROM ab_flagged
UNION ALL
SELECT 'users with 2+ rows (all causes)',
       COUNT(*) FILTER (WHERE rows_for_user > 1),
       COUNT(DISTINCT user_id) FILTER (WHERE rows_for_user > 1)
FROM ab_flagged
UNION ALL
SELECT 'clean: one row per user', COUNT(*), COUNT(DISTINCT user_id)
FROM ab_clean;

-- @export: ab_mismatch_by_group.csv
-- Is the mismatch bug symmetric? If it hit one group far more, the bug
-- itself could bias the test.
SELECT "group",
       COUNT(*)                                            AS rows_,
       COUNT(*) FILTER (WHERE is_mismatch)                 AS mismatched_rows,
       ROUND(100.0 * COUNT(*) FILTER (WHERE is_mismatch) / COUNT(*), 3) AS mismatch_pct
FROM ab_flagged
GROUP BY "group"
ORDER BY "group";

-- @export: ab_daily_conversion.csv
-- Daily conversion per group: checks for novelty effects (new page spikes
-- early then fades) and for days where one arm broke.
-- Plain English: one row per day; FILTER splits each metric by group.
SELECT
    "timestamp"::DATE                                                         AS day,
    COUNT(*) FILTER (WHERE "group" = 'control')                               AS control_users,
    COUNT(*) FILTER (WHERE "group" = 'treatment')                             AS treatment_users,
    ROUND(100.0 * AVG(converted) FILTER (WHERE "group" = 'control'), 3)       AS control_cr_pct,
    ROUND(100.0 * AVG(converted) FILTER (WHERE "group" = 'treatment'), 3)     AS treatment_cr_pct
FROM ab_clean
GROUP BY day
ORDER BY day;
