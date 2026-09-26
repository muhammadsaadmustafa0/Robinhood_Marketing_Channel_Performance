# Dashboard

Add these three files here before your final commit:

- [ ] `robinhood_dashboard.twbx` — packaged Tableau workbook (File → Export Packaged Workbook...). Fully interactive when opened in the free [Tableau Reader](https://www.tableau.com/products/reader) — filter actions, the campaign click-through, and the efficiency parameter all work.
- [ ] `robinhood_dashboard.pdf` — static export (File → Print → Save as PDF) for anyone who doesn't want to install Reader.
- [ ] `robinhood_dashboard.png` — screenshot (Cmd+Shift+4) of the full dashboard, used inline in the main README.

## Sheets included
- Campaign KPIs — full metrics table, colored by ROAS
- Efficiency Scatter — cost per signup vs. cost per paying sub (the headline chart)
- Paid vs Unpaid Conversion — signup-to-paid rate by segment
- Monthly Trend — spend and cost-per-paying-sub over time, flags `display_network` stopping
- Budget Scenario — projected paying subs / cost per sub by scenario, with an efficiency-assumption toggle (0.5 / 0.7 / 1.0)
