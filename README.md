# Olist E-Commerce Analytics + A/B Test

A SQL-first analysis of ~100k orders from Olist, a Brazilian online marketplace, plus a landing-page A/B test. All business logic is written in DuckDB SQL (see [`sql/`](sql/)), so every number in this README can be traced back to a query.

**Live dashboard:** [Landing Page A/B Test on Tableau Public](https://public.tableau.com/app/profile/qingyao.yang/viz/LandingPageABTest_17948802889870/ABtestdashboard)

**Skills shown:** CTEs, joins at the right grain, window functions (`LAG`, `RANK`, `ROW_NUMBER`, running totals, `CORR() OVER`), cohort analysis, hypothesis testing, power analysis, and a documented data-quality audit.

---

## Business questions and key findings

Analysis window: **Jan 2017 – Aug 2018** (97,905 orders, 94,703 customers, R$15.7M revenue). The 2016 months and Sep/Oct 2018 are partial exports and were excluded.

### 1. How fast is the business growing? ([q1](sql/q1_monthly_revenue_trend.sql))
- Revenue for Jan–Aug 2018 was **R$8.59M, up 140% from R$3.57M** in Jan–Aug 2017. Orders rose 137% (22.6k → 53.5k).
- **Growth stalled in 2018.** Monthly revenue stayed flat at R$0.98–1.16M from January to August, swinging between −11% and +18% month to month after January.
- **Black Friday (Nov 2017) was the peak month**, at R$1.17M (+53% over October).
- Average order value is steady at about R$160. Growth came from more orders, not bigger baskets.

### 2. Which categories matter, and which are winning? ([q2](sql/q2_category_revenue_growth.sql))
- Top 3 by revenue: **health_beauty (R$1.25M), watches_gifts (R$1.19M), bed_bath_table (R$1.04M)**.
- Because the whole platform grew 138%, raw growth % is misleading: almost every category "grew". I classify categories by **change in revenue share** instead.
  - **Gaining share:** watches_gifts (+2.95 pp), health_beauty (+2.46 pp), baby (+1.21 pp), housewares (+1.16 pp).
  - **Losing share:** cool_stuff (−3.74 pp; it grew only 9% while the market grew 138%), garden_tools (−1.74 pp), perfumery (−1.60 pp), toys (−1.57 pp).

### 3. Do customers come back? ([q3](sql/q3_customer_retention.sql))
- **Only 2.2% of customers ever make a second purchase.** On a fair, fixed window, **2.0% return within 180 days**.
- Cohort retention is about **0.5% in month 1 and 0.25% by month 3**, and it is similar across every cohort.
- **Implication:** Olist is effectively a one-purchase business. All growth is new-customer acquisition, so retention (email, loyalty programs, re-order prompts) is a large untapped lever.

### 4. Does late delivery hurt reviews? ([q4](sql/q4_late_delivery_vs_reviews.sql))
- **Yes, dramatically.** Late orders average **2.27 stars vs 4.29** for on-time orders, a gap of −2.02 stars (95% CI −2.06 to −1.98).
- **62% of late orders get a 1–2 star review, vs 9% of on-time orders.** The 6.7% of orders that arrive late produce **a third (32.6%) of all 1–2 star reviews**.
- **The damage starts immediately and grows with delay:** 3.29 stars at 1–3 days late, 2.10 at 4–7 days, 1.67 at 8–14 days.
- **It isn't just geography.** Within every state with enough late orders (21 states), late deliveries score 1.6–2.6 stars lower.

### 5. Where is delivery worst? ([q5](sql/q5_state_delivery_reviews.sql))
- **Slowest states** (with 300+ orders): **AL 24.5 days, PA 23.7, MA 21.5, SE 21.4, CE 21.2** (North/Northeast), vs **SP 8.7 days**.
- **Worst reviews** (300+ orders): MA (3.83), AL (3.85), SE (3.90), PA (3.91), BA (3.93).
- **The key insight: customers punish broken promises, not distance.** Across states, the late rate correlates **−0.89** with review score, while raw delivery days correlate only **−0.46**. The Amazon-region states AM and AP are among the slowest yet review well, because their delivery estimates are honest (only about 3% late).
- **Recommendation:** set realistic delivery estimates in the Northeast before investing in faster logistics.

---

## A/B test: should we launch the new landing page? ([ab_test.py](ab_test.py))

**Recommendation: don't launch.** The new page converted at **11.87% vs 12.03%** for the old page: −0.16 points (−1.3% relative), p = 0.20 (two-proportion z-test, 288,586 users).

The 95% confidence interval for the difference is **−0.39 to +0.08 points**, so even the best plausible case is a gain of about 0.7%, which isn't worth a rollout. The test could detect a 2.8% relative lift at 80% power. The split passed a sample-ratio check (p = 0.92), there was no novelty spike, and the result held under an alternative cleaning rule. Full report: [docs/ab_test_report.md](docs/ab_test_report.md). Interactive version: [Tableau Public dashboard](https://public.tableau.com/app/profile/qingyao.yang/viz/LandingPageABTest_17948802889870/ABtestdashboard), with the lift, conversion rates and daily trend by country, weekday/weekend and test week.

Method:
1. **Cleaning** ([sql/ab_01_clean.sql](sql/ab_01_clean.sql)):
   - Rows where the group and the page don't match (e.g. control users shown the new page) indicate a bucketing bug, so they are removed.
   - Users who saw both pages are removed entirely, because their conversion can't be credited to either page.
   - Remaining duplicate users keep only their first exposure, so each user counts once.
2. **Sanity checks:**
   - Sample-ratio-mismatch test (was the split really 50/50?).
   - Whether the mismatch bug hit one group more than the other.
   - Daily conversion by group, to spot novelty effects.
3. **Statistics:**
   - Two-proportion z-test (two-sided, plus one-sided "is new better?").
   - Wilson confidence intervals for each conversion rate, and a Wald confidence interval for the difference.
   - Minimum detectable effect at 80% power, and the sample size needed to detect a +2% relative lift.
4. **Robustness:** the whole test is re-run with the simpler "drop bad rows only" cleaning rule to confirm the conclusion doesn't depend on that choice.

---

## Data quality: what I checked and fixed

Full audit in [docs/data_quality_audit.md](docs/data_quality_audit.md). Highlights:

- **Wrong customer key.** `customer_id` is regenerated for every order, so retention measured on it would be 0%. I used `customer_unique_id` instead.
- **Inflated repeat purchases.** One checkout with several sellers creates several orders at the same moment. Counting those as repeats would have inflated the repeat rate by about 40%, so only purchases on different days count.
- **Inflated late deliveries.** The estimated date is stored as midnight, so a timestamp comparison flags on-time deliveries as late. Comparing dates instead removed 1,292 false "late" orders.
- **Double counting in joins.** Reviews (547 orders with 2+ reviews) were deduplicated, and items were aggregated before joining. [`sql/99_audit_checks.sql`](sql/99_audit_checks.sql) re-checks every view's grain and reconciles revenue on each build: 10/10 checks pass.

---

## How to run

```bash
pip install -r requirements.txt
# Download the data from Kaggle into data/ (see below), then:
python run_sql.py     # builds olist.duckdb, runs all SQL, writes output/*.csv
python ab_test.py     # A/B test (needs data/ab_data.csv)
```

**Data**
- [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce): put the 9 CSVs in `data/`.
- `ab_data.csv` from the Udacity "Analyze A/B Test Results" project (294,478 rows; columns `user_id, timestamp, group, landing_page, converted`; SHA-256 `d56e2acc…301beb`), e.g. from [this public copy](https://github.com/vonOrso/AB_test_results). Put it in `data/`.

**Output** (one tidy CSV per question, ready for Tableau): `output/q1_monthly_revenue.csv`, `q2_category_revenue.csv`, `q3a_repeat_purchase_rate.csv`, `q3b_cohort_retention.csv` (long format; pivot `month_number` in Tableau for a cohort heatmap), `q4a_late_vs_ontime.csv`, `q4b_score_by_days_late.csv`, `q4c_late_gap_by_state.csv`, `q5_state_delivery_reviews.csv`, `audit_checks.csv`, and `ab_*.csv`.

## Repository layout

```
sql/00_load.sql           raw CSV -> typed DuckDB tables
sql/01_staging.sql        clean views; every business rule defined once
sql/q1..q5_*.sql          one file per business question
sql/99_audit_checks.sql   automated grain/reconciliation tests
sql/ab_01_clean.sql       A/B data cleaning
sql/ab_02_summary.sql     A/B descriptive tables
ab_test.py                z-test, confidence intervals, power
run_sql.py                runs the SQL and exports CSVs (no analysis logic)
docs/                     audit, A/B report, SQL walkthrough, interview prep
tableau/                  A/B dashboard data: prep script, CSVs, Tableau build guide
```
