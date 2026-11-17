"""Prepare Tableau-ready CSVs for the landing-page A/B test.

Reads   data/ab_data.csv        (user_id, timestamp, group, landing_page, converted)
        data/countries.csv      (user_id, country) - optional, adds a Country segment
Writes  tableau/funnel.csv
        tableau/conversion_by_segment.csv
        tableau/daily_conversion.csv
        tableau/lift_by_segment.csv

Every output file has the same two columns, segment_type and segment, so one
Tableau filter can drive every chart. Each segment type splits ALL users into
non-overlapping groups, so the segments of one type always add up to the total.

There is no cohort_retention.csv: the data has one landing-page visit per user
and no signup date, so retention cannot be measured.

Usage:  python tableau/make_tableau_data.py
"""
from math import erfc  # standard library; used for the z-test p-value
from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parent.parent
DATA, OUT = ROOT / "data", ROOT / "tableau"
Z = 1.959964  # z-score for a 95% confidence interval


# ---------------------------------------------------------------------------
# 1. Load and clean (same three rules as sql/ab_01_clean.sql)
# ---------------------------------------------------------------------------
raw = pd.read_csv(DATA / "ab_data.csv", parse_dates=["timestamp"])

# Rule 1: a row is a mismatch when the group and the page disagree.
expected_page = raw["group"].map({"control": "old_page", "treatment": "new_page"})
raw["is_mismatch"] = raw["landing_page"] != expected_page

# Rule 2: users who saw BOTH pages are dropped entirely, because their
# conversion can't be credited to either page.
pages_seen = raw.groupby("user_id")["landing_page"].transform("nunique")
raw["saw_both_pages"] = pages_seen > 1

# Rule 3: of what's left, keep each user's first visit (one row per user).
clean = (
    raw[~raw["saw_both_pages"] & ~raw["is_mismatch"]]
    .sort_values("timestamp")
    .drop_duplicates("user_id", keep="first")
    .rename(columns={"group": "test_group"})
)


# ---------------------------------------------------------------------------
# 2. Add segment columns
# ---------------------------------------------------------------------------
clean["date"] = clean["timestamp"].dt.date

# Test week: the test started on Monday 2 Jan 2017, so week 1 = Jan 2-8, etc.
days_in = (clean["timestamp"].dt.normalize() - pd.Timestamp("2017-01-02")).dt.days
clean["test_week"] = (days_in // 7).map({
    0: "Week 1 (Jan 2-8)",
    1: "Week 2 (Jan 9-15)",
    2: "Week 3 (Jan 16-22)",
    3: "Week 4 (Jan 23-24)",
})

# Weekday vs weekend (dayofweek: Monday = 0 ... Sunday = 6).
is_weekend = clean["timestamp"].dt.dayofweek >= 5
clean["day_type"] = is_weekend.map({True: "Weekend", False: "Weekday"})

clean["all"] = "All"

# segment_type label -> column in `clean` that holds the segment value
segment_columns = {"All": "all", "Test week": "test_week", "Day type": "day_type"}

# Country comes from a second file. It is optional so the script still runs
# without it.
if (DATA / "countries.csv").exists():
    countries = pd.read_csv(DATA / "countries.csv")
    clean = clean.merge(countries, on="user_id", how="left", validate="one_to_one")
    clean["country"] = clean["country"].fillna("Unknown")
    segment_columns["Country"] = "country"
else:
    print("data/countries.csv not found -> skipping the Country segment")

# Stack one copy of the data per segment type. After this, every output file
# is just a groupby on this one long table.
long = pd.concat(
    [
        clean[["user_id", "test_group", "date", "converted"]].assign(
            segment_type=segment_type, segment=clean[column]
        )
        for segment_type, column in segment_columns.items()
    ],
    ignore_index=True,
)


# ---------------------------------------------------------------------------
# 3. conversion_by_segment.csv: one row per segment and test group
# ---------------------------------------------------------------------------
def wilson_interval(conversions, users):
    """95% Wilson confidence interval for a conversion rate.

    Better than the simple p +/- 1.96*SE formula because it never goes below 0
    or above 1 and stays accurate for small segments.
    """
    p = conversions / users
    denominator = 1 + Z**2 / users
    centre = (p + Z**2 / (2 * users)) / denominator
    half_width = Z * (p * (1 - p) / users + Z**2 / (4 * users**2)) ** 0.5 / denominator
    return centre - half_width, centre + half_width


by_segment = (
    long.groupby(["segment_type", "segment", "test_group"], as_index=False)
    .agg(users=("user_id", "count"), conversions=("converted", "sum"))
)
by_segment["conversion_rate"] = by_segment["conversions"] / by_segment["users"]
by_segment["ci_lower"], by_segment["ci_upper"] = wilson_interval(
    by_segment["conversions"], by_segment["users"]
)


# ---------------------------------------------------------------------------
# 4. funnel.csv: one row per segment, test group and funnel step
#    The data only records two steps: seeing the page and converting.
# ---------------------------------------------------------------------------
keys = ["segment_type", "segment", "test_group"]
visited = by_segment[keys + ["users"]].assign(step_order=1, step_name="Visited landing page")
converted = (
    by_segment[keys + ["conversions"]]
    .rename(columns={"conversions": "users"})
    .assign(step_order=2, step_name="Converted")
)
funnel = pd.concat([visited, converted], ignore_index=True)

# pct_of_group = this step's users / step-1 users of the same segment and group
step1_users = funnel.groupby(keys)["users"].transform("max")
funnel["pct_of_group"] = funnel["users"] / step1_users
funnel = funnel[keys + ["step_order", "step_name", "users", "pct_of_group"]].sort_values(
    keys + ["step_order"]
)


# ---------------------------------------------------------------------------
# 5. daily_conversion.csv: one row per segment, test group and day
# ---------------------------------------------------------------------------
daily = (
    long.groupby(["segment_type", "segment", "test_group", "date"], as_index=False)
    .agg(users=("user_id", "count"), conversions=("converted", "sum"))
)
daily["conversion_rate"] = daily["conversions"] / daily["users"]


# ---------------------------------------------------------------------------
# 6. lift_by_segment.csv: one row per segment, treatment compared to control
# ---------------------------------------------------------------------------
# Put control and treatment side by side, so each segment is one row.
wide = by_segment.pivot(
    index=["segment_type", "segment"], columns="test_group", values=["users", "conversions"]
)
n_control, n_treatment = wide["users"]["control"], wide["users"]["treatment"]
x_control, x_treatment = wide["conversions"]["control"], wide["conversions"]["treatment"]
rate_control, rate_treatment = x_control / n_control, x_treatment / n_treatment
diff = rate_treatment - rate_control

# 95% Wald interval for the difference. Each group keeps its own rate in the
# standard error (unpooled), because we are estimating the size of the gap.
se_diff = (
    rate_control * (1 - rate_control) / n_control
    + rate_treatment * (1 - rate_treatment) / n_treatment
) ** 0.5

# Two-proportion z-test. The null hypothesis says both groups share ONE rate,
# so the standard error uses the pooled rate.
rate_pooled = (x_control + x_treatment) / (n_control + n_treatment)
se_pooled = (rate_pooled * (1 - rate_pooled) * (1 / n_control + 1 / n_treatment)) ** 0.5
z_stat = diff / se_pooled

# Two-sided p-value = chance of a z at least this far from 0 = erfc(|z| / sqrt(2)).
p_value = (z_stat.abs() / 2**0.5).map(erfc)

# Rates stay as fractions (0-1); the difference and its interval are in
# percentage points (treatment minus control).
lift = pd.DataFrame({
    "control_rate": rate_control,
    "treatment_rate": rate_treatment,
    "diff_pp": 100 * diff,
    "diff_ci_lower": 100 * (diff - Z * se_diff),
    "diff_ci_upper": 100 * (diff + Z * se_diff),
    "p_value": p_value,
}).reset_index()


# ---------------------------------------------------------------------------
# 7. Checks: stop with an error if any number doesn't add up
# ---------------------------------------------------------------------------
def check(name, passed):
    print(f"  {'PASS' if passed else 'FAIL'}  {name}")
    assert passed, name


print("Checks")

# 7a. Cleaning reconciles with the raw data.
raw_users = raw["user_id"].nunique()
both_page_users = raw.loc[raw["saw_both_pages"], "user_id"].nunique()
check(
    f"raw users {raw_users:,} - saw both pages {both_page_users:,} = clean users {len(clean):,}",
    raw_users - both_page_users == len(clean),
)
check("clean data has one row per user", clean["user_id"].is_unique)
check(
    "every clean row has matching group and page",
    (clean["landing_page"] == clean["test_group"].map({"control": "old_page", "treatment": "new_page"})).all(),
)

# 7b. Within every segment type, the segments add up to the group totals.
group_totals = clean.groupby("test_group")["converted"].agg(users="count", conversions="sum")
segment_sums = by_segment.groupby(["segment_type", "test_group"])[["users", "conversions"]].sum()
for segment_type in segment_columns:
    check(
        f"'{segment_type}' segments add up to the group totals",
        segment_sums.loc[segment_type].equals(group_totals),
    )

funnel_sums = funnel.pivot_table(
    index=["segment_type", "test_group"], columns="step_order", values="users", aggfunc="sum"
)
check(
    "funnel.csv matches conversion_by_segment.csv",
    (funnel_sums[1] == segment_sums["users"]).all() and (funnel_sums[2] == segment_sums["conversions"]).all(),
)
daily_sums = daily.groupby(["segment_type", "test_group"])[["users", "conversions"]].sum()
check("daily_conversion.csv matches conversion_by_segment.csv", daily_sums.equals(segment_sums))

# 7c. Rates are valid.
check(
    "all rates are between 0 and 1",
    by_segment[["conversion_rate", "ci_lower", "ci_upper"]].stack().between(0, 1).all()
    and funnel["pct_of_group"].between(0, 1).all()
    and daily["conversion_rate"].between(0, 1).all()
    and lift[["control_rate", "treatment_rate", "p_value"]].stack().between(0, 1).all(),
)
check(
    "ci_lower <= conversion_rate <= ci_upper on every row",
    ((by_segment["ci_lower"] <= by_segment["conversion_rate"])
     & (by_segment["conversion_rate"] <= by_segment["ci_upper"])).all(),
)
check(
    "lift_by_segment.csv has one row per segment, with diff_ci_lower <= diff_pp <= diff_ci_upper",
    len(lift) == by_segment[["segment_type", "segment"]].drop_duplicates().shape[0]
    and ((lift["diff_ci_lower"] <= lift["diff_pp"]) & (lift["diff_pp"] <= lift["diff_ci_upper"])).all(),
)

# 7d. The "All" rows match the original analysis (output/ab_test_results.csv).
original = pd.read_csv(ROOT / "output" / "ab_test_results.csv").query("cleaning == 'ab_clean'").iloc[0]
overall = by_segment[by_segment["segment_type"] == "All"].set_index("test_group")
for group in ["control", "treatment"]:
    row = overall.loc[group]
    original_ci = [float(x) for x in original[f"{group}_ci95"].strip("[]").split(",")]
    check(
        f"{group}: {row['users']:,} users, {row['conversions']:,} conversions, "
        f"rate {row['conversion_rate']:.4%} match the original analysis",
        row["users"] == original[f"{group}_users"]
        and row["conversions"] == original[f"{group}_conversions"]
        and abs(100 * row["conversion_rate"] - original[f"{group}_cr_pct"]) < 1e-9,
    )
    check(
        f"{group}: 95% CI [{row['ci_lower']:.3%}, {row['ci_upper']:.3%}] matches the original analysis",
        round(100 * row["ci_lower"], 3) == original_ci[0] and round(100 * row["ci_upper"], 3) == original_ci[1],
    )

# 7e. The "All" lift row matches the original analysis too.
overall_lift = lift[lift["segment_type"] == "All"].iloc[0]
original_diff_ci = [float(x) for x in original["diff_ci95_pp"].strip("[]").split(",")]
check(
    f"lift: control {overall_lift['control_rate']:.4%}, treatment {overall_lift['treatment_rate']:.4%}, "
    f"diff {overall_lift['diff_pp']:+.4f} pp match the original analysis",
    abs(100 * overall_lift["control_rate"] - original["control_cr_pct"]) < 1e-9
    and abs(100 * overall_lift["treatment_rate"] - original["treatment_cr_pct"]) < 1e-9
    and abs(overall_lift["diff_pp"] - original["diff_pp"]) < 1e-9,
)
check(
    f"lift: 95% CI [{overall_lift['diff_ci_lower']:.3f}, {overall_lift['diff_ci_upper']:.3f}] pp "
    "matches the original analysis",
    round(overall_lift["diff_ci_lower"], 3) == original_diff_ci[0]
    and round(overall_lift["diff_ci_upper"], 3) == original_diff_ci[1],
)
check(
    f"lift: p-value {overall_lift['p_value']:.4f} matches the original analysis",
    abs(overall_lift["p_value"] - original["p_value_two_sided"]) < 1e-9,
)


# ---------------------------------------------------------------------------
# 8. Save
# ---------------------------------------------------------------------------
funnel.to_csv(OUT / "funnel.csv", index=False)
by_segment.to_csv(OUT / "conversion_by_segment.csv", index=False)
daily.to_csv(OUT / "daily_conversion.csv", index=False)
lift.to_csv(OUT / "lift_by_segment.csv", index=False)

print("\nFiles written")
outputs = [
    ("funnel.csv", funnel),
    ("conversion_by_segment.csv", by_segment),
    ("daily_conversion.csv", daily),
    ("lift_by_segment.csv", lift),
]
for name, table in outputs:
    print(f"  tableau/{name:28s} {len(table):>4} rows")
