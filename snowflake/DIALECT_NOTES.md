# DuckDB to Snowflake: what changed and why

Every `.sql` file in `sql/` has a twin in this folder with the same name and the same logic.
Only the syntax that Snowflake does not accept, or reads differently, was changed.
Each change is marked in the SQL with a `SNOWFLAKE:` comment.

## Changes by file

| File | Code lines changed | What changed |
|---|---:|---|
| `00_load.sql` | rewritten | `read_csv()` became typed `CREATE TABLE` + file format + stage + `COPY INTO` |
| `01_staging.sql` | 3 | `DATE_DIFF` → `DATEDIFF` (2), `NULLS LAST` written out (1) |
| `q1_monthly_revenue_trend.sql` | 0 | nothing |
| `q2_category_revenue_growth.sql` | 3 | `FILTER` → `CASE WHEN` (2), `NULLS LAST` (1) |
| `q3_customer_retention.sql` | 9 | `BOOL_OR` → `BOOLOR_AGG`, `INTERVAL` → `DATEADD` (2), `FILTER` → `COUNT_IF` (5), `DATE_DIFF` → `DATEDIFF` (1) |
| `q4_late_delivery_vs_reviews.sql` | 16 | `^2` → `POWER` (2 lines), `FILTER` → `COUNT_IF` / `CASE WHEN` (7), `NULLS LAST` (1), `::FLOAT` inside `AVG` |
| `q5_state_delivery_reviews.sql` | 5 | `NULLS LAST` (2), `::FLOAT` inside `AVG` (3) |
| `99_audit_checks.sql` | 0 | nothing |
| `ab_01_clean.sql` | 7 | CSV load moved to `00_load.sql`; `"group"` / `"timestamp"` → `"GROUP"` / `"TIMESTAMP"` |
| `ab_02_summary.sql` | 16 changed, 7 added | `FILTER` → `COUNT_IF` / `CASE WHEN` (12), quoted names in capitals (4), `::FLOAT` inside `AVG`; one export added for verification |

## The differences, in plain English

### 1. Loading files: `read_csv()` vs stage + `COPY INTO`
- **DuckDB:** `CREATE TABLE orders AS SELECT * FROM read_csv('data/orders.csv', columns = {...})`.
  DuckDB runs on your laptop, so it can open the file directly.
- **Snowflake:** the file has to travel to the cloud first.
  1. `CREATE TABLE` with the column types.
  2. `CREATE FILE FORMAT` describes the CSV (header row, quotes, what counts as NULL).
  3. `PUT` uploads the file to a *stage*, a landing area inside Snowflake.
  4. `COPY INTO` parses the staged file into the table.
- **Why it matters:** in a warehouse, loading is its own step with its own error handling (`ON_ERROR`), not part of a query.

### 2. Data types
- `TIMESTAMP` → `TIMESTAMP_NTZ`. Snowflake has three timestamp types. `NTZ` ("no time zone") is the one that behaves like DuckDB's `TIMESTAMP`.
- `DECIMAL(10,2)` → `NUMBER(10,2)`. Same thing; `NUMBER` is Snowflake's native name.
- `INTEGER`, `BIGINT`, `VARCHAR`, `DOUBLE` are accepted as written. Inside Snowflake, `INTEGER` and `BIGINT` are both `NUMBER(38,0)` and `DOUBLE` is `FLOAT`.

### 3. Date difference: `DATE_DIFF` → `DATEDIFF`
- **DuckDB:** `DATE_DIFF('day', start, end)`. **Snowflake:** `DATEDIFF('day', start, end)`.
- Same argument order and same result. Both count how many day (or month) boundaries are crossed.

### 4. Date arithmetic: `+ INTERVAL 180 DAY` → `DATEADD`
- **DuckDB:** `first_purchase + INTERVAL 180 DAY`. **Snowflake:** `DATEADD('day', 180, first_purchase)`.
- Subtracting uses a negative number: `DATEADD('day', -180, DATE '2018-08-31')`.
- `DATEADD` and `DATEDIFF` are the standard pair in Snowflake (and SQL Server).

### 5. Conditional aggregation: `FILTER (WHERE ...)` → `COUNT_IF` / `CASE WHEN`
- **DuckDB:** `COUNT(*) FILTER (WHERE is_late)` and `SUM(price) FILTER (WHERE ...)`.
- **Snowflake** has no `FILTER` clause, so the condition moves inside the aggregate:
  - counts: `COUNT_IF(is_late)`
  - sums and averages: `SUM(CASE WHEN ... THEN price END)`, `AVG(CASE WHEN is_late THEN review_score END)`
  - distinct counts: `COUNT(DISTINCT CASE WHEN is_mismatch THEN user_id END)`
- **Why it gives the same answer:** a `CASE` with no `ELSE` returns NULL for rows that fail the test, and aggregates skip NULLs.
- The `CASE WHEN` form works in every database, so it is the safest one to write in an interview.

### 6. "True if any row is true": `BOOL_OR` → `BOOLOR_AGG`
- Same function, different name. It returns true if the condition holds for at least one row in the group.

### 7. Powers: `x^2` → `POWER(x, 2)`
- DuckDB reads `^` as "to the power of". Snowflake has no power operator, so it needs the function.

### 8. Sorting NULLs: `DESC` → `DESC NULLS LAST`
- **DuckDB** puts NULLs last whichever way you sort.
- **Snowflake** treats NULL as the largest value, so NULLs come last on `ASC` but **first** on `DESC`.
- This is the dangerous kind of difference: the query runs without error and can quietly give a different answer. In `reviews_dedup`, `ROW_NUMBER() ... ORDER BY review_answer_timestamp DESC` picks the review to keep, so a NULL sorted first would win.
- Writing `NULLS LAST` on every `DESC` makes both databases behave the same.

### 9. Quoted names and capital letters
- Snowflake stores unquoted names in CAPITALS: `order_id` is really `ORDER_ID`.
- A name in double quotes is case-sensitive: `"group"` and `"GROUP"` are two different columns.
- `GROUP` is a reserved word, so that column must be quoted. Writing it as `"GROUP"` keeps it consistent with the other columns.
- Result columns come back in capitals, so `run_snowflake.py` lower-cases the CSV headers to match DuckDB's.

### 10. Averages of whole numbers: `AVG(x)` → `AVG(x::FLOAT)`
- This one was found by testing, not by a syntax error. On the first run, 2,599 of 2,600 cells
  matched DuckDB. One did not: the control conversion rate for 2017-01-20 was 11.506 in DuckDB
  and 11.507 in Snowflake.
- **Cause:** that day had 747 conversions out of 6,492 users, which is 0.1150647...
  - DuckDB's `AVG` of integers returns a full-precision `DOUBLE`: 0.1150647 → 11.50647% → rounds to **11.506**.
  - Snowflake's `AVG` of integers returns `NUMBER(38,6)`, only 6 decimals: 0.115065 → 11.5065% → rounds to **11.507**.
  - Snowflake rounded twice, and the first rounding pushed the value onto a .5 boundary.
- **Fix:** cast to `FLOAT` inside the `AVG`, so Snowflake also averages in floating point.
  I applied it to every `AVG` of whole numbers (review scores, delivery days, 0/1 flags), not
  only the one that showed the difference, because the same thing could happen to any of them.
- **The lesson:** two databases can accept the same SQL and still disagree in the last digit,
  because the *type* a function returns is part of the dialect.

## What did not need changing

Worth knowing, because it shows how much of the SQL is standard:

- CTEs (`WITH ...`), joins, `JOIN ... USING`, `CROSS JOIN`, `UNION ALL`
- Window functions: `LAG`, `RANK`, `ROW_NUMBER`, `SUM(...) OVER`, `CORR(...) OVER ()`, `COUNT(DISTINCT ...) OVER`
- `GROUP BY ROLLUP`, `GROUP BY 1`, grouping by a column alias
- `::DATE` casts, `DATE_TRUNC('month', ...)`, `DATE '2017-01-01'` and `TIMESTAMP '2017-01-01'` literals
- `MEDIAN`, `STDDEV_SAMP`, `NULLIF`, `COALESCE`, `ROUND`
- `CREATE OR REPLACE VIEW`, and true/false expressions used as columns (`a > b AS is_late`)

## How the conversion was checked

`run_snowflake.py` writes every result to `snowflake/output/`, and `compare_results.py`
compares each file with DuckDB's `output/` value by value. The result is in
[VERIFICATION.md](VERIFICATION.md): all 2,600 cells in 12 result files match.

One thing the comparison surfaced that is not a dialect difference: in `q4c_late_gap_by_state.csv`
two states tie on the sort column and come back in a different order. SQL does not define the
order of tied rows; add a second `ORDER BY` column when the order of ties matters.
