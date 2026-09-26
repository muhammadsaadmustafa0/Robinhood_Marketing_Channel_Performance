# Outputs

Exported CSVs from the SQL analysis views. Add these here before your final commit:

- [ ] `campaign_metrics.csv` — `SELECT * FROM dbo.vw_campaign_metrics ORDER BY roas_90d DESC;`
- [ ] `channel_metrics.csv` — `SELECT * FROM dbo.vw_channel_metrics;`
- [ ] `traffic_comparison.csv` — `SELECT * FROM dbo.vw_traffic_comparison;`
- [ ] `monthly_campaign.csv` — `SELECT * FROM dbo.vw_monthly_campaign ORDER BY campaign, month_start;`
- [ ] `metric_rankings.csv` — `SELECT * FROM dbo.vw_metric_rankings;`
- [ ] `budget_scenarios.csv` — Section 8c summary query in the SQL script

In SQL Server / VS Code (mssql extension): run the query, then use the "Save as CSV" icon in the results pane.

`charts/` — optional: any standalone chart images you export from Tableau (e.g. for use outside the dashboard, in a blog post, or LinkedIn).
