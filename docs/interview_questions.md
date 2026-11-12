# The 5 hardest interview questions about this project

### 1. "A 2% repeat rate sounds like a bug. How do you know it's real?"
I tested the two ways it could be wrong, in both directions.
- **Too low?** Olist creates a new `customer_id` for every order, so I used `customer_unique_id`. On `customer_id` the rate would literally be 0%.
- **Too high?** One checkout with several sellers creates several orders at the same moment, so I only count purchases on different days. Without that the rate would be about 40% higher.
- **Unfair to recent customers?** The "ever repeated" rate penalizes people who bought recently, so I added a fixed 180-day window for customers we could observe that long. That gives **1.99%**.
- **Consistent across cohorts?** Cohort retention is about 0.5% in month 1 for every cohort.

A consistent number under all those definitions points to the business, not the query: Olist is a marketplace people use once.

### 2. "Late orders score 2 stars lower. Is that causal?"
It's observational, so I wouldn't claim pure causation, but three things make it convincing.
- **Within-state comparison:** the gap holds in all 21 states with enough late orders (−1.6 to −2.6), so it isn't just harsh-reviewing regions.
- **Dose-response:** scores fall steadily with lateness: 4.03 on the estimated day, 3.29 at 1–3 days late, 2.10 at 4–7 days, 1.67 at 8–14 days.
- **Timing:** 74.5% of late orders were reviewed before the package arrived, because Olist sends the survey on the estimated date. The review is literally reacting to the missed date.

What I didn't control is seller and category. My next step would be a regression of score on lateness with seller fixed effects.

### 3. "How did you make sure your joins didn't double-count revenue?"
- I wrote down the grain of every table first: `order_items` and `order_payments` are both many rows per order, and 547 orders have more than one review.
- I aggregated items to one row per order before joining anything, never joined items to payments, and deduplicated reviews with `ROW_NUMBER() ... WHERE rn = 1`.
- Then I proved it: `99_audit_checks.sql` asserts one row per order in every view and reconciles category revenue to order revenue to the cent (R$13,449,529.68 both ways). It runs on every build.

### 4. "In the A/B test, why drop users who saw both pages instead of just their bad rows?"
- A user who saw both the old and new page was exposed to both treatments, so their conversion can't be credited to either one.
- Dropping only the mismatched row would quietly keep those users in the "clean" data.
- I remove them entirely, then keep each remaining user's first exposure so every user is one independent observation, which the z-test requires.
- Because this is a judgment call, I re-ran the test with the simpler "drop bad rows only" rule as a sensitivity check. The conclusion shouldn't depend on the choice.
- I also checked that the mismatch bug hit both groups equally and that the split passed a sample-ratio-mismatch test. A broken randomization would invalidate the test regardless of cleaning.

Numbers to quote:
- 3,893 mismatched rows: 1.31% of control rows vs 1.33% of treatment rows, so the bug hit both groups equally.
- 1,998 users saw both pages and were dropped entirely, leaving 288,586 clean users.
- The textbook rule keeps 290,584 users and gives p = 0.19 vs 0.20. The conclusion is identical.

### 5. "Not significant means the new page doesn't work, right?"
No. "Not significant" means we didn't detect a difference, not that there is none.
- That's why I report the **confidence interval** for the lift, which shows the range of effects still consistent with the data.
- I also report the **minimum detectable effect at 80% power**. If the smallest lift we could reliably detect is bigger than a lift the business would care about, the test was underpowered for that question.
- I also compute how many users per group would be needed to detect a +2% relative lift.
- The recommendation then combines the statistics with cost.

In this test:
- p = 0.20 and the confidence interval is −0.39 to +0.08 points, so the best plausible lift is about +0.7% relative.
- The minimum detectable effect was 2.8% relative, and power for a +2% lift was only 51%. A +2% lift (+0.24 pp) is already outside the interval, so a bigger test wouldn't change the decision.
- So: don't launch, and don't extend. Go back to design and test something bolder.

---

**Backup questions worth preparing:**
- "Why compare categories by share instead of growth?" Because the platform grew 138%, raw growth makes everything look good.
- "Why exclude Sep–Oct 2018?" Those months have 20 orders in total; it's a truncated export, not a collapse.
- "Why compare dates, not timestamps, for lateness?" The estimate is stored as midnight, and timestamps would have mislabelled 1,292 on-time orders as late.
