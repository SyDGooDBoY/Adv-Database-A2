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

-- 7.5 Day 1: score risk with the scorecard and publish the 1 Sep snapshot (must happen BEFORE loading 15 Sep).
-- Score = base 20 + KYC points + AML points (+ exposure points only when KYC and AML are both UNKNOWN), capped at 100.
-- Rating: below 50 LOW, 50-74 MEDIUM, 75 or more HIGH.
CALL gold.publish_snapshot(DATE '2026-09-01', '{"rule_name":"demo_scorecard","rule_version":"3","base_score":20,
 "kyc_points":{
  "VERIFIED":{"points":0,"rating":"LOW","reason":"KYC verified"},
  "EXPIRED":{"points":55,"rating":"HIGH","reason":"KYC expired"},
  "MISSING_DOCUMENT":{"points":55,"rating":"HIGH","reason":"KYC document missing"},
  "UNKNOWN":{"points":15,"rating":"UNKNOWN","reason":"No KYC/AML result yet"}},
 "aml_points":{
  "CLEAR":{"points":0,"rating":"LOW","reason":"AML screening clear"},
  "FALSE_POSITIVE":{"points":0,"rating":"LOW","reason":"AML match was a false positive"},
  "POTENTIAL_MATCH":{"points":40,"rating":"MEDIUM","reason":"AML potential match"},
  "LOW":{"points":20,"rating":"LOW","reason":"open AML case rated LOW"},
  "MEDIUM":{"points":40,"rating":"MEDIUM","reason":"open AML case rated MEDIUM"},
  "HIGH":{"points":70,"rating":"HIGH","reason":"open AML case rated HIGH"},
  "CRITICAL":{"points":80,"rating":"HIGH","reason":"open AML case rated CRITICAL"},
  "UNKNOWN":{"points":15,"rating":"UNKNOWN","reason":null}},
 "exposure_bands":[
  {"min":0,"max":50000,"points":0,"reason":"exposure below 50000"},
  {"min":50000,"max":null,"points":30,"reason":"exposure 50000 or more"}],
 "rating_bands":[
  {"min":0,"max":50,"rating":"LOW"},
  {"min":50,"max":75,"rating":"MEDIUM"},
  {"min":75,"max":null,"rating":"HIGH"}]}');

-- 7.6 Day 2 (15 Sep): load, acknowledge, check totals.
CALL silver.load_financials(DATE '2026-09-15');
SELECT entity_name, record_reference, issue_description, issue_status FROM silver.data_quality_issue WHERE validation_run_id = 'FIN-2026-09-15';
UPDATE silver.data_quality_issue SET issue_status = 'ACKNOWLEDGED', resolved_at = now()
WHERE validation_run_id = 'FIN-2026-09-15' AND issue_status = 'OPEN';
SELECT * FROM gold.customer_financials(DATE '2026-09-15');

-- 7.7 Day 2: publish the 15 Sep snapshot (same scorecard).
CALL gold.publish_snapshot(DATE '2026-09-15', '{"rule_name":"demo_scorecard","rule_version":"3","base_score":20,
 "kyc_points":{
  "VERIFIED":{"points":0,"rating":"LOW","reason":"KYC verified"},
  "EXPIRED":{"points":55,"rating":"HIGH","reason":"KYC expired"},
  "MISSING_DOCUMENT":{"points":55,"rating":"HIGH","reason":"KYC document missing"},
  "UNKNOWN":{"points":15,"rating":"UNKNOWN","reason":"No KYC/AML result yet"}},
 "aml_points":{
  "CLEAR":{"points":0,"rating":"LOW","reason":"AML screening clear"},
  "FALSE_POSITIVE":{"points":0,"rating":"LOW","reason":"AML match was a false positive"},
  "POTENTIAL_MATCH":{"points":40,"rating":"MEDIUM","reason":"AML potential match"},
  "LOW":{"points":20,"rating":"LOW","reason":"open AML case rated LOW"},
  "MEDIUM":{"points":40,"rating":"MEDIUM","reason":"open AML case rated MEDIUM"},
  "HIGH":{"points":70,"rating":"HIGH","reason":"open AML case rated HIGH"},
  "CRITICAL":{"points":80,"rating":"HIGH","reason":"open AML case rated CRITICAL"},
  "UNKNOWN":{"points":15,"rating":"UNKNOWN","reason":null}},
 "exposure_bands":[
  {"min":0,"max":50000,"points":0,"reason":"exposure below 50000"},
  {"min":50000,"max":null,"points":30,"reason":"exposure 50000 or more"}],
 "rating_bands":[
  {"min":0,"max":50,"rating":"LOW"},
  {"min":50,"max":75,"rating":"MEDIUM"},
  {"min":75,"max":null,"rating":"HIGH"}]}');

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
