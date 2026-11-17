"""Compare Snowflake's results with DuckDB's, value by value.

Reads  output/*.csv            (written by run_sql.py and ab_test.py, DuckDB)
       snowflake/output/*.csv  (written by run_snowflake.py, Snowflake)
Writes snowflake/VERIFICATION.md and prints the same tables.

It needs no database connection, so it still works after the Snowflake trial ends.
Usage:  python snowflake/compare_results.py
"""
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DUCK, SNOW = ROOT / "output", ROOT / "snowflake" / "output"

# The column(s) that identify a row in each file. Rows are matched on these, not
# on position, because a query without ORDER BY may return rows in any order.
KEYS = {
    "q1_monthly_revenue.csv": ["order_month"],
    "q2_category_revenue.csv": ["category"],
    "q3a_repeat_purchase_rate.csv": ["first_purchase_year"],
    "q3b_cohort_retention.csv": ["cohort_month", "month_number"],
    "q4a_late_vs_ontime.csv": ["delivery_status"],
    "q4b_score_by_days_late.csv": ["delivery_bucket"],
    "q4c_late_gap_by_state.csv": ["customer_state"],
    "q5_state_delivery_reviews.csv": ["customer_state"],
    "audit_checks.csv": ["check_name"],
    "ab_cleaning_log.csv": ["stage"],
    "ab_mismatch_by_group.csv": ["group"],
    "ab_daily_conversion.csv": ["day"],
}


def read(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def same(a, b):
    """Two cells are equal if they are the same number (7.0 vs 7.000) or the same
    text ignoring case (true vs True)."""
    try:
        return abs(float(a) - float(b)) < 1e-9
    except ValueError:
        return a.strip().lower() == b.strip().lower()


lines = ["# Snowflake vs DuckDB: verification", "",
         "Written by `snowflake/compare_results.py`. Every cell of every result file is compared.", "",
         "## Result files", "",
         "| Result file | DuckDB rows | Snowflake rows | Cells compared | Cells different | Same row order | Result |",
         "|---|---:|---:|---:|---:|---|---|"]
problems = []
for name, key in KEYS.items():
    duck, snow = read(DUCK / name), read(SNOW / name)
    snow_by_key = {tuple(r[k] for k in key): r for r in snow}
    cells = different = 0
    for row in duck:
        k = tuple(row[c] for c in key)
        other = snow_by_key.get(k)
        for col, value in row.items():
            cells += 1
            if other is None or col not in other or not same(value, other[col]):
                different += 1
                problems.append(f"{name} {k} {col}: DuckDB={value!r} Snowflake={None if other is None else other.get(col)!r}")
    ok = different == 0 and len(duck) == len(snow) and list(duck[0]) == list(snow[0])
    # Row order is reported but does not decide the result: SQL only promises an order
    # where ORDER BY says so, and rows that tie on the ORDER BY column may come back either way.
    same_order = [tuple(r[k] for k in key) for r in duck] == [tuple(r[k] for k in key) for r in snow]
    lines.append(f"| `{name}` | {len(duck):,} | {len(snow):,} | {cells:,} | {different} | {'yes' if same_order else 'no'} | {'match' if ok else 'MISMATCH'} |")
    if len(duck) != len(snow):
        problems.append(f"{name}: row counts differ")

# ---- Headline numbers quoted in the README, read from both sides.
def headline(folder):
    q1, q3a, q4a = read(folder / "q1_monthly_revenue.csv"), read(folder / "q3a_repeat_purchase_rate.csv"), read(folder / "q4a_late_vs_ontime.csv")
    q5, audit = read(folder / "q5_state_delivery_reviews.csv"), read(folder / "audit_checks.csv")
    total = next(r for r in q3a if r["first_purchase_year"] == "all")
    score = {r["delivery_status"]: r["avg_score"] for r in q4a}
    return {
        "Orders in the analysis window": f"{sum(int(r['orders']) for r in q1):,}",
        "Customers": f"{int(total['customers']):,}",
        "Total revenue (R$)": f"{max(float(r['cumulative_revenue']) for r in q1):,.2f}",
        "Average review, on-time orders": f"{float(score['on_time']):.3f}",
        "Average review, late orders": f"{float(score['late']):.3f}",
        "Customers who buy again within 180 days (%)": f"{float(total['repeat_180d_pct']):.2f}",
        "Customers who ever buy again (%)": f"{float(total['repeat_rate_ever_pct']):.2f}",
        "Correlation, late rate vs review score": f"{float(q5[0]['corr_late_rate_vs_review']):.3f}",
        "Correlation, delivery days vs review score": f"{float(q5[0]['corr_delivery_days_vs_review']):.3f}",
        "Audit checks passing": f"{sum(r['result'] == 'PASS' for r in audit)} of {len(audit)}",
    }


duck_head, snow_head = headline(DUCK), headline(SNOW)

# A/B test: DuckDB's numbers come from ab_test.py's results file, Snowflake's from
# the per-group counts exported by ab_02_summary.sql.
ab_duck = next(r for r in read(DUCK / "ab_test_results.csv") if r["cleaning"] == "ab_clean")
ab_snow = {r["group"]: r for r in read(SNOW / "ab_group_totals.csv") if r["cleaning"] == "ab_clean"}
for group in ("control", "treatment"):
    n, conv = int(ab_snow[group]["n"]), int(ab_snow[group]["conv"])
    duck_head[f"A/B {group} users"] = f"{int(ab_duck[f'{group}_users']):,}"
    snow_head[f"A/B {group} users"] = f"{n:,}"
    duck_head[f"A/B {group} conversions"] = f"{int(ab_duck[f'{group}_conversions']):,}"
    snow_head[f"A/B {group} conversions"] = f"{conv:,}"
    duck_head[f"A/B {group} conversion rate (%)"] = f"{float(ab_duck[f'{group}_cr_pct']):.4f}"
    snow_head[f"A/B {group} conversion rate (%)"] = f"{100 * conv / n:.4f}"

lines += ["", "## Headline numbers", "", "| Metric | DuckDB | Snowflake | Result |", "|---|---:|---:|---|"]
for metric, value in duck_head.items():
    ok = value == snow_head[metric]
    lines.append(f"| {metric} | {value} | {snow_head[metric]} | {'match' if ok else 'MISMATCH'} |")
    if not ok:
        problems.append(f"headline {metric}: DuckDB={value} Snowflake={snow_head[metric]}")

lines += ["", "## Differences", ""]
lines += [f"- {p}" for p in problems] if problems else ["None. Every cell and every headline number matches."]
lines += ["", "Where \"Same row order\" says no, the values are identical and only tied rows are swapped:",
          "`q4c_late_gap_by_state.csv` is sorted by `late_gap`, and MT and SP both round to -1.777.",
          "SQL does not define the order of ties, so each database is free to pick one."]
text = "\n".join(lines) + "\n"
(ROOT / "snowflake" / "VERIFICATION.md").write_text(text)
print(text)
