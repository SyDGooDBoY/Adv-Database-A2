-- Step 7: Run Member4 for one reporting date (2026-09-15) and show the results.
-- Run after files 01-06. Safe to rerun: the same date gives the same result.

-- 7.1 Build customer history.
CALL gold.load_dim_customer();
SELECT customer_id, customer_full_name, customer_status, effective_from, current_flag FROM gold.dim_customer ORDER BY customer_id;

-- 7.2 Load accounts, loans and transactions into Silver and list data quality issues.
CALL silver.load_financials(DATE '2026-09-15');
SELECT entity_name, record_reference, issue_description, issue_status FROM silver.data_quality_issue WHERE validation_run_id = 'FIN-2026-09-15';

-- 7.3 LOAN-002 has no ACCEPTED match (Member2 sent it to manual review). Acknowledge it so aggregation can continue without that loan.
UPDATE silver.data_quality_issue SET issue_status = 'ACKNOWLEDGED', resolved_at = now()
WHERE validation_run_id = 'FIN-2026-09-15' AND issue_status = 'OPEN';

-- 7.4 Customer totals.
SELECT * FROM gold.customer_financials(DATE '2026-09-15');

-- 7.5 Assess risk and publish the daily snapshot. Demo rules until Member5 provides the agreed JSON.
CALL gold.publish_snapshot(DATE '2026-09-15', '{"rule_name":"demo_rules","rule_version":"1","rules":[
 {"kyc_status":"UNKNOWN","aml_risk_level":"UNKNOWN","exposure_min":0,"exposure_max":50000,"score":50,"rating":"MEDIUM","kyc_risk_rating":"UNKNOWN","aml_risk_rating":"UNKNOWN","reason":"No KYC/AML result yet; exposure below 50000"},
 {"kyc_status":"UNKNOWN","aml_risk_level":"UNKNOWN","exposure_min":50000,"exposure_max":null,"score":80,"rating":"HIGH","kyc_risk_rating":"UNKNOWN","aml_risk_rating":"UNKNOWN","reason":"No KYC/AML result yet; exposure 50000 or more"}]}');

-- 7.6 Reports.
SELECT * FROM gold.v_portfolio_health ORDER BY snapshot_date;
SELECT * FROM gold.v_portfolio_risk_distribution ORDER BY snapshot_date, risk_rating;
SELECT * FROM gold.v_customer_risk_profile ORDER BY customer_id, snapshot_date;
