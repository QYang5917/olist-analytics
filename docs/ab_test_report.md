# A/B Test Report: new landing page vs old

**Data:** `data/ab_data.csv`, 294,478 rows covering 290,584 users from Jan 2 to Jan 24, 2017 (22 days).
**Question:** Does the new landing page convert better than the old one?
**Code:** cleaning in [`sql/ab_01_clean.sql`](../sql/ab_01_clean.sql), tables in [`sql/ab_02_summary.sql`](../sql/ab_02_summary.sql), statistics in [`ab_test.py`](../ab_test.py).

## Recommendation: do not launch the new page

The new page converted at **11.87% vs 12.03%** for the old page. That's **0.16 points lower (−1.3% relative)**, and the difference isn't statistically significant (p = 0.20).

The more useful number is the 95% confidence interval for the difference: **−0.39 to +0.08 points**. Even in the best case consistent with the data, the new page adds at most +0.08 points (about +0.7% relative). That's too small to justify the cost and risk of a rollout, so there is no realistic upside to chase.

**I also wouldn't extend the test.** Running longer only narrows the interval around a number that is already centered slightly below zero. The better move is to go back to design and test a meaningfully different page.

## 1. Cleaning: what I found and why I handled it this way

| Step | Found | Decision | Why |
|---|---|---|---|
| Mismatched rows | **3,893 rows** where the group and page disagree (control saw `new_page`, or treatment saw `old_page`) | Remove | The bucketing or logging broke for these rows. We can't tell which experience the user was meant to get, so they can't be assigned to either arm |
| Is the bug biased? | Mismatch rate: control 1.31%, treatment 1.33% | Safe to remove | The bug hit both groups equally. If it had hit one group far more, removing those rows could itself bias the comparison |
| Users who saw both pages | **1,998 users** (3,996 rows) were shown the old page and the new page | Remove the **whole user**, not just the bad row | Their conversion can't be credited to either page. Dropping only the mismatched row would quietly keep people exposed to both designs |
| Remaining duplicates | Users with 2+ rows on the same page | Keep their **first** exposure | One user = one observation. The z-test assumes independent observations, and repeat visitors shouldn't get extra votes |
| **Result** | **288,586 users**, one row each | | |

**Sensitivity check:** I re-ran everything with the simpler textbook rule (drop mismatched rows, keep each user's first remaining row; 290,584 users). Conversion rates move by about 0.01 points and p = 0.19, so the conclusion doesn't depend on the cleaning choice.

## 2. Sanity checks before trusting the result

- **Sample ratio mismatch:** 144,267 control vs 144,319 treatment. Chi-square p = 0.92, consistent with a clean 50/50 split. If this check fails, randomization is broken and no other result can be trusted.
- **Novelty effect:** daily conversion shows no early spike for the new page. It led on only 7 of 23 days. First half: 11.89% vs 11.88% (tied). Second half: 11.85% vs 12.16% (new page behind).

## 3. Hypothesis test

- H₀: p_new = p_old. H₁ (two-sided): p_new ≠ p_old.
- **Two-proportion z-test:** z = −1.29, **p = 0.198 (two-sided)**. One-sided "is the new page better?": p = 0.90.
- Significance level α = 0.05, so **we fail to reject H₀**.

| | Users | Conversions | Rate | 95% CI (Wilson) |
|---|---|---|---|---|
| Control (old page) | 144,267 | 17,349 | **12.03%** | 11.86% to 12.19% |
| Treatment (new page) | 144,319 | 17,131 | **11.87%** | 11.70% to 12.04% |
| **Difference** | | | **−0.16 pp** | **−0.39 to +0.08 pp** |

## 4. Statistical power: was the test big enough?

- **Minimum detectable effect at 80% power:** 0.34 points, about **2.8% relative**. The test reliably detects lifts of 2.8% or more.
- **Power to detect a +2% relative lift:** 51%, so a test of this size alone couldn't reliably find a 2% lift.
- **To detect +2% relative at 80% power:** about **290k users per arm**, roughly 2× this test (about 6 weeks).

**Why this doesn't change the recommendation:** power describes what a test of this size could detect before seeing data. Now that we have the data, the confidence interval's upper bound is +0.08 points, well below a +2% lift (+0.24 points). So the data already make a 2% lift unlikely even though the test wasn't designed to detect one.

## 5. Caveats

- **Short window:** 22 days, all in January. That captures weekly cycles but not seasonality.
- **New page shown to existing users:** some may resist change, which would show up as an early dip. We don't see one, but we can't tell new and returning users apart in this data.
- **"Converted" only:** the data has no revenue or downstream metrics. A page could convert slightly less but at higher order value.
