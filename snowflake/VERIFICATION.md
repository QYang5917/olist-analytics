# Snowflake vs DuckDB: verification

Written by `snowflake/compare_results.py`. Every cell of every result file is compared.

## Result files

| Result file | DuckDB rows | Snowflake rows | Cells compared | Cells different | Same row order | Result |
|---|---:|---:|---:|---:|---|---|
| `q1_monthly_revenue.csv` | 20 | 20 | 180 | 0 | yes | match |
| `q2_category_revenue.csv` | 74 | 74 | 814 | 0 | yes | match |
| `q3a_repeat_purchase_rate.csv` | 3 | 3 | 18 | 0 | yes | match |
| `q3b_cohort_retention.csv` | 187 | 187 | 935 | 0 | yes | match |
| `q4a_late_vs_ontime.csv` | 2 | 2 | 20 | 0 | yes | match |
| `q4b_score_by_days_late.csv` | 8 | 8 | 32 | 0 | yes | match |
| `q4c_late_gap_by_state.csv` | 21 | 21 | 126 | 0 | no | match |
| `q5_state_delivery_reviews.csv` | 27 | 27 | 297 | 0 | yes | match |
| `audit_checks.csv` | 10 | 10 | 40 | 0 | yes | match |
| `ab_cleaning_log.csv` | 5 | 5 | 15 | 0 | yes | match |
| `ab_mismatch_by_group.csv` | 2 | 2 | 8 | 0 | yes | match |
| `ab_daily_conversion.csv` | 23 | 23 | 115 | 0 | yes | match |

## Headline numbers

| Metric | DuckDB | Snowflake | Result |
|---|---:|---:|---|
| Orders in the analysis window | 97,905 | 97,905 | match |
| Customers | 94,703 | 94,703 | match |
| Total revenue (R$) | 15,683,706.74 | 15,683,706.74 | match |
| Average review, on-time orders | 4.291 | 4.291 | match |
| Average review, late orders | 2.271 | 2.271 | match |
| Customers who buy again within 180 days (%) | 1.99 | 1.99 | match |
| Customers who ever buy again (%) | 2.17 | 2.17 | match |
| Correlation, late rate vs review score | -0.888 | -0.888 | match |
| Correlation, delivery days vs review score | -0.456 | -0.456 | match |
| Audit checks passing | 10 of 10 | 10 of 10 | match |
| A/B control users | 144,267 | 144,267 | match |
| A/B control conversions | 17,349 | 17,349 | match |
| A/B control conversion rate (%) | 12.0256 | 12.0256 | match |
| A/B treatment users | 144,319 | 144,319 | match |
| A/B treatment conversions | 17,131 | 17,131 | match |
| A/B treatment conversion rate (%) | 11.8702 | 11.8702 | match |

## Differences

None. Every cell and every headline number matches.

Where "Same row order" says no, the values are identical and only tied rows are swapped:
`q4c_late_gap_by_state.csv` is sorted by `late_gap`, and MT and SP both round to -1.777.
SQL does not define the order of ties, so each database is free to pick one.
