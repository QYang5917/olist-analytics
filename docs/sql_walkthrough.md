# SQL Walkthrough: every query in plain English

Use this to rebuild each query from memory in an interview. For each one, the **pattern** is the reusable idea; the **steps** are what the query does.

---

## 01_staging.sql: define the rules once

**Pattern: fix the grain before you join.** Ask "what does one row mean?" for every table:
- `orders`: one row per order.
- `order_items`: one row per item, so many per order.
- `order_reviews`: usually one per order, but 547 orders have more.

Joining a one-row-per-order table to a many-rows-per-order table repeats the order row, and any `SUM` then double-counts.

| View | What it does | Key SQL idea |
|---|---|---|
| `order_totals` | Collapses items to one row per order (item count, revenue) | `GROUP BY order_id` **before** joining |
| `orders_clean` | One row per valid order with the real customer, its state and revenue; drops canceled orders and partial months | `JOIN` + `WHERE` filters; `DATE_TRUNC('month', ts)` gives a month key |
| `reviews_dedup` | Keeps the latest review for each order | `ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY answer_ts DESC)`, then `WHERE rn = 1` |
| `deliveries` | Delivery days and days vs estimate for delivered orders | `DATE_DIFF('day', a::DATE, b::DATE)`; compare **dates**, not timestamps |
| `items_with_category` | Item rows with an English category name | `LEFT JOIN` (keep items with no category) + `COALESCE` fallback |

> **Interview line:** "ROW_NUMBER partitioned by the key and filtered to 1 is my go-to dedup pattern: it keeps exactly one row per key and lets me choose which one through the ORDER BY."

---

## Q1: monthly revenue and month-over-month growth

**Pattern: `LAG()` to compare a row with an earlier row.**

```sql
WITH monthly AS (                       -- step 1: one row per month
    SELECT order_month, COUNT(*) AS orders, SUM(gross_revenue) AS revenue
    FROM orders_clean GROUP BY order_month
),
with_prev AS (                          -- step 2: bring last month onto this row
    SELECT *, LAG(revenue) OVER (ORDER BY order_month) AS prev_revenue
    FROM monthly
)
SELECT order_month, revenue,            -- step 3: growth %
       100.0 * (revenue - prev_revenue) / NULLIF(prev_revenue, 0) AS mom_pct
FROM with_prev;
```

- `LAG(revenue)` means "the revenue value from the previous row", with rows ordered by month. `LAG(revenue, 12)` reaches 12 rows back, which gives year-over-year growth.
- `NULLIF(x, 0)` turns 0 into NULL, so dividing by it returns NULL instead of an error.
- Running total: `SUM(revenue) OVER (ORDER BY order_month)`. A window `SUM` with an `ORDER BY` adds up everything up to the current row.
- **Why aggregate first, then LAG?** Window functions run after `GROUP BY` in the same `SELECT`, but putting them in a separate CTE makes the logic far easier to read and debug.

---

## Q2: top categories, gaining vs losing share

**Patterns: conditional aggregation (a pivot) + `RANK()` + share of total with `SUM() OVER ()`.**

1. **`by_period`**: `SUM(price) FILTER (WHERE order_month BETWEEN '2017-01-01' AND '2017-08-01')` adds up only the 2017 rows inside one `GROUP BY category`. Two filters give two columns, so the pivot is done in one pass. In databases without `FILTER`, write `SUM(CASE WHEN ... THEN price ELSE 0 END)`.
2. **`ranked`**:
   - `RANK() OVER (ORDER BY revenue DESC)` numbers the categories (ties share a rank).
   - `revenue / SUM(revenue) OVER ()` gives the share of total. An empty `OVER ()` means "the whole result set", so every row carries the grand total.
3. **Final**: share change = 2018 share − 2017 share, in percentage points, and `CASE` assigns the label.

> **Why share instead of growth?** The platform grew 138%. A category growing 50% is falling behind the market. Share change removes the overall tide.

`RANK` vs `DENSE_RANK` vs `ROW_NUMBER`, for ties of 100, 100, 90:
- `RANK` → 1, 1, 3
- `DENSE_RANK` → 1, 1, 2
- `ROW_NUMBER` → 1, 2, 3

---

## Q3a: repeat-purchase rate

**Pattern: reduce to one row per customer, then count with `FILTER`.**

1. **`purchase_days`**: `SELECT DISTINCT customer_unique_id, ts::DATE`. Several orders on the same day collapse into one purchase.
2. **`first_purchase`**: `MIN(purchase_date)` per customer.
3. **`per_customer`**: joins the two back together to get, per customer:
   - number of purchase days;
   - `BOOL_OR(date > first AND date <= first + 180 days)`, which is true if any later purchase fell within 180 days;
   - whether we could watch them for 180 days at all (first purchase on or before 2018-03-04).
4. **Final**: `COUNT(*) FILTER (WHERE n_purchase_days >= 2) / COUNT(*)`. `GROUP BY ROLLUP (year)` adds an "all years" total row automatically; the subtotal row has `year = NULL`, which is why `COALESCE(..., 'all')` is there.

## Q3b: cohort retention

**Pattern: cohort = first event; then measure time since the cohort.** Memorize this one; it comes up constantly.

```sql
WITH first_month AS (      -- 1. each customer's cohort
    SELECT customer_unique_id, MIN(order_month) AS cohort_month
    FROM orders_clean GROUP BY 1
),
activity AS (              -- 2. every month each customer was active, as "months since cohort"
    SELECT DISTINCT o.customer_unique_id, f.cohort_month,
           DATE_DIFF('month', f.cohort_month, o.order_month) AS month_number
    FROM orders_clean o JOIN first_month f USING (customer_unique_id)
),
cohort_size AS (           -- 3. the denominator
    SELECT cohort_month, COUNT(*) AS cohort_customers FROM first_month GROUP BY 1
)
SELECT a.cohort_month, a.month_number,     -- 4. % of the cohort active
       100.0 * COUNT(*) / s.cohort_customers AS retention_pct
FROM activity a JOIN cohort_size s USING (cohort_month)
WHERE month_number >= 1
GROUP BY a.cohort_month, a.month_number, s.cohort_customers;
```

- `DISTINCT` in `activity` matters: a customer with 3 orders in the same month counts once.
- The output is in **long format** (one row per cohort × month). Tableau pivots it into the triangle heatmap.
- Months we can't observe yet simply have no row. They are not 0%.

---

## Q4: late delivery vs review score

**Patterns: grouped stats + a `CROSS JOIN` to put the comparison group on every row + a CI computed in SQL.**

1. **`joined`**: delivered orders joined to the deduplicated reviews (both one row per order, so the join can't duplicate rows).
2. **`grp`**: one row each for late and on-time, with mean, standard deviation, % 1–2 star and % 5 star. `AVG(CASE WHEN score <= 2 THEN 1 ELSE 0 END)` is a quick way to get a percentage: the average of a 0/1 flag equals the share of 1s.
3. **Final**:
   - `CROSS JOIN (SELECT * FROM grp WHERE status = 'on_time') o` attaches the on-time numbers to every row, so the late row can subtract them.
   - 95% confidence interval for the difference in means: `diff ± 1.96 * SQRT(s1²/n1 + s2²/n2)`.
- **q4b**: `CASE` buckets on days vs estimate, giving the dose-response curve.
- **q4c**: the same comparison done within each state, using `AVG(score) FILTER (WHERE is_late)`; `HAVING` keeps states with 30+ late orders.

---

## Q5: states, delivery time vs reviews

**Patterns: two `RANK()`s on different metrics + `MEDIAN` vs `AVG` + `CORR() OVER ()`.**

1. **`state_stats`**: per state, average and median delivery days, late rate and average review. `LEFT JOIN` to reviews, because an order without a review still has a delivery time. `COUNT(r.review_score)` counts only non-NULL values, so it gives the number of reviewed orders.
2. **Final**:
   - `RANK() OVER (ORDER BY avg_delivery_days DESC)` and `RANK() OVER (ORDER BY avg_review_score ASC)` put two leaderboards side by side.
   - `CORR(x, y) OVER ()` computes a single correlation across all states and repeats it on every row.
   - `small_sample_flag` warns about states with fewer than 300 orders.

---

## 99_audit_checks.sql

**Pattern: assertions as a query.** Each `UNION ALL` row computes one number that should be 0, such as `COUNT(*) - COUNT(DISTINCT order_id)` (0 means no duplicates), and the final `CASE` prints PASS or FAIL. This is cheap to write and catches regressions every time the data is rebuilt.

---

## Quick reference

| Need | Use |
|---|---|
| Previous / next row | `LAG(x) OVER (ORDER BY t)`, `LEAD(...)` |
| Running total | `SUM(x) OVER (ORDER BY t)` |
| Share of total | `x / SUM(x) OVER ()` |
| Share within a group | `x / SUM(x) OVER (PARTITION BY g)` |
| Top N per group | `ROW_NUMBER() OVER (PARTITION BY g ORDER BY x DESC)`, then `WHERE rn <= N` |
| Deduplicate | `ROW_NUMBER() ... WHERE rn = 1` |
| Pivot | `SUM(x) FILTER (WHERE cond)` or `SUM(CASE WHEN cond THEN x END)` |
| Percent of rows matching | `AVG(CASE WHEN cond THEN 1 ELSE 0 END)` |
| Subtotals | `GROUP BY ROLLUP (a)` |
| Safe division | `x / NULLIF(y, 0)` |
