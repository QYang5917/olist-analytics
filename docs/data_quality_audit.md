# Data Quality Audit (Part 3)

I reviewed the work as a skeptical senior analyst would, looking for three kinds of problems: joins that duplicate rows, wrong date handling, and metrics that are technically correct but misleading. Each item below lists what I checked, what I found, and what changed.

## A. Problems caught during profiling (built into `sql/01_staging.sql`)

| # | Issue | Evidence | Fix | Impact if ignored |
|---|---|---|---|---|
| 1 | `customer_id` is not a customer | 99,441 `customer_id`s but only 96,096 `customer_unique_id`s; every `customer_id` has exactly 1 order | Use `customer_unique_id` for anything customer-level | The repeat-purchase rate would be **0%** |
| 2 | One checkout is split into several orders | 2,888 people have 2+ orders, but only 2,065 bought on 2+ different days | A "purchase" = a distinct purchase **day** | Repeat rate inflated by **~40%** |
| 3 | Estimated delivery date is stored as midnight | Timestamp comparison: 7,826 late orders. Date comparison: 6,534 | Compare `::DATE` to `::DATE` | **1,292 on-time orders labelled late** (+20%) |
| 4 | Multiple reviews per order | 547 orders have 2+ reviews | `ROW_NUMBER()` keeps the latest review per order | Those orders counted twice in review averages |
| 5 | Items and payments are both many-rows-per-order | Joining raw items to payments multiplies rows | Aggregate items to one row per order (`order_totals`) **before** any join; payments not joined at all | Revenue double- or triple-counted for split-payment orders |
| 6 | Truncated months at both ends | 2016 has 329 orders (zero in Nov 2016); Sep and Oct 2018 have 16 and 4 | Window = Jan 2017 to Aug 2018 | Sep 2018 would show a fake **−99.8%** month-over-month "collapse" |
| 7 | Canceled / unavailable orders | 1,234 orders | Excluded from revenue | Revenue counted that never happened |
| 8 | Delivery-status inconsistencies | 8 delivered orders with no delivery date; 6 non-delivered orders with one | Delivery metrics require status = delivered **and** a date | Small, but a source of NULL math errors |
| 9 | Missing categories | 623 products with no category; 2 categories missing from the translation file | `COALESCE` to the Portuguese name, then `'unknown'` | Those rows silently dropped by an inner join to the translation table |

**Revenue definition:** item price + freight from `order_items` (R$15.84M across all orders) rather than `order_payments` (R$15.85M). The 0.02% gap is mainly installment interest and vouchers. Items are the only source that can be split by product category, so every question uses the same number.

## B. Problems found by auditing the first version of the results

| # | Query | What was misleading | Change | Before → after |
|---|---|---|---|---|
| 10 | Q2 categories | Labels were based on raw year-over-year growth while the platform itself grew 138%, so nearly every category looked like it was "growing fast" | Label by **change in revenue share** (percentage points); raw growth kept as a column, platform growth shown for context | Top 15: 11 "growing fast (2x+)" → 6 gaining share, 8 losing, 1 stable. cool_stuff went from "growing" (+9%) to the **biggest share loser** (−3.74 pp) |
| 11 | Q3 repeat rate | "Ever repeated" gives a customer from Jan 2017 20 months to return and a customer from Aug 2018 a few days, so later customers look worse | Added `repeat_180d_pct`, counting only customers observable for a full 180 days | All customers: 2.17% → **1.99%** (fair). 2018 customers: 1.38% → 1.84%. The apparent decline was mostly censoring |
| 12 | Q4 late vs on-time | The on-time row showed a "difference vs on-time" of 0 with a confidence interval, which is meaningless | Set to NULL on the reference row | Cosmetic, but it would confuse a dashboard reader |
| 13 | Q4 causality | Late orders could cluster in regions that review harshly anyway | Added `q4c_late_gap_by_state`: late vs on-time **within** each state | The gap holds in all 21 states (−1.6 to −2.6 stars), so geography doesn't explain it |
| 14 | Q4 interpretation | Checked when reviews were written | Added `pct_reviewed_before_arrival` | **74.5% of late orders were reviewed before the package arrived** (Olist surveys on the estimated date). The score measures "you missed your promise", not product quality |
| 15 | Q5 states | Ranking by delivery days alone suggests "faster shipping = better reviews" | Added the correlation between late rate and review score | Late rate vs review: **−0.89**; delivery days vs review: −0.46. Slow-but-honest states (AM, AP) review well |
| 16 | Q1 year-over-year | Jan 2018 shows +705% YoY | Comment added: Jan 2017 was the platform's ramp-up month | Use late-2018 YoY (+50–100%) as the honest growth read |

## C. Automated checks (`sql/99_audit_checks.sql`, runs on every build)

All 10 pass (`output/audit_checks.csv`):
- One row per order in `orders_clean`, `deliveries` and `reviews_dedup`; `customer_id` joins 1:1.
- Category revenue reconciles to order revenue to the cent (R$13,449,529.68 both ways).
- Monthly revenue sums back to the total.
- No orders outside the window, no canceled orders in revenue, no negative delivery times.
- Cohort sizes sum to the number of distinct customers.

## D. Known limitations (not fixed, stated openly)

- **Calendar-month cohorts:** a purchase on Jan 31 followed by one on Feb 1 counts as "month 1 retention". This is standard, but it slightly overstates month-1 retention.
- **Left censoring:** 10 customers first bought in 2016 and again in the window; they're treated as new in 2017. Negligible.
- **Q4 is observational.** The within-state check and the dose-response pattern make a strong case, but seller and category effects aren't controlled. A regression with seller fixed effects would be the next step.
- **Retention covers at most 19 months of observation.** Long-run lifetime value can't be estimated.
