/* =====================================================================
   ROBINHOOD ANALYSIS - PART 2: build the correct star schema + views
   Run this AFTER dropping the old mismatched objects below.
   This picks up from where robinhood_marketing_analysis_tsql.sql leaves off
   (Section 2 clean views through Section 8 budget model).
   ===================================================================== */

-- ---------------------------------------------------------------------
-- STEP 0: drop the OLD objects from the earlier script version
-- (the ones with no "vw_" prefix, visible in your screenshot)
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS dbo.budget_scenario;
DROP VIEW IF EXISTS dbo.monthly_campaign;
DROP VIEW IF EXISTS dbo.campaign_metrics;
DROP VIEW IF EXISTS dbo.signups_clean;
DROP VIEW IF EXISTS dbo.ad_spend_clean;
GO

CREATE OR ALTER VIEW dbo.vw_ad_spend_clean AS
SELECT DISTINCT                                        -- removes the exact duplicate rows
    [date]                                            AS spend_date,
    LOWER(REPLACE(LTRIM(RTRIM(channel)), ' ', '_'))   AS channel_key,   -- 'Paid Search' -> 'paid_search'
    LTRIM(RTRIM(channel))                             AS channel_name,
    LTRIM(RTRIM(campaign))                            AS campaign,
    impressions,
    clicks,
    spend
FROM dbo.raw_ad_spend;
GO

CREATE OR ALTER VIEW dbo.vw_signups_clean AS
SELECT
    user_id,
    signup_date,
    LOWER(LTRIM(RTRIM(channel)))                                  AS channel_key,
    NULLIF(LTRIM(RTRIM(campaign)), '')                            AS campaign,       -- NULL for organic / referral
    subscription_start_date,
    NULLIF(LTRIM(RTRIM([plan])), '')                                AS [plan],
    revenue_first_90_days                                         AS revenue,
    CASE WHEN NULLIF(LTRIM(RTRIM([plan])), '') IS NOT NULL THEN 1 ELSE 0 END          AS is_paying,
    CASE WHEN NULLIF(LTRIM(RTRIM(campaign)), '') IS NOT NULL THEN 'paid' ELSE 'unpaid' END AS traffic_type,
    COALESCE(NULLIF(LTRIM(RTRIM(campaign)), ''), LOWER(LTRIM(RTRIM(channel)))) AS segment,  -- campaign, or organic/referral
    DATEDIFF(DAY, signup_date, subscription_start_date)           AS days_to_subscribe
FROM dbo.raw_signups;
GO

-- 2c. Sanity check. Expect 1,039 rows and total spend 124,886.22
SELECT COUNT(*) AS n_rows, CAST(SUM(spend) AS DECIMAL(12, 2)) AS total_spend
FROM dbo.vw_ad_spend_clean;
GO


/* =====================================================================
   SECTION 3 - MODEL TABLES (small star schema, ready for Power BI)

       dim_date ---< fact_ad_spend_daily >--- dim_campaign ---< fact_signups >--- dim_date
                     (PK: date + campaign)      (PK: campaign)   (PK: user_id)

   Primary/foreign keys are ENFORCED. If a duplicate or a mismatched name
   survived cleaning, the INSERT fails, which proves the cleaning worked.
   ===================================================================== */

-- Reset (drop in dependency order so the script can be re-run)
DROP TABLE IF EXISTS dbo.budget_proposal;
DROP TABLE IF EXISTS dbo.model_params;
DROP TABLE IF EXISTS dbo.fact_signups;
DROP TABLE IF EXISTS dbo.fact_ad_spend_daily;
DROP TABLE IF EXISTS dbo.dim_date;
DROP TABLE IF EXISTS dbo.dim_campaign;
GO

-- 3a. dim_campaign: 6 rows, one per campaign
CREATE TABLE dbo.dim_campaign (
    campaign     VARCHAR(50) NOT NULL CONSTRAINT PK_dim_campaign PRIMARY KEY,
    channel_key  VARCHAR(50) NOT NULL,
    channel_name VARCHAR(50) NOT NULL
);
GO
INSERT INTO dbo.dim_campaign (campaign, channel_key, channel_name)
SELECT DISTINCT campaign, channel_key, channel_name
FROM dbo.vw_ad_spend_clean;
GO

-- 3b. dim_date: one row per day, Jan-Jun 2025 (181 rows)
CREATE TABLE dbo.dim_date (
    date_key      DATE    NOT NULL CONSTRAINT PK_dim_date PRIMARY KEY,
    month_start   DATE    NOT NULL,
    month_label   CHAR(7) NOT NULL,     -- '2025-01'
    quarter_label CHAR(2) NOT NULL,     -- 'Q1' / 'Q2'
    month_number  TINYINT NOT NULL
);
GO
WITH d AS (
    SELECT CAST('2025-01-01' AS DATE) AS dt
    UNION ALL
    SELECT DATEADD(DAY, 1, dt) FROM d WHERE dt < '2025-06-30'
)
INSERT INTO dbo.dim_date (date_key, month_start, month_label, quarter_label, month_number)
SELECT dt,
       DATEFROMPARTS(YEAR(dt), MONTH(dt), 1),
       FORMAT(dt, 'yyyy-MM'),
       CONCAT('Q', DATEPART(QUARTER, dt)),
       MONTH(dt)
FROM d
OPTION (MAXRECURSION 400);
GO

-- 3c. fact_ad_spend_daily: one row per campaign per day (1,039 rows)
CREATE TABLE dbo.fact_ad_spend_daily (
    spend_date  DATE          NOT NULL,
    campaign    VARCHAR(50)   NOT NULL,
    impressions INT           NOT NULL,
    clicks      INT           NOT NULL,
    spend       DECIMAL(10,2) NOT NULL,
    CONSTRAINT PK_fact_ad_spend_daily PRIMARY KEY (spend_date, campaign),
    CONSTRAINT FK_spend_campaign FOREIGN KEY (campaign)   REFERENCES dbo.dim_campaign (campaign),
    CONSTRAINT FK_spend_date     FOREIGN KEY (spend_date) REFERENCES dbo.dim_date (date_key)
);
GO
INSERT INTO dbo.fact_ad_spend_daily (spend_date, campaign, impressions, clicks, spend)
SELECT spend_date, campaign, impressions, clicks, spend
FROM dbo.vw_ad_spend_clean;
GO

-- 3d. fact_signups: one row per user (18,840 rows). campaign is NULL for organic / referral
CREATE TABLE dbo.fact_signups (
    user_id                 INT           NOT NULL CONSTRAINT PK_fact_signups PRIMARY KEY,
    signup_date             DATE          NOT NULL,
    channel_key             VARCHAR(50)   NOT NULL,
    campaign                VARCHAR(50)   NULL,
    segment                 VARCHAR(50)   NOT NULL,   -- campaign name, or 'organic' / 'referral'
    traffic_type            VARCHAR(10)   NOT NULL,   -- 'paid' / 'unpaid'
    subscription_start_date DATE          NULL,
    [plan]                    VARCHAR(20)   NULL,
    revenue                 DECIMAL(10,2) NOT NULL,
    is_paying               INT           NOT NULL,
    days_to_subscribe       INT           NULL,
    CONSTRAINT CK_signups_plan   CHECK ([plan] IN ('monthly', 'annual')),
    CONSTRAINT CK_signups_paying CHECK (is_paying IN (0, 1)),
    CONSTRAINT FK_signups_campaign FOREIGN KEY (campaign)    REFERENCES dbo.dim_campaign (campaign),
    CONSTRAINT FK_signups_date     FOREIGN KEY (signup_date) REFERENCES dbo.dim_date (date_key)
);
GO
INSERT INTO dbo.fact_signups
    (user_id, signup_date, channel_key, campaign, segment, traffic_type,
     subscription_start_date, [plan], revenue, is_paying, days_to_subscribe)
SELECT user_id, signup_date, channel_key, campaign, segment, traffic_type,
       subscription_start_date, [plan], revenue, is_paying, days_to_subscribe
FROM dbo.vw_signups_clean;
GO

-- 3e. Post-build checks
--     Expect: 1039 | 124886.22 | 18840
SELECT (SELECT COUNT(*) FROM dbo.fact_ad_spend_daily)                     AS spend_rows,
       (SELECT CAST(SUM(spend) AS DECIMAL(12, 2)) FROM dbo.fact_ad_spend_daily) AS total_spend,
       (SELECT COUNT(*) FROM dbo.fact_signups)                            AS signup_rows;

-- Signups whose channel disagrees with the campaign's channel. Expect 0
SELECT COUNT(*) AS channel_mismatch
FROM dbo.fact_signups f
JOIN dbo.dim_campaign c ON c.campaign = f.campaign
WHERE f.channel_key <> c.channel_key;
GO


/* =====================================================================
   SECTION 4 - CAMPAIGN & CHANNEL METRICS     (Questions 2 and 3)
   KEY LESSON: aggregate each fact table to campaign level FIRST, then join.
   Joining daily spend rows straight to individual signups repeats every spend
   row once per signup (fan-out) and massively inflates spend.
   ===================================================================== */

-- 4a. Base view: raw (unrounded) totals per campaign. All ratio views are built on this.
CREATE OR ALTER VIEW dbo.vw_campaign_base AS
WITH spend AS (
    SELECT campaign,
           SUM(spend)       AS total_spend,
           SUM(impressions) AS impressions,
           SUM(clicks)      AS clicks,
           COUNT(*)         AS days_with_spend,
           MIN(spend_date)  AS first_spend_day,
           MAX(spend_date)  AS last_spend_day
    FROM dbo.fact_ad_spend_daily
    GROUP BY campaign
),
outcomes AS (
    SELECT campaign,
           COUNT(*)                                            AS signups,
           SUM(is_paying)                                      AS paying_subs,
           SUM(revenue)                                        AS revenue_90d,
           SUM(CASE WHEN [plan] = 'annual' THEN 1 ELSE 0 END)    AS annual_subs,
           AVG(CAST(days_to_subscribe AS FLOAT))               AS avg_days_to_subscribe
    FROM dbo.fact_signups
    WHERE campaign IS NOT NULL
    GROUP BY campaign
)
SELECT c.channel_key, c.channel_name, c.campaign,
       s.total_spend, s.impressions, s.clicks, s.days_with_spend, s.first_spend_day, s.last_spend_day,
       o.signups, o.paying_subs, o.revenue_90d, o.annual_subs, o.avg_days_to_subscribe
FROM dbo.dim_campaign c
JOIN spend    s ON s.campaign = c.campaign
JOIN outcomes o ON o.campaign = c.campaign;
GO

-- 4b. THE campaign metrics table (this is your main deliverable)
CREATE OR ALTER VIEW dbo.vw_campaign_metrics AS
SELECT
    channel_key,
    campaign,
    -- delivery
    CAST(total_spend AS DECIMAL(12,2))                                             AS spend,
    impressions,
    clicks,
    CAST(100.0 * clicks / impressions AS DECIMAL(6,2))                             AS ctr_pct,
    CAST(CAST(total_spend AS FLOAT) / NULLIF(clicks, 0) AS DECIMAL(10,2))          AS cpc,
    CAST(CAST(total_spend AS FLOAT) / impressions * 1000 AS DECIMAL(10,2))         AS cpm,
    -- acquisition
    signups,
    CAST(100.0 * signups / NULLIF(clicks, 0) AS DECIMAL(6,1))                      AS signups_per_100_clicks,
    CAST(CAST(total_spend AS FLOAT) / signups AS DECIMAL(10,2))                    AS cost_per_signup,
    -- monetisation
    paying_subs,
    CAST(100.0 * paying_subs / signups AS DECIMAL(5,1))                            AS signup_to_paid_pct,
    CAST(CAST(total_spend AS FLOAT) / NULLIF(paying_subs, 0) AS DECIMAL(10,2))     AS cost_per_paying_sub,
    CAST(revenue_90d AS DECIMAL(12,2))                                             AS revenue_90d,
    CAST(CAST(revenue_90d AS FLOAT) / total_spend AS DECIMAL(8,2))                 AS roas_90d,
    CAST(revenue_90d - total_spend AS DECIMAL(12,2))                               AS net_return_90d,
    CAST(CAST(revenue_90d AS FLOAT) / signups AS DECIMAL(8,2))                     AS revenue_per_signup,
    CAST(CAST(revenue_90d AS FLOAT) / NULLIF(paying_subs, 0) AS DECIMAL(8,2))      AS revenue_per_paying_sub,
    CAST(100.0 * annual_subs / NULLIF(paying_subs, 0) AS DECIMAL(5,1))             AS annual_plan_share_pct,
    CAST(avg_days_to_subscribe AS DECIMAL(5,1))                                    AS avg_days_to_subscribe,
    -- where the money goes vs what it returns
    CAST(100.0 * total_spend  / SUM(total_spend)  OVER () AS DECIMAL(5,1))         AS share_of_spend_pct,
    CAST(100.0 * paying_subs  / SUM(paying_subs)  OVER () AS DECIMAL(5,1))         AS share_of_paying_subs_pct,
    CAST(100.0 * revenue_90d  / SUM(revenue_90d)  OVER () AS DECIMAL(5,1))         AS share_of_revenue_pct,
    -- run dates
    days_with_spend,
    first_spend_day,
    last_spend_day
FROM dbo.vw_campaign_base;
GO

SELECT * FROM dbo.vw_campaign_metrics ORDER BY roas_90d DESC;

-- 4c. Reconciliation: joined totals must equal cleaned source totals (catches fan-out bugs)
--     Expect identical pairs: 124886.22 / 124886.22  and  14266 / 14266
SELECT (SELECT SUM(spend)   FROM dbo.vw_campaign_metrics)                     AS spend_in_metrics,
       (SELECT SUM(spend)   FROM dbo.fact_ad_spend_daily)                     AS spend_in_source,
       (SELECT SUM(signups) FROM dbo.vw_campaign_metrics)                     AS signups_in_metrics,
       (SELECT COUNT(*)     FROM dbo.fact_signups WHERE campaign IS NOT NULL) AS signups_in_source;
GO

-- 4d. Channel-level rollup (for the CMO slide)
CREATE OR ALTER VIEW dbo.vw_channel_metrics AS
SELECT
    channel_key,
    CAST(SUM(total_spend) AS DECIMAL(12,2))                                                AS spend,
    SUM(impressions)                                                                       AS impressions,
    SUM(clicks)                                                                            AS clicks,
    CAST(100.0 * SUM(clicks) / SUM(impressions) AS DECIMAL(6,2))                           AS ctr_pct,
    CAST(CAST(SUM(total_spend) AS FLOAT) / SUM(clicks) AS DECIMAL(10,2))                   AS cpc,
    SUM(signups)                                                                           AS signups,
    SUM(paying_subs)                                                                       AS paying_subs,
    CAST(100.0 * SUM(paying_subs) / SUM(signups) AS DECIMAL(5,1))                          AS signup_to_paid_pct,
    CAST(CAST(SUM(total_spend) AS FLOAT) / SUM(signups) AS DECIMAL(10,2))                  AS cost_per_signup,
    CAST(CAST(SUM(total_spend) AS FLOAT) / NULLIF(SUM(paying_subs), 0) AS DECIMAL(10,2))   AS cost_per_paying_sub,
    CAST(SUM(revenue_90d) AS DECIMAL(12,2))                                                AS revenue_90d,
    CAST(CAST(SUM(revenue_90d) AS FLOAT) / SUM(total_spend) AS DECIMAL(8,2))               AS roas_90d
FROM dbo.vw_campaign_base
GROUP BY channel_key;
GO

SELECT * FROM dbo.vw_channel_metrics ORDER BY roas_90d DESC;
GO


/* =====================================================================
   SECTION 5 - PAID vs ORGANIC vs REFERRAL     (Question 4)
   Unpaid channels have no spend, so compare on conversion and revenue only.
   ===================================================================== */
CREATE OR ALTER VIEW dbo.vw_traffic_comparison AS
SELECT
    traffic_type,
    segment,
    COUNT(*)                                                                    AS signups,
    SUM(is_paying)                                                              AS paying_subs,
    CAST(100.0 * SUM(is_paying) / COUNT(*) AS DECIMAL(5,1))                     AS signup_to_paid_pct,
    CAST(SUM(revenue) / COUNT(*) AS DECIMAL(8,2))                               AS revenue_per_signup,
    CAST(100.0 * SUM(CASE WHEN [plan] = 'annual' THEN 1 ELSE 0 END)
               / NULLIF(SUM(is_paying), 0) AS DECIMAL(5,1))                     AS annual_plan_share_pct,
    CAST(AVG(CAST(days_to_subscribe AS FLOAT)) AS DECIMAL(5,1))                 AS avg_days_to_subscribe
FROM dbo.fact_signups
GROUP BY traffic_type, segment
UNION ALL
SELECT
    'paid', 'ALL PAID (pooled)',
    COUNT(*), SUM(is_paying),
    CAST(100.0 * SUM(is_paying) / COUNT(*) AS DECIMAL(5,1)),
    CAST(SUM(revenue) / COUNT(*) AS DECIMAL(8,2)),
    CAST(100.0 * SUM(CASE WHEN [plan] = 'annual' THEN 1 ELSE 0 END)
               / NULLIF(SUM(is_paying), 0) AS DECIMAL(5,1)),
    CAST(AVG(CAST(days_to_subscribe AS FLOAT)) AS DECIMAL(5,1))
FROM dbo.fact_signups
WHERE traffic_type = 'paid';
GO

-- Expect referral ~19.9%, organic ~9.8%, all paid ~11.9%
SELECT * FROM dbo.vw_traffic_comparison ORDER BY signup_to_paid_pct DESC;
GO


/* =====================================================================
   SECTION 6 - PERFORMANCE OVER TIME          (Question 5)
   ===================================================================== */

-- 6a. Monthly view. Builds a campaign x month GRID first, so a campaign that stopped
--     still shows a row with zero spend (instead of silently disappearing).
CREATE OR ALTER VIEW dbo.vw_monthly_campaign AS
WITH months AS (
    SELECT DISTINCT month_start, month_label, quarter_label FROM dbo.dim_date
),
grid AS (
    SELECT c.campaign, c.channel_key, m.month_start, m.month_label, m.quarter_label
    FROM dbo.dim_campaign c
    CROSS JOIN months m
),
ms AS (
    SELECT d.month_start, f.campaign,
           SUM(f.spend) AS spend, SUM(f.impressions) AS impressions, SUM(f.clicks) AS clicks
    FROM dbo.fact_ad_spend_daily f
    JOIN dbo.dim_date d ON d.date_key = f.spend_date
    GROUP BY d.month_start, f.campaign
),
mo AS (
    SELECT d.month_start, f.campaign,
           COUNT(*) AS signups, SUM(f.is_paying) AS paying_subs, SUM(f.revenue) AS revenue
    FROM dbo.fact_signups f
    JOIN dbo.dim_date d ON d.date_key = f.signup_date
    WHERE f.campaign IS NOT NULL
    GROUP BY d.month_start, f.campaign
)
SELECT
    g.month_start, g.month_label, g.quarter_label, g.channel_key, g.campaign,
    CAST(COALESCE(ms.spend, 0) AS DECIMAL(12,2))              AS spend,
    COALESCE(ms.impressions, 0)                               AS impressions,
    COALESCE(ms.clicks, 0)                                    AS clicks,
    COALESCE(mo.signups, 0)                                   AS signups,
    COALESCE(mo.paying_subs, 0)                               AS paying_subs,
    CAST(COALESCE(mo.revenue, 0) AS DECIMAL(12,2))            AS revenue_90d,
    CAST(ms.spend / NULLIF(mo.signups, 0)     AS DECIMAL(10,2)) AS cost_per_signup,
    CAST(ms.spend / NULLIF(mo.paying_subs, 0) AS DECIMAL(10,2)) AS cost_per_paying_sub,
    CAST(100.0 * mo.paying_subs / NULLIF(mo.signups, 0) AS DECIMAL(5,1)) AS signup_to_paid_pct,
    CAST(mo.revenue / NULLIF(ms.spend, 0)     AS DECIMAL(8,2))  AS roas_90d
FROM grid g
LEFT JOIN ms ON ms.month_start = g.month_start AND ms.campaign = g.campaign
LEFT JOIN mo ON mo.month_start = g.month_start AND mo.campaign = g.campaign;
GO

SELECT * FROM dbo.vw_monthly_campaign ORDER BY campaign, month_start;

-- 6b. Month-over-month change in cost per paying subscriber (window function)
SELECT
    campaign, month_label, cost_per_paying_sub,
    LAG(cost_per_paying_sub) OVER (PARTITION BY campaign ORDER BY month_start) AS prev_month,
    CAST(100.0 * (cost_per_paying_sub - LAG(cost_per_paying_sub) OVER (PARTITION BY campaign ORDER BY month_start))
         / NULLIF(LAG(cost_per_paying_sub) OVER (PARTITION BY campaign ORDER BY month_start), 0)
         AS DECIMAL(7,1)) AS mom_change_pct
FROM dbo.vw_monthly_campaign
ORDER BY campaign, month_start;
GO

-- 6c. Q1 vs Q2: did each campaign get better or worse?
--     (display_network Q2 is partial: it stopped on 14 May)
CREATE OR ALTER VIEW dbo.vw_quarterly_comparison AS
SELECT
    campaign,
    q1_spend, q2_spend, q1_signups, q2_signups, q1_subs, q2_subs,
    CAST(100.0 * q1_subs / NULLIF(q1_signups, 0) AS DECIMAL(5,1))            AS q1_signup_to_paid_pct,
    CAST(100.0 * q2_subs / NULLIF(q2_signups, 0) AS DECIMAL(5,1))            AS q2_signup_to_paid_pct,
    CAST(q1_spend / NULLIF(q1_subs, 0) AS DECIMAL(10,2))                     AS q1_cost_per_paying_sub,
    CAST(q2_spend / NULLIF(q2_subs, 0) AS DECIMAL(10,2))                     AS q2_cost_per_paying_sub,
    CAST(100.0 * (q2_spend / NULLIF(q2_subs, 0) - q1_spend / NULLIF(q1_subs, 0))
               / NULLIF(q1_spend / NULLIF(q1_subs, 0), 0) AS DECIMAL(7,1))   AS cost_per_sub_change_pct
FROM (
    SELECT campaign,
           SUM(CASE WHEN quarter_label = 'Q1' THEN spend       END) AS q1_spend,
           SUM(CASE WHEN quarter_label = 'Q2' THEN spend       END) AS q2_spend,
           SUM(CASE WHEN quarter_label = 'Q1' THEN signups     END) AS q1_signups,
           SUM(CASE WHEN quarter_label = 'Q2' THEN signups     END) AS q2_signups,
           SUM(CASE WHEN quarter_label = 'Q1' THEN paying_subs END) AS q1_subs,
           SUM(CASE WHEN quarter_label = 'Q2' THEN paying_subs END) AS q2_subs
    FROM dbo.vw_monthly_campaign
    GROUP BY campaign
) AS q;
GO

SELECT * FROM dbo.vw_quarterly_comparison ORDER BY campaign;
GO

-- 6d. Campaigns that STOPPED running. Expect display_network: last spend 2025-05-14, 47 days before data end
CREATE OR ALTER VIEW dbo.vw_campaign_status AS
SELECT
    campaign, channel_key, first_spend_day, last_spend_day, days_with_spend,
    (SELECT MAX(spend_date) FROM dbo.fact_ad_spend_daily)                               AS data_end,
    DATEDIFF(DAY, last_spend_day, (SELECT MAX(spend_date) FROM dbo.fact_ad_spend_daily)) AS days_without_spend_at_end,
    CASE WHEN last_spend_day < (SELECT MAX(spend_date) FROM dbo.fact_ad_spend_daily)
         THEN 'STOPPED' ELSE 'running' END                                              AS status
FROM dbo.vw_campaign_base;
GO

SELECT * FROM dbo.vw_campaign_status ORDER BY status DESC, campaign;
GO


/* =====================================================================
   SECTION 7 - WHICH METRIC RANKS CHANNELS?    (Question 6)
   ===================================================================== */
CREATE OR ALTER VIEW dbo.vw_metric_rankings AS
SELECT
    campaign,
    cost_per_signup,
    RANK() OVER (ORDER BY cost_per_signup)                       AS rank_by_cost_per_signup,
    signup_to_paid_pct,
    RANK() OVER (ORDER BY signup_to_paid_pct DESC)               AS rank_by_signup_to_paid,
    cost_per_paying_sub,
    RANK() OVER (ORDER BY cost_per_paying_sub)                   AS rank_by_cost_per_paying_sub,
    roas_90d,
    RANK() OVER (ORDER BY roas_90d DESC)                         AS rank_by_roas,
    RANK() OVER (ORDER BY cost_per_paying_sub)
      - RANK() OVER (ORDER BY cost_per_signup)                   AS rank_shift   -- positive = looks worse once payers are counted
FROM dbo.vw_campaign_metrics;
GO

SELECT * FROM dbo.vw_metric_rankings ORDER BY rank_by_roas;

-- 7b. The headline pair: near-identical cost per signup, very different cost per paying subscriber
--     Expect prospecting_video ~5.1x more expensive per payer than retargeting
SELECT
    campaign, cost_per_signup, signup_to_paid_pct, cost_per_paying_sub,
    CAST(cost_per_paying_sub /
         (SELECT cost_per_paying_sub FROM dbo.vw_campaign_metrics WHERE campaign = 'retargeting')
         AS DECIMAL(6,1)) AS x_vs_retargeting
FROM dbo.vw_campaign_metrics
WHERE campaign IN ('prospecting_video', 'retargeting');

-- 7c. Rule-based verdict. The thresholds are ASSUMPTIONS: state them in the README.
--     ROAS >= 1.0 means the ad cost is earned back inside 90 days on revenue alone
--     (revenue is not profit; margin data is not available).
SELECT
    campaign, roas_90d, cost_per_paying_sub, signup_to_paid_pct, share_of_spend_pct,
    CASE WHEN roas_90d >= 1.0 THEN 'SCALE (cautiously)'
         WHEN roas_90d >= 0.4 THEN 'OPTIMISE / HOLD'
         ELSE                      'CUT or RE-TEST' END AS suggested_action
FROM dbo.vw_campaign_metrics
ORDER BY roas_90d DESC;
GO


/* =====================================================================
   SECTION 8 - H2 BUDGET SCENARIOS            (Question 7)

   Model rules (state them in the README):
   - H2 budget = H1 budget x budget_multiplier (default 1.0 = same total spend).
   - Spend up to a campaign's H1 level converts at its H1 cost per paying subscriber.
   - Extra spend ABOVE the H1 level converts at only efficiency_on_extra of that rate
     (diminishing returns). We test 0.5 / 0.7 / 1.0 as a sensitivity check.
   - Revenue per paying sub is held at each campaign's H1 average.
   Limits: linear model, no saturation curve, no interaction between campaigns
   (cutting prospecting may shrink the retargeting audience - not modelled).
   ===================================================================== */

CREATE TABLE dbo.model_params (
    param_name  VARCHAR(50)   NOT NULL CONSTRAINT PK_model_params PRIMARY KEY,
    param_value DECIMAL(10,4) NOT NULL,
    notes       VARCHAR(200)  NULL
);
GO
INSERT INTO dbo.model_params (param_name, param_value, notes)
VALUES ('budget_multiplier', 1.0, 'H2 total budget as a multiple of H1 total spend');
GO

CREATE TABLE dbo.budget_proposal (
    scenario       VARCHAR(30)  NOT NULL,
    campaign       VARCHAR(50)  NOT NULL,
    proposed_share DECIMAL(6,4) NOT NULL,      -- share of the H2 budget, each scenario must sum to 1
    CONSTRAINT PK_budget_proposal PRIMARY KEY (scenario, campaign),
    CONSTRAINT FK_budget_campaign FOREIGN KEY (campaign) REFERENCES dbo.dim_campaign (campaign)
);
GO

-- PLACEHOLDER scenarios: replace or edit with YOUR reasoning. (H1_repeat is added automatically.)
INSERT INTO dbo.budget_proposal (scenario, campaign, proposed_share) VALUES
 ('A_trim_display',   'brand_search',      0.10), ('A_trim_display',   'retargeting',       0.13),
 ('A_trim_display',   'generic_search',    0.29), ('A_trim_display',   'finance_blogs',     0.13),
 ('A_trim_display',   'prospecting_video', 0.35), ('A_trim_display',   'display_network',   0.00),

 ('B_balanced',       'brand_search',      0.12), ('B_balanced',       'retargeting',       0.18),
 ('B_balanced',       'generic_search',    0.30), ('B_balanced',       'finance_blogs',     0.15),
 ('B_balanced',       'prospecting_video', 0.25), ('B_balanced',       'display_network',   0.00),

 ('C_efficiency_led', 'brand_search',      0.12), ('C_efficiency_led', 'retargeting',       0.22),
 ('C_efficiency_led', 'generic_search',    0.36), ('C_efficiency_led', 'finance_blogs',     0.15),
 ('C_efficiency_led', 'prospecting_video', 0.15), ('C_efficiency_led', 'display_network',   0.00);
GO

-- 8a. Each scenario must have 6 campaigns and shares summing to 1.0. Expect 6 | 1.0000 for every row
SELECT scenario, COUNT(*) AS n_campaigns, SUM(proposed_share) AS total_share
FROM dbo.budget_proposal
GROUP BY scenario;
GO

-- 8b. Projection: scenario x campaign x efficiency assumption
CREATE OR ALTER VIEW dbo.vw_budget_projection AS
WITH tot AS (
    SELECT CAST(SUM(total_spend) AS FLOAT) AS h1_total FROM dbo.vw_campaign_base
),
prm AS (
    SELECT CAST(param_value AS FLOAT) AS budget_multiplier
    FROM dbo.model_params WHERE param_name = 'budget_multiplier'
),
eff AS (
    SELECT efficiency_on_extra FROM (VALUES (0.5), (0.7), (1.0)) AS v(efficiency_on_extra)
),
shares AS (
    SELECT scenario, campaign, CAST(proposed_share AS FLOAT) AS share
    FROM dbo.budget_proposal
    UNION ALL
    SELECT 'H1_repeat', campaign, CAST(total_spend AS FLOAT) / (SELECT h1_total FROM tot)
    FROM dbo.vw_campaign_base
),
calc AS (
    SELECT sh.scenario, sh.campaign, e.efficiency_on_extra,
           CAST(b.total_spend AS FLOAT)                        AS h1_spend,
           sh.share * t.h1_total * p.budget_multiplier         AS h2_spend,
           CAST(b.total_spend  AS FLOAT) / b.paying_subs       AS cost_per_sub,
           CAST(b.revenue_90d  AS FLOAT) / b.paying_subs       AS revenue_per_sub
    FROM shares sh
    JOIN dbo.vw_campaign_base b ON b.campaign = sh.campaign
    CROSS JOIN tot t
    CROSS JOIN prm p
    CROSS JOIN eff e
)
SELECT c.scenario, c.campaign, c.efficiency_on_extra, c.h1_spend, c.h2_spend,
       x.projected_paying_subs,
       x.projected_paying_subs * c.revenue_per_sub AS projected_revenue_90d
FROM calc c
CROSS APPLY (
    SELECT CASE WHEN c.h2_spend <= c.h1_spend
                THEN c.h2_spend / c.cost_per_sub
                ELSE c.h1_spend / c.cost_per_sub
                     + (c.h2_spend - c.h1_spend) / c.cost_per_sub * c.efficiency_on_extra
           END AS projected_paying_subs
) AS x;
GO

-- 8c. Scenario summary. THIS is the table that backs your recommendation.
--     With the placeholder shares and budget_multiplier = 1.0 you should see, at efficiency 0.7:
--     H1_repeat ~1,698 subs @ $73.55 | A ~1,888 | B ~2,077 | C ~2,174 @ ~$57.4
SELECT
    scenario,
    efficiency_on_extra,
    CAST(SUM(h2_spend)              AS DECIMAL(12,0)) AS h2_spend,
    CAST(SUM(projected_paying_subs) AS DECIMAL(10,0)) AS projected_paying_subs,
    CAST(SUM(h2_spend) / SUM(projected_paying_subs) AS DECIMAL(10,2)) AS blended_cost_per_sub,
    CAST(SUM(projected_revenue_90d) AS DECIMAL(12,0)) AS projected_revenue_90d,
    CAST(SUM(projected_revenue_90d) / SUM(h2_spend) AS DECIMAL(6,3)) AS projected_roas
FROM dbo.vw_budget_projection
GROUP BY scenario, efficiency_on_extra
ORDER BY efficiency_on_extra, scenario;

-- 8d. Allocation detail at the middle assumption: H1 share vs proposed share, in dollars
SELECT scenario, campaign,
       CAST(h1_spend AS DECIMAL(12,0))              AS h1_spend,
       CAST(h2_spend AS DECIMAL(12,0))              AS h2_spend,
       CAST(h2_spend - h1_spend AS DECIMAL(12,0))   AS change_usd,
       CAST(projected_paying_subs AS DECIMAL(10,0)) AS projected_paying_subs
FROM dbo.vw_budget_projection
WHERE efficiency_on_extra = 0.7
ORDER BY scenario, campaign;
GO


/* =====================================================================
   SECTION 9 - EXPORT THE DELIVERABLES
   In VS Code (mssql): run the query, then use the "Save as CSV" icon in the results pane.
   In SSMS: right-click the result grid > Save Results As...
   Save these into /outputs in your repo:
     campaign_metrics.csv       <- SELECT * FROM dbo.vw_campaign_metrics ORDER BY roas_90d DESC;
     channel_metrics.csv        <- SELECT * FROM dbo.vw_channel_metrics;
     traffic_comparison.csv     <- SELECT * FROM dbo.vw_traffic_comparison;
     monthly_campaign.csv       <- SELECT * FROM dbo.vw_monthly_campaign ORDER BY campaign, month_start;
     metric_rankings.csv        <- SELECT * FROM dbo.vw_metric_rankings;
     budget_scenarios.csv       <- the query in 8c
   Power BI: connect to the SQL Server database and import the dim_* / fact_* tables plus
   the vw_* views. Relationships: fact_ad_spend_daily[campaign] -> dim_campaign[campaign],
   fact_signups[campaign] -> dim_campaign[campaign], both date columns -> dim_date[date_key].
   ===================================================================== */
