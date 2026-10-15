-- Step 6: Reporting views on the daily snapshots.
-- Example: SELECT * FROM gold.v_portfolio_health WHERE snapshot_date = DATE '2026-09-15';
BEGIN;

-- Portfolio Health Dashboard: portfolio totals per date.
CREATE OR REPLACE VIEW gold.v_portfolio_health AS
SELECT snapshot_date,
       count(*) AS customer_count,
       count(*) FILTER (WHERE financial_data_status = 'PARTIAL') AS partial_customer_count,
       count(*) FILTER (WHERE risk_assessment_id IS NULL) AS unassessed_customer_count,
       sum(total_account_balance) AS total_account_balance,
       sum(total_outstanding_loans) AS total_outstanding_loans,
       sum(total_overdraft_balance) AS total_overdraft_balance,
       sum(total_debt) AS total_debt,
       -- Show exposure and profit totals only when all values are known.
       CASE WHEN count(total_credit_exposure) = count(*) THEN sum(total_credit_exposure) END AS total_credit_exposure,
       CASE WHEN count(net_profit) = count(*) THEN sum(net_profit) END AS total_net_profit
FROM gold.fact_customer_snapshot
GROUP BY snapshot_date;

-- Portfolio Health Dashboard: customers and debt per risk rating.
CREATE OR REPLACE VIEW gold.v_portfolio_risk_distribution AS
SELECT snapshot_date,
       COALESCE(risk_rating, 'UNASSESSED') AS risk_rating,
       count(*) AS customer_count,
       sum(total_debt) AS total_debt
FROM gold.fact_customer_snapshot
GROUP BY snapshot_date, COALESCE(risk_rating, 'UNASSESSED');

-- Customer Risk Profile Report: each customer's risk history with reasons.
CREATE OR REPLACE VIEW gold.v_customer_risk_profile AS
SELECT s.snapshot_date, s.customer_id, d.customer_full_name, d.customer_status,
       s.total_account_balance, s.total_outstanding_loans, s.total_overdraft_balance, s.total_debt,
       s.total_credit_exposure, s.net_profit, s.financial_data_status,
       s.kyc_status, s.aml_risk_level, s.risk_score, s.risk_rating,
       r.kyc_risk_rating, r.aml_risk_rating, r.assessment_reason,
       r.assessment_rule, r.assessment_rule_version
FROM gold.fact_customer_snapshot s
JOIN gold.dim_customer d ON d.customer_key = s.customer_key
LEFT JOIN silver.customer_risk_assessment r ON r.risk_assessment_id = s.risk_assessment_id;

COMMIT;
