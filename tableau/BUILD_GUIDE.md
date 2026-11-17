# Build Guide: A/B Test Dashboard in Tableau Public

This guide builds a three-chart dashboard from the files in this folder, with one segment selector that controls every chart.

To regenerate the files: `python tableau/make_tableau_data.py`

## Ready-made workbook

`ab_test_dashboard.twb` in this folder is the finished dashboard described below, so you can open it in Tableau Public and publish without building anything. `ab_test_dashboard_simple.twb` is the same dashboard with plain bar and line charts.

- Tableau Public only opens and publishes workbooks whose data is an extract, so the workbooks read the three `.hyper` files in this folder, not the CSVs. Keep the workbook and the `.hyper` files together.
- If the CSVs change, rebuild the extracts with `python tableau/make_hyper_extracts.py` (needs `pip install tableauhyperapi`).
- Tested with Tableau Public 2026.3.

The rest of this guide explains how to build the same dashboard by hand from the CSVs.

## The files

| File | One row per | Columns |
|---|---|---|
| `lift_by_segment.csv` | segment | `segment_type`, `segment`, `control_rate`, `treatment_rate`, `diff_pp`, `diff_ci_lower`, `diff_ci_upper`, `p_value` |
| `conversion_by_segment.csv` | segment, test group | `segment_type`, `segment`, `test_group`, `users`, `conversions`, `conversion_rate`, `ci_lower`, `ci_upper` |
| `daily_conversion.csv` | segment, test group, day | `segment_type`, `segment`, `test_group`, `date`, `users`, `conversions`, `conversion_rate` |
| `funnel.csv` (not used in this dashboard) | segment, test group, funnel step | `segment_type`, `segment`, `test_group`, `step_order`, `step_name`, `users`, `pct_of_group` |

Values you'll see:

- `test_group`: `control` (old page) or `treatment` (new page).
- `segment_type`: `All`, `Country`, `Day type`, `Test week`.
- `segment`: `All`; `US`, `UK`, `CA`; `Weekday`, `Weekend`; `Week 1 (Jan 2-8)` to `Week 4 (Jan 23-24)`.
- Rates (`conversion_rate`, `ci_lower`, `ci_upper`, `control_rate`, `treatment_rate`, `pct_of_group`) are fractions between 0 and 1. Format them as percentages in Tableau.
- `diff_pp`, `diff_ci_lower` and `diff_ci_upper` are in **percentage points**, treatment minus control. A value of `-0.16` means the new page converted 0.16 points lower. The interval is a 95% Wald interval.
- `p_value` is from a two-sided, two-proportion z-test.

**The one rule that keeps the numbers right:** every chart must show exactly one `segment_type` at a time, and must have `segment` in the view. Each segment type is a complete copy of all users, so mixing two types would double-count. The selector in step 2 enforces this.

**What is not here:** there is no device segment and no retention file. The data has one landing-page visit per user, no device column and no signup date. `funnel.csv` is still produced, but the dashboard doesn't use it: the data records only two steps (visited, converted), so a funnel chart adds nothing the conversion rate doesn't already show.

---

## Step 1: Connect the three files

1. Open Tableau Public. Under **Connect**, choose **Text file** and open `lift_by_segment.csv`.
2. Go to **Data → New Data Source → Text file** and open `conversion_by_segment.csv`.
3. Repeat for `daily_conversion.csv`.

Keep them as three separate data sources. Don't drag them onto the same canvas to join them.

For each data source, set the formats once (right-click the field → **Default Properties → Number Format**):

- `lift_by_segment`:
  - `control_rate`, `treatment_rate`: **Percentage**, 2 decimals
  - `diff_pp`, `diff_ci_lower`, `diff_ci_upper`: **Custom**, with the format `+0.00" pp";-0.00" pp"`
  - `p_value`: **Number (Custom)**, 3 decimals
- `conversion_by_segment`: `conversion_rate`, `ci_lower`, `ci_upper` as **Percentage**, 2 decimals
- `daily_conversion`: `conversion_rate` as **Percentage**, 2 decimals

## Step 2: Create the segment selector (controls every chart)

A parameter works across all data sources, so this is the most reliable way to drive three files with one control.

1. In the Data pane, click the small arrow at the top → **Create Parameter**.
   - Name: `Segment Type`
   - Data type: **String**
   - Allowable values: **List**, with these four values typed exactly: `All`, `Country`, `Day type`, `Test week`
   - Current value: `All`
2. In **each of the three data sources**, create a calculated field (**Analysis → Create Calculated Field**):
   - Name: `Show Segment Type`
   - Formula: `[segment_type] = [Segment Type]`
3. You'll drag `Show Segment Type` to **Filters** and tick **True** on every sheet (the chart steps below remind you).
4. Right-click the `Segment Type` parameter → **Show Parameter**.

## Step 3: Chart 1, lift by segment

Data source: **`lift_by_segment`**. Name the sheet `Lift by segment`.

This is the headline chart: for each segment, how much better or worse the new page converted, with a 95% interval and a line at zero.

1. Drag `Show Segment Type` to **Filters** → tick **True**.
2. **Rows:** `segment`.
3. **Columns:** drag `diff_pp`. On its Marks card, set the mark type to **Bar**.
4. Create a calculated field `diff_ci_width`: `[diff_ci_upper] - [diff_ci_lower]`
5. **Columns:** drag `diff_ci_lower` to the right of `diff_pp`. On its Marks card, set the mark type to **Gantt Bar**, then drag `diff_ci_width` to **Size**. Each Gantt bar now runs from `diff_ci_lower` to `diff_ci_upper`.
6. Right-click the `diff_ci_lower` pill → **Dual Axis**. Then right-click the top axis → **Synchronize Axis**, and right-click it again → untick **Show Header**.
7. Check the two Marks cards after the dual-axis step, because Tableau sometimes resets them: `SUM(diff_pp)` must be **Bar** and `SUM(diff_ci_lower)` must be **Gantt Bar**.
8. Style the marks so the interval reads clearly on top of the bar:
   - `SUM(diff_pp)` card: click **Color** and pick a light color.
   - `SUM(diff_ci_lower)` card: click **Color** and pick a dark color, then click **Size** and move the slider left so the interval is a thin line.
9. **Reference line at 0:** right-click the bottom axis → **Add Reference Line**. Choose **Line**, scope **Entire Table**, value **Constant** `0`, label **None**, and a solid dark line.
10. Right-click the bottom axis → **Edit Axis** and set the title to `Treatment minus control (percentage points)`.
11. **Tooltip** (All Marks card): add `control_rate`, `treatment_rate` and `p_value`.

How to read it:

- The bar is the difference in conversion rate. Left of zero means the new page converted worse; right of zero means better.
- The thin dark bar is the 95% interval for that difference.
- If the interval crosses the zero line, the difference is not statistically significant at the 5% level. If the whole interval sits on one side of zero, it is.
- The interval and `p_value` use slightly different standard errors (unpooled for the interval, pooled for the test), so they can disagree by a hair when a result sits right on the boundary.

Each mark is exactly one row of the file, so `SUM` and `AVG` give the same value. Leave the default.

## Step 4: Chart 2, conversion rate with confidence intervals

Data source: **`conversion_by_segment`**. Name the sheet `Conversion by segment`.

1. Drag `Show Segment Type` to **Filters** → tick **True**.
2. **Rows:** `segment`, then `test_group`.
3. Create a calculated field `ci_width`: `[ci_upper] - [ci_lower]`
4. **Columns:** drag `ci_lower`. On the Marks card for it, change the mark type to **Gantt Bar**, then drag `ci_width` to **Size**. Each bar now runs from `ci_lower` to `ci_upper`.
5. **Columns:** drag `conversion_rate` to the right of `ci_lower`. On its Marks card, change the mark type to **Circle**.
6. Right-click the `conversion_rate` pill → **Dual Axis**. Then right-click the top axis → **Synchronize Axis**, and right-click it again → untick **Show Header**.
7. **Color:** on the **All** Marks card, drag `test_group` to **Color**. Pick two colors you'll reuse everywhere, for example gray for `control` and blue for `treatment`.
8. Right-click the bottom axis → **Edit Axis** → untick **Include zero**. The rates sit near 12%, so the intervals are invisible on an axis that starts at 0.
9. Make the Gantt bars thin: on the `ci_lower` Marks card, click **Size** and move the slider left.
10. **Tooltip** (All Marks card): add `users` and `conversions`.

How to read it: the circle is each group's conversion rate and the bar is its 95% Wilson interval. This chart shows the level of each rate and how precisely it is measured.

Don't use overlap between the two bars to judge significance. If the bars don't overlap, the difference is significant. If they do overlap, the difference may still be significant, because the interval for a difference is narrower than the two separate intervals suggest. Weekend is the example in this data: the two bars overlap, yet the difference has p = 0.046. Use the lift chart to judge whether a difference is real.

## Step 5: Chart 3, daily trend

Data source: **`daily_conversion`**. Name the sheet `Daily trend`.

1. Drag `Show Segment Type` to **Filters** → tick **True**.
2. **Columns:** right-click-drag `date` to Columns and choose **date (Continuous)**, the first option, so you get one point per day.
3. **Rows:** `segment`, then `conversion_rate` (SUM). You get one pane per segment.
4. **Color:** `test_group`, with the same two colors as chart 2.
5. Right-click the rate axis → **Edit Axis** → untick **Include zero**.
6. **Tooltip:** add `users` and `conversions`.

Daily rates are noisy. With about 6,500 users per group per day, a single day moves by roughly ±0.8 percentage points from chance alone, and far more in a small segment like `CA` (about 300 users per group per day). Read the overall pattern, not single days. Jan 2 and Jan 24 are partial days.

## Step 6: Assemble the dashboard

1. **Dashboard → New Dashboard**. Set **Size** to a fixed 1200 × 900, or **Automatic**.
2. Drag in `Lift by segment` (top), then `Conversion by segment` and `Daily trend` (bottom, side by side).
3. The `Segment Type` control appears on the right. If it doesn't, click any sheet's drop-down arrow → **Parameters → Segment Type**. Set it to display as **Single Value (list)**.
4. Add a **Text** object at the top with the headline result:
   - New page 11.87% vs old page 12.03% conversion
   - Difference −0.16 points (95% CI −0.39 to +0.08), p = 0.198 (two-proportion z-test, 288,586 users)
   - Recommendation: don't launch
5. Test the selector: switch through all four values and confirm all three charts change together.

### Optional: narrow to specific segments (for example, US only)

1. On the `Lift by segment` sheet, drag `segment` to **Filters** and select all values.
2. Right-click the filter → **Show Filter**. On the filter card's drop-down, choose **Only Relevant Values**.
3. Right-click the filter → **Apply to Worksheets → All Using Related Data Sources**.

This needs Tableau to treat `segment` as the same field in all three sources. It matches same-named fields automatically; if the option is grayed out, check **Data → Edit Blend Relationships** and confirm `segment` and `segment_type` are linked for each pair of sources.

## Step 7: Publish

1. **File → Save to Tableau Public As…** and sign in.
2. On the published page, turn on **Show Sheets as Tabs** only if you want viewers to see the individual sheets.
3. Copy the URL into the project README.

---

## Reading the segments honestly

The segment charts are exploratory. Ten comparisons are shown (overall plus nine segments), so one "significant" result at the 5% level is not surprising by chance alone.

| Segment | Control | Treatment | Difference (95% CI) | p-value |
|---|---|---|---|---|
| All | 12.03% | 11.87% | −0.16 pp (−0.39 to +0.08) | 0.198 |
| US | 12.05% | 11.83% | −0.22 pp (−0.50 to +0.07) | 0.133 |
| UK | 11.99% | 12.11% | +0.12 pp (−0.36 to +0.60) | 0.622 |
| CA | 11.87% | 11.22% | −0.66 pp (−1.70 to +0.39) | 0.218 |
| Weekday | 11.97% | 11.93% | −0.04 pp (−0.32 to +0.24) | 0.777 |
| Weekend | 12.19% | 11.72% | −0.46 pp (−0.91 to −0.01) | 0.046 |

- No segment shows a win for the new page. UK is the only one where it is ahead, and its interval comfortably includes zero.
- Weekend is the only segment whose interval excludes zero, and it points against the new page. With ten comparisons and no correction, treat it as a question for the next test, not a finding.
- The four test weeks all show the new page slightly behind (−0.12 to −0.25 pp, p between 0.43 and 0.58), so there is no novelty effect.

These numbers support the original recommendation: don't launch.

## Data sources

- `data/ab_data.csv`: the Udacity "Analyze A/B Test Results" file used in the original analysis.
- `data/countries.csv`: the companion file from the same project (`user_id`, `country`; 290,584 rows; SHA-256 `c011d050…0d55e45b`), for example from [this public copy](https://github.com/deepaksithu/Analyze_AB_Test_Results_Project). The script skips the Country segment if this file is missing.
