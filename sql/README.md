# SQL build

Dialect: T-SQL (SQL Server 2016 SP1+ / Azure SQL). Tested by first building the
same logic in SQLite against the real CSVs; all expected values in the code
comments were verified that way.

## Run in this order

1. **`robinhood_marketing_analysis_tsql.sql`** — Sections 1–2 only (validation
   queries, then the two clean views `vw_ad_spend_clean` / `vw_signups_clean`).
2. **`robinhood_part2_remaining_build.sql`** — drops any earlier draft objects,
   rebuilds the clean views, then builds the star schema
   (`dim_campaign`, `dim_date`, `fact_ad_spend_daily`, `fact_signups`),
   the analysis views (campaign/channel metrics, traffic comparison, monthly
   trend, rankings), and the budget scenario model.

Run each file **section by section** (select a block between `GO` statements,
execute), not as one paste — several `CREATE TABLE` + `INSERT` pairs need to
commit before the next block reads from them.

## Checkpoints

| After | Expect |
|---|---|
| Section 1 | 1,046 / 18,840 raw rows; 7 exact-duplicate spend rows found |
| Section 2 | 1,039 clean spend rows; total spend $124,886.22 |
| Star schema build | 1,039 / 124,886.22 / 18,840; 0 channel mismatches |
| Campaign metrics reconciliation | Metrics-table totals match source totals exactly |
| Traffic comparison | referral ~19.9%, organic ~9.8%, all paid ~11.9% signup-to-paid |
| Campaign status | `display_network` last spend 2025-05-14, flagged STOPPED |
| Budget scenarios (0.7 efficiency) | H1_repeat ≈1,698 subs @ $73.55/sub |

## Data model

```
dim_date ──< fact_ad_spend_daily >── dim_campaign ──< fact_signups >── dim_date
```

Both fact tables are aggregated to campaign level before being joined to each
other's outcomes (see `vw_campaign_base`) — never joined directly row-to-row,
which would fan out spend across every matching signup.
