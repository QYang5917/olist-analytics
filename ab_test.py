"""A/B test analysis for data/ab_data.csv.

Cleaning and descriptive tables are SQL (sql/ab_01_clean.sql, sql/ab_02_summary.sql).
This script adds the statistics SQL can't do:
  * sample-ratio-mismatch (SRM) check
  * two-proportion z-test (two-sided, plus one-sided "is new page better?")
  * 95% confidence intervals for each rate and for the difference
  * power: minimum detectable effect, power for a +1pp / +2% relative lift,
    and the sample size that would have been needed
  * sensitivity check with the alternative cleaning rule
Usage:  python ab_test.py      (writes output/ab_*.csv)
"""
import re
from pathlib import Path

import duckdb
import numpy as np
import pandas as pd
from scipy import stats
from statsmodels.stats.power import NormalIndPower
from statsmodels.stats.proportion import (confint_proportions_2indep,
                                          proportion_confint,
                                          proportion_effectsize,
                                          proportions_ztest)

ROOT = Path(__file__).parent
SQL, OUT = ROOT / "sql", ROOT / "output"
OUT.mkdir(exist_ok=True)
ALPHA, TARGET_POWER = 0.05, 0.80

con = duckdb.connect(str(ROOT / "olist.duckdb"))
con.execute((SQL / "ab_01_clean.sql").read_text())

# Descriptive SQL exports
marker = re.compile(r"^--\s*@export:\s*(\S+)\s*$", re.M)
parts = marker.split((SQL / "ab_02_summary.sql").read_text())
for name, query in zip(parts[1::2], parts[2::2]):
    df = con.sql(query.strip().rstrip(";")).df()
    df.to_csv(OUT / name, index=False)
    print(f"\n== {name}\n{df.to_string(index=False) if len(df) < 30 else df.head(5).to_string(index=False) + ' ...'}")


def analyse(view: str) -> dict:
    g = con.sql(f"""
        SELECT "group", COUNT(*) AS n, SUM(converted) AS conv
        FROM {view} GROUP BY "group" ORDER BY "group" """).df().set_index("group")
    n_c, x_c = int(g.loc["control", "n"]), int(g.loc["control", "conv"])
    n_t, x_t = int(g.loc["treatment", "n"]), int(g.loc["treatment", "conv"])
    p_c, p_t = x_c / n_c, x_t / n_t

    # SRM: were users really split ~50/50? A chi-square on counts.
    srm_p = stats.chisquare([n_c, n_t]).pvalue

    # Two-proportion z-test (pooled SE under H0: p_t == p_c)
    z, p_two = proportions_ztest([x_t, x_c], [n_t, n_c], alternative="two-sided")
    _, p_one = proportions_ztest([x_t, x_c], [n_t, n_c], alternative="larger")

    # CIs
    ci_c = proportion_confint(x_c, n_c, alpha=ALPHA, method="wilson")
    ci_t = proportion_confint(x_t, n_t, alpha=ALPHA, method="wilson")
    ci_d = confint_proportions_2indep(x_t, n_t, x_c, n_c, method="wald", compare="diff", alpha=ALPHA)

    # Power. "Observed power" from the observed effect is circular, so instead:
    #   - MDE: smallest lift we had 80% power to detect with these sample sizes
    #   - power to detect business-relevant lifts (+2% relative, +1pp absolute)
    #   - n per arm needed to detect a +2% relative lift
    pw = NormalIndPower()
    ratio = n_t / n_c
    es_mde = pw.solve_power(nobs1=n_c, alpha=ALPHA, power=TARGET_POWER, ratio=ratio)
    # convert Cohen's h back to a treatment rate: h = 2asin(sqrt(p_t)) - 2asin(sqrt(p_c))
    p_mde = np.sin(np.arcsin(np.sqrt(p_c)) + es_mde / 2) ** 2
    def power_for(p_new):
        return pw.power(proportion_effectsize(p_new, p_c), nobs1=n_c, alpha=ALPHA, ratio=ratio)
    n_needed_2pct = pw.solve_power(proportion_effectsize(p_c * 1.02, p_c), alpha=ALPHA, power=TARGET_POWER, ratio=1)

    return dict(
        cleaning=view, control_users=n_c, treatment_users=n_t,
        control_conversions=x_c, treatment_conversions=x_t,
        control_cr_pct=100 * p_c, treatment_cr_pct=100 * p_t,
        control_ci95=f"[{100*ci_c[0]:.3f}, {100*ci_c[1]:.3f}]",
        treatment_ci95=f"[{100*ci_t[0]:.3f}, {100*ci_t[1]:.3f}]",
        diff_pp=100 * (p_t - p_c), diff_ci95_pp=f"[{100*ci_d[0]:.3f}, {100*ci_d[1]:.3f}]",
        relative_lift_pct=100 * (p_t - p_c) / p_c,
        z_stat=z, p_value_two_sided=p_two, p_value_one_sided_new_better=p_one,
        srm_p_value=srm_p,
        mde_abs_pp_at_80pct_power=100 * (p_mde - p_c),
        mde_relative_pct=100 * (p_mde - p_c) / p_c,
        power_for_plus_2pct_relative=power_for(p_c * 1.02),
        power_for_plus_1pp=power_for(p_c + 0.01),
        n_per_arm_needed_for_plus_2pct_relative=int(np.ceil(n_needed_2pct)),
    )


results = pd.DataFrame([analyse("ab_clean"), analyse("ab_clean_alt")])
results.to_csv(OUT / "ab_test_results.csv", index=False)
pd.set_option("display.float_format", lambda v: f"{v:.5g}")
print("\n== ab_test_results.csv (column = cleaning rule)\n", results.set_index("cleaning").T.to_string())
