-- ab_01_clean.sql (Snowflake version of sql/ab_01_clean.sql)
-- Dialect changes from the DuckDB version are marked with 'SNOWFLAKE:'.
-- Clean the A/B test data (data/ab_data.csv). Columns:
--   user_id, timestamp, group ('control'|'treatment'),
--   landing_page ('old_page'|'new_page'), converted (0|1)
--
-- Cleaning rules, applied in this order:
--   1. A row is MISMATCHED if group and page disagree (control saw new_page or
--      treatment saw old_page). That's a bucketing/logging bug: we don't know
--      which experience the user was supposed to get.
--   2. A user is CONTAMINATED if they saw BOTH pages across their rows. Their
--      conversion can't be credited to either page -> drop the whole user,
--      not just the bad row (dropping only the bad row would quietly keep
--      people who were exposed to both designs).
--   3. Remaining users with several rows on the same page: keep their FIRST
--      exposure (earliest timestamp). One user = one observation; otherwise
--      the z-test's independence assumption breaks and heavy visitors get
--      extra votes.

-- SNOWFLAKE: the DuckDB version loads data/ab_data.csv here with read_csv().
-- In Snowflake, loading is a separate step: ab_raw is created in 00_load.sql
-- and filled by load_data.py (PUT + COPY INTO), like the Olist tables.
--
-- SNOWFLAKE: "GROUP" and "TIMESTAMP" are written in capitals. GROUP is a reserved
-- word, so it must be quoted, and a quoted name in Snowflake is case-sensitive.
-- Unquoted names are stored in capitals, so capitals keep the two styles consistent.

CREATE OR REPLACE VIEW ab_flagged AS
SELECT
    *,
    ("GROUP" = 'control'   AND landing_page = 'new_page')
 OR ("GROUP" = 'treatment' AND landing_page = 'old_page')                AS is_mismatch,
    COUNT(DISTINCT landing_page) OVER (PARTITION BY user_id) > 1         AS saw_both_pages,
    COUNT(*) OVER (PARTITION BY user_id)                                 AS rows_for_user,
    ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY "TIMESTAMP")        AS exposure_rank
FROM ab_raw;

-- Final analysis table: one row per user.
CREATE OR REPLACE VIEW ab_clean AS
SELECT user_id, "TIMESTAMP", "GROUP", landing_page, converted
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY "TIMESTAMP") AS rn
    FROM ab_flagged
    WHERE NOT saw_both_pages
      AND NOT is_mismatch
)
WHERE rn = 1;

-- Alternative ("textbook") cleaning used only as a sensitivity check:
-- drop mismatched ROWS, then keep each user's first remaining row.
CREATE OR REPLACE VIEW ab_clean_alt AS
SELECT user_id, "TIMESTAMP", "GROUP", landing_page, converted
FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY "TIMESTAMP") AS rn
    FROM ab_flagged
    WHERE NOT is_mismatch
)
WHERE rn = 1;
