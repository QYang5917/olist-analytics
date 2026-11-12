-- 99_audit_checks.sql
-- Automated integrity checks, re-run on every build. Each row is one test;
-- 'PASS' means the expected value was found. If anything prints FAIL, the
-- analysis numbers should not be trusted until it's fixed.
--
-- Plain English: each CTE row computes one number (e.g. "how many order_ids
-- appear more than once?") next to the value it SHOULD be, then we compare.

-- @export: audit_checks.csv
WITH checks AS (
    SELECT 'orders_clean has one row per order' AS check_name,
           (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM orders_clean)::DOUBLE AS actual, 0::DOUBLE AS expected
    UNION ALL
    SELECT 'deliveries has one row per order',
           (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM deliveries), 0
    UNION ALL
    SELECT 'reviews_dedup has one row per order',
           (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM reviews_dedup), 0
    UNION ALL
    SELECT 'customer_id -> customer join is 1:1',
           (SELECT COUNT(*) - COUNT(DISTINCT customer_id) FROM customers), 0
    UNION ALL
    SELECT 'category revenue reconciles to order revenue (R$ diff)',
           (SELECT ROUND(ABS((SELECT SUM(price) FROM items_with_category)
                           - (SELECT SUM(product_revenue) FROM orders_clean)), 2)), 0
    UNION ALL
    SELECT 'Q1 monthly revenue sums to orders_clean total (R$ diff)',
           (SELECT ROUND(ABS((SELECT SUM(gross_revenue) FROM orders_clean)
                           - (SELECT SUM(m) FROM (SELECT SUM(gross_revenue) m FROM orders_clean GROUP BY order_month))), 2)), 0
    UNION ALL
    SELECT 'no orders outside Jan-2017..Aug-2018 window',
           (SELECT COUNT(*) FROM orders_clean WHERE order_month < DATE '2017-01-01' OR order_month > DATE '2018-08-01'), 0
    UNION ALL
    SELECT 'no canceled/unavailable orders in revenue',
           (SELECT COUNT(*) FROM orders_clean WHERE order_status IN ('canceled', 'unavailable')), 0
    UNION ALL
    SELECT 'no deliveries before purchase',
           (SELECT COUNT(*) FROM deliveries WHERE delivery_days < 0), 0
    UNION ALL
    SELECT 'cohort sizes sum to total customers',
           (SELECT (SELECT COUNT(*) FROM (SELECT customer_unique_id, MIN(order_month) FROM orders_clean GROUP BY 1))
                 - (SELECT COUNT(DISTINCT customer_unique_id) FROM orders_clean)), 0
)
SELECT check_name, actual, expected,
       CASE WHEN actual = expected THEN 'PASS' ELSE 'FAIL' END AS result
FROM checks
