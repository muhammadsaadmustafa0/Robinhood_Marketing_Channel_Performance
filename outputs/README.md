# Outputs

Exported results from the SQL analysis views (`sql/robinhood_part2_remaining_build.sql`, Sections 4–8).

## `campaign_metrics.csv`
Spend, CTR, CPC, cost per signup, cost per paying subscriber, and ROAS for each of the 6 paid campaigns. The core metrics table everything else is built from.

## `channel_metrics.csv`
The same metrics rolled up to channel level (paid_search, paid_social, display, finance_blogs) instead of per campaign.

## `traffic_comparison.csv`
Signup-to-paid conversion rate and revenue per signup for each paid campaign plus organic and referral — answers whether paid traffic converts better than free traffic.

## `monthly_campaign.csv`
Spend, signups, and cost per paying subscriber by campaign, month by month (Jan–Jun 2025). Shows that `display_network` stopped running in May.

## `metric_rankings.csv`
Each campaign's rank under four different metrics side by side, proving that the cheapest campaign per signup isn't the cheapest per paying subscriber.

## `budget_scenarios.csv`
Projected paying subscribers and blended cost per subscriber for each proposed H2 budget split, at three different efficiency assumptions. The table the final recommendation is drawn from.
