# Build Guide: A/B Test Dashboard in Tableau Public

This guide builds a three-chart dashboard from the files in this folder, with one segment selector that controls every chart.

To regenerate the files: `python tableau/make_tableau_data.py`

## The files

| File | One row per | Columns |
|---|---|---|
| `funnel.csv` | segment, test group, funnel step | `segment_type`, `segment`, `test_group`, `step_order`, `step_name`, `users`, `pct_of_group` |
| `conversion_by_segment.csv` | segment, test group | `segment_type`, `segment`, `test_group`, `users`, `conversions`, `conversion_rate`, `ci_lower`, `ci_upper` |
| `daily_conversion.csv` | segment, test group, day | `segment_type`, `segment`, `test_group`, `date`, `users`, `conversions`, `conversion_rate` |

Values you'll see:

- `test_group`: `control` (old page) or `treatment` (new page).
- `segment_type`: `All`, `Country`, `Day type`, `Test week`.
- `segment`: `All`; `US`, `UK`, `CA`; `Weekday`, `Weekend`; `Week 1 (Jan 2-8)` to `Week 4 (Jan 23-24)`.
- All rates (`conversion_rate`, `ci_lower`, `ci_upper`, `pct_of_group`) are fractions between 0 and 1. Format them as percentages in Tableau.

**The one rule that keeps the numbers right:** every chart must show exactly one `segment_type` at a time, and must have `segment` in the view. Each segment type is a complete copy of all users, so mixing two types would double-count. The selector in step 2 enforces this.

**What is not here:** there is no device segment and no retention file. The data has one landing-page visit per user, no device column and no signup date. The funnel has only two steps because the data records only two.

---

## Step 1: Connect the three files

1. Open Tableau Public. Under **Connect**, choose **Text file** and open `funnel.csv`.
2. Go to **Data → New Data Source → Text file** and open `conversion_by_segment.csv`.
3. Repeat for `daily_conversion.csv`.

Keep them as three separate data sources. Don't drag them onto the same canvas to join them.

For each data source, set the formats once (right-click the field → **Default Properties → Number Format → Percentage**, 2 decimals):

- `conversion_by_segment`: `conversion_rate`, `ci_lower`, `ci_upper`
- `funnel`: `pct_of_group`
- `daily_conversion`: `conversion_rate`

In `funnel`, drag `step_order` from Measures up to Dimensions if Tableau put it under Measures.

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

## Step 3: Chart 1, conversion rate with confidence intervals

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

How to read it: the circle is the conversion rate and the bar is its 95% Wilson interval. When the control and treatment bars overlap, the difference for that segment is within the noise.

Each mark is exactly one row of the file, so `SUM` and `AVG` give the same value. Leave the default.

## Step 4: Chart 2, funnel

Data source: **`funnel`**. Name the sheet `Funnel`.

1. Drag `Show Segment Type` to **Filters** → tick **True**.
2. **Rows:** `segment`, `step_name`, `test_group`.
3. Sort the steps: right-click `step_name` on Rows → **Sort** → **Field** → `step_order`, **Ascending**, aggregation **Minimum**.
4. **Columns:** `users` (SUM).
5. **Color:** `test_group`. Assign the same two colors as chart 1.
6. **Label:** drag `pct_of_group` to **Label**.

The funnel has two steps: `Visited landing page` (100%) and `Converted`.

## Step 5: Chart 3, daily trend

Data source: **`daily_conversion`**. Name the sheet `Daily trend`.

1. Drag `Show Segment Type` to **Filters** → tick **True**.
2. **Columns:** right-click-drag `date` to Columns and choose **date (Continuous)**, the first option, so you get one point per day.
3. **Rows:** `segment`, then `conversion_rate` (SUM). You get one pane per segment.
4. **Color:** `test_group`, same two colors.
5. Right-click the rate axis → **Edit Axis** → untick **Include zero**.
6. **Tooltip:** add `users` and `conversions`.

Daily rates are noisy. With about 6,500 users per group per day, a single day moves by roughly ±0.8 percentage points from chance alone, and far more in a small segment like `CA` (about 300 users per group per day). Read the overall pattern, not single days. Jan 2 and Jan 24 are partial days.

## Step 6: Assemble the dashboard

1. **Dashboard → New Dashboard**. Set **Size** to a fixed 1200 × 900, or **Automatic**.
2. Drag in `Conversion by segment` (top), then `Funnel` and `Daily trend` (bottom, side by side).
3. The `Segment Type` control appears on the right. If it doesn't, click any sheet's drop-down arrow → **Parameters → Segment Type**. Set it to display as **Single Value (list)**.
4. Add a **Text** object at the top with the headline result:
   - New page 11.87% vs old page 12.03% conversion
   - Difference −0.16 points, p = 0.198 (two-proportion z-test, 288,586 users)
   - Recommendation: don't launch
5. Test the selector: switch through all four values and confirm all three charts change together.

### Optional: narrow to specific segments (for example, US only)

1. On the `Conversion by segment` sheet, drag `segment` to **Filters** and select all values.
2. Right-click the filter → **Show Filter**. On the filter card's drop-down, choose **Only Relevant Values**.
3. Right-click the filter → **Apply to Worksheets → All Using Related Data Sources**.

This needs Tableau to treat `segment` as the same field in all three sources. It matches same-named fields automatically; if the option is grayed out, check **Data → Edit Blend Relationships** and confirm `segment` and `segment_type` are linked for each pair of sources.

## Step 7: Publish

1. **File → Save to Tableau Public As…** and sign in.
2. On the published page, turn on **Show Sheets as Tabs** only if you want viewers to see the individual sheets.
3. Copy the URL into the project README.

---

## Reading the segments honestly

The segment charts are exploratory. Ten comparisons are shown (overall plus nine segments), so one or two will look "significant" by chance alone.

| Segment | Control | Treatment | Difference |
|---|---|---|---|
| All | 12.03% | 11.87% | −0.16 pp |
| US | 12.05% | 11.83% | −0.22 pp |
| UK | 11.99% | 12.11% | +0.12 pp |
| CA | 11.87% | 11.22% | −0.66 pp |
| Weekday | 11.97% | 11.93% | −0.04 pp |
| Weekend | 12.19% | 11.72% | −0.46 pp |

- No segment shows a clear win for the new page. UK is the only one where it is ahead, and that gap is well within its interval.
- Weekend is the largest gap with enough users to matter (z = −2.0, p ≈ 0.05 before any correction for multiple comparisons). Treat it as a question for the next test, not a finding.
- The four test weeks all show the new page slightly behind (−0.12 to −0.25 pp), so there is no novelty effect.

These numbers support the original recommendation: don't launch.

## Data sources

- `data/ab_data.csv`: the Udacity "Analyze A/B Test Results" file used in the original analysis.
- `data/countries.csv`: the companion file from the same project (`user_id`, `country`; 290,584 rows; SHA-256 `c011d050…0d55e45b`), for example from [this public copy](https://github.com/deepaksithu/Analyze_AB_Test_Results_Project). The script skips the Country segment if this file is missing.
