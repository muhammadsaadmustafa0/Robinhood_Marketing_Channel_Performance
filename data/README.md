# Raw data

Untouched source files. Never edited directly — all cleaning happens in
`sql/robinhood_marketing_analysis_tsql.sql` (Sections 1–2), so the fixes are
visible and auditable rather than hidden in a spreadsheet edit.

| File | Rows | Grain | Notes |
|---|---|---|---|
| `ad_spend.csv` | 1,046 | one row per campaign per day | Contains 7 exact duplicate rows (removed in Section 2 of the SQL script) |
| `signups.csv` | 18,840 | one row per user | `campaign`, `plan`, `subscription_start_date` are empty for organic/referral signups and for users who never subscribed — this is expected, not missing data |

See the main [README](../README.md) for the full column dictionary and analysis.
