-- Step 7: Run Member4 for two reporting dates (2026-09-01, then 2026-09-15) and show the results.
-- Run after files 01-06 and after Module 5. Safe to rerun: 7.0 clears only Member4 data, so the same dates give the same result.
-- Dates must run oldest first: Silver keeps only the latest date, Gold keeps one snapshot per date.

-- 7.0 Clear Member4 financial and snapshot data (empty on the first run).
TRUNCATE silver.account_transaction, silver.banking_account, silver.loan, gold.fact_customer_snapshot CASCADE;
DELETE FROM silver.customer_risk_assessment;
DELETE FROM silver.data_quality_issue WHERE validation_run_id LIKE 'FIN-%';

-- 7.1 Build customer history.
CALL gold.load_dim_customer();
SELECT customer_id, customer_full_name, customer_status, effective_from, current_flag FROM gold.dim_customer ORDER BY customer_id;

-- 7.2 Day 1 (1 Sep): load into Silver and list data quality issues.
CALL silver.load_financials(DATE '2026-09-01');
SELECT entity_name, record_reference, issue_description, issue_status FROM silver.data_quality_issue WHERE validation_run_id = 'FIN-2026-09-01';

-- 7.3 Day 1: acknowledge LOAN-002 (no ACCEPTED customer match).
UPDATE silver.data_quality_issue SET issue_status = 'ACKNOWLEDGED', resolved_at = now()
WHERE validation_run_id = 'FIN-2026-09-01' AND issue_status = 'OPEN';

-- 7.4 Day 1: customer totals.
SELECT * FROM gold.customer_financials(DATE '2026-09-01');

-- 7.5 Day 1: assess risk and publish the 1 Sep snapshot (must happen BEFORE loading 15 Sep).
CALL gold.publish_snapshot(DATE '2026-09-01', '{"rule_name":"demo_rules","rule_version":"2","rules":[
 {"kyc_status":"UNKNOWN","aml_risk_level":"UNKNOWN","exposure_min":0,"exposure_max":50000,"score":50,"rating":"MEDIUM","kyc_risk_rating":"UNKNOWN","aml_risk_rating":"UNKNOWN","reason":"No KYC/AML result yet; exposure below 50000"},
 {"kyc_status":"UNKNOWN","aml_risk_level":"UNKNOWN","exposure_min":50000,"exposure_max":null,"score":80,"rating":"HIGH","kyc_risk_rating":"UNKNOWN","aml_risk_rating":"UNKNOWN","reason":"No KYC/AML result yet; exposure 50000 or more"},
 {"kyc_status":"VERIFIED","aml_risk_level":"CLEAR","exposure_min":0,"exposure_max":null,"score":20,"rating":"LOW","kyc_risk_rating":"LOW","aml_risk_rating":"LOW","reason":"KYC verified; AML screening clear"},
 {"kyc_status":"VERIFIED","aml_risk_level":"POTENTIAL_MATCH","exposure_min":0,"exposure_max":null,"score":60,"rating":"MEDIUM","kyc_risk_rating":"LOW","aml_risk_rating":"MEDIUM","reason":"KYC verified; AML potential match"},
 {"kyc_status":"VERIFIED","aml_risk_level":"MEDIUM","exposure_min":0,"exposure_max":null,"score":60,"rating":"MEDIUM","kyc_risk_rating":"LOW","aml_risk_rating":"MEDIUM","reason":"KYC verified; open AML case rated MEDIUM"},
 {"kyc_status":"VERIFIED","aml_risk_level":"HIGH","exposure_min":0,"exposure_max":null,"score":90,"rating":"HIGH","kyc_risk_rating":"LOW","aml_risk_rating":"HIGH","reason":"KYC verified; open AML case rated HIGH"},
 {"kyc_status":"EXPIRED","aml_risk_level":"CLEAR","exposure_min":0,"exposure_max":null,"score":75,"rating":"HIGH","kyc_risk_rating":"HIGH","aml_risk_rating":"LOW","reason":"KYC expired; AML screening clear"},
 {"kyc_status":"MISSING_DOCUMENT","aml_risk_level":"CLEAR","exposure_min":0,"exposure_max":null,"score":75,"rating":"HIGH","kyc_risk_rating":"HIGH","aml_risk_rating":"LOW","reason":"KYC document missing; AML screening clear"}]}');

-- 7.6 Day 2 (15 Sep): load, acknowledge, check totals.
CALL silver.load_financials(DATE '2026-09-15');
SELECT entity_name, record_reference, issue_description, issue_status FROM silver.data_quality_issue WHERE validation_run_id = 'FIN-2026-09-15';
UPDATE silver.data_quality_issue SET issue_status = 'ACKNOWLEDGED', resolved_at = now()
WHERE validation_run_id = 'FIN-2026-09-15' AND issue_status = 'OPEN';
SELECT * FROM gold.customer_financials(DATE '2026-09-15');

-- 7.7 Day 2: publish the 15 Sep snapshot.
CALL gold.publish_snapshot(DATE '2026-09-15', '{"rule_name":"demo_rules","rule_version":"2","rules":[
 {"kyc_status":"UNKNOWN","aml_risk_level":"UNKNOWN","exposure_min":0,"exposure_max":50000,"score":50,"rating":"MEDIUM","kyc_risk_rating":"UNKNOWN","aml_risk_rating":"UNKNOWN","reason":"No KYC/AML result yet; exposure below 50000"},
 {"kyc_status":"UNKNOWN","aml_risk_level":"UNKNOWN","exposure_min":50000,"exposure_max":null,"score":80,"rating":"HIGH","kyc_risk_rating":"UNKNOWN","aml_risk_rating":"UNKNOWN","reason":"No KYC/AML result yet; exposure 50000 or more"},
 {"kyc_status":"VERIFIED","aml_risk_level":"CLEAR","exposure_min":0,"exposure_max":null,"score":20,"rating":"LOW","kyc_risk_rating":"LOW","aml_risk_rating":"LOW","reason":"KYC verified; AML screening clear"},
 {"kyc_status":"VERIFIED","aml_risk_level":"POTENTIAL_MATCH","exposure_min":0,"exposure_max":null,"score":60,"rating":"MEDIUM","kyc_risk_rating":"LOW","aml_risk_rating":"MEDIUM","reason":"KYC verified; AML potential match"},
 {"kyc_status":"VERIFIED","aml_risk_level":"MEDIUM","exposure_min":0,"exposure_max":null,"score":60,"rating":"MEDIUM","kyc_risk_rating":"LOW","aml_risk_rating":"MEDIUM","reason":"KYC verified; open AML case rated MEDIUM"},
 {"kyc_status":"VERIFIED","aml_risk_level":"HIGH","exposure_min":0,"exposure_max":null,"score":90,"rating":"HIGH","kyc_risk_rating":"LOW","aml_risk_rating":"HIGH","reason":"KYC verified; open AML case rated HIGH"},
 {"kyc_status":"EXPIRED","aml_risk_level":"CLEAR","exposure_min":0,"exposure_max":null,"score":75,"rating":"HIGH","kyc_risk_rating":"HIGH","aml_risk_rating":"LOW","reason":"KYC expired; AML screening clear"},
 {"kyc_status":"MISSING_DOCUMENT","aml_risk_level":"CLEAR","exposure_min":0,"exposure_max":null,"score":75,"rating":"HIGH","kyc_risk_rating":"HIGH","aml_risk_rating":"LOW","reason":"KYC document missing; AML screening clear"}]}');

-- 7.8 Reports (now two dates).
SELECT * FROM gold.v_portfolio_health ORDER BY snapshot_date;
SELECT * FROM gold.v_portfolio_risk_distribution ORDER BY snapshot_date, risk_rating;
SELECT * FROM gold.v_customer_risk_profile ORDER BY customer_id, snapshot_date;

-- 7.9 What changed between the two dates.
SELECT coalesce(a.customer_full_name, b.customer_full_name) AS customer,
       a.risk_rating AS rating_0901, b.risk_rating AS rating_0915,
       a.total_debt AS debt_0901, b.total_debt AS debt_0915, b.assessment_reason AS reason_0915
FROM (SELECT * FROM gold.v_customer_risk_profile WHERE snapshot_date = DATE '2026-09-01') a
FULL JOIN (SELECT * FROM gold.v_customer_risk_profile WHERE snapshot_date = DATE '2026-09-15') b USING (customer_id)
WHERE a.risk_rating IS DISTINCT FROM b.risk_rating OR a.total_debt IS DISTINCT FROM b.total_debt
ORDER BY 1;
