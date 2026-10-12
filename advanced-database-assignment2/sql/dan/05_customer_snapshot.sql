-- Step 5: publish the daily customer snapshot (FACT_CUSTOMER_SNAPSHOT).
-- Install: run this file once. Run: CALL gold.publish_snapshot(DATE '2026-09-15', '<rules json>');
-- Correct a published date: CALL gold.publish_snapshot(DATE '2026-09-15', '<rules json>', true);
-- Run after steps 1 and 2 and Member5's KYC/AML loading.
BEGIN;

CREATE OR REPLACE PROCEDURE gold.publish_snapshot(
  p_date date, p_rules jsonb, p_allow_correction boolean DEFAULT false)
LANGUAGE plpgsql AS $$
BEGIN
  -- Create (or reuse) the risk assessments for this date. The whole procedure runs in one
  -- transaction, so a later failure also rolls these back.
  CALL silver.assess_customer_risk(p_date, p_rules);

  -- Stop if a customer with an account or loan has no dimension version valid at the end of
  -- p_date; that customer would otherwise be missing from the snapshot.
  IF EXISTS (
    SELECT 1 FROM silver.customer_master c
    WHERE (EXISTS (SELECT 1 FROM silver.banking_account a WHERE a.customer_id = c.customer_id)
           OR EXISTS (SELECT 1 FROM silver.loan l WHERE l.customer_id = c.customer_id))
      AND NOT EXISTS (SELECT 1 FROM gold.dim_customer d
                      WHERE d.customer_id = c.customer_id AND d.effective_from < p_date + 1
                        AND (d.effective_to IS NULL OR d.effective_to >= p_date + 1))
  ) THEN
    RAISE EXCEPTION 'A customer with products has no dimension version on %; run gold.load_dim_customer()', p_date;
  END IF;

  -- Build the candidate snapshot in a temp table with the same structure as the fact table,
  -- so values have the same precision when compared with published rows.
  -- Each row combines the customer's financials, compliance status, the dimension version valid
  -- at the end of p_date (not today's version) and the latest assessment for p_date (NULL when
  -- the customer was not assessed). Placeholder customers with no products are skipped.
  DROP TABLE IF EXISTS tmp_snapshot;
  CREATE TEMP TABLE tmp_snapshot (LIKE gold.fact_customer_snapshot) ON COMMIT DROP;
  INSERT INTO tmp_snapshot
  SELECT 'SNAP-' || md5(f.customer_id || '|' || p_date) AS customer_snapshot_id,
         f.customer_id, d.customer_key, a.risk_assessment_id, p_date AS snapshot_date,
         f.total_account_balance, f.total_outstanding_loans, f.total_overdraft_balance,
         f.total_debt, f.banking_credit_exposure, f.lending_credit_exposure,
         f.total_credit_exposure, f.total_income, f.total_cost, f.net_profit,
         f.financial_data_status, a.risk_score, a.risk_rating,
         c.kyc_status, c.aml_risk_level, now()::timestamp AS calculated_at
  FROM gold.customer_financials(p_date) f
  JOIN gold.customer_compliance(p_date) c ON c.customer_id = f.customer_id
  JOIN gold.dim_customer d
    ON d.customer_id = f.customer_id
   AND d.effective_from < p_date + 1
   AND (d.effective_to IS NULL OR d.effective_to >= p_date + 1)
  LEFT JOIN (
    SELECT DISTINCT ON (x.customer_id) x.*
    FROM silver.customer_risk_assessment x
    WHERE x.assessment_date = p_date::timestamp
    ORDER BY x.customer_id, x.assessment_version DESC
  ) a ON a.customer_id = f.customer_id
  WHERE EXISTS (SELECT 1 FROM silver.banking_account b WHERE b.customer_id = f.customer_id)
     OR EXISTS (SELECT 1 FROM silver.loan l WHERE l.customer_id = f.customer_id);

  -- Stop if a published row for this date would change or disappear, unless p_allow_correction
  -- is true. A published row with no candidate makes to_jsonb(t) NULL, which counts as a change.
  -- calculated_at is ignored because it differs on every run.
  IF NOT p_allow_correction AND EXISTS (
    SELECT 1 FROM gold.fact_customer_snapshot f
    LEFT JOIN tmp_snapshot t ON t.customer_snapshot_id = f.customer_snapshot_id
    WHERE f.snapshot_date = p_date
      AND (to_jsonb(f) - 'calculated_at') IS DISTINCT FROM (to_jsonb(t) - 'calculated_at')
  ) THEN
    RAISE EXCEPTION 'Snapshot for % changed; rerun with p_allow_correction => true to correct it', p_date;
  END IF;

  -- Delete published rows for customers that no longer belong in this date's snapshot
  -- (e.g. their only account was corrected away). Only reached on a correction or no change.
  DELETE FROM gold.fact_customer_snapshot f
  WHERE f.snapshot_date = p_date
    AND NOT EXISTS (SELECT 1 FROM tmp_snapshot t WHERE t.customer_snapshot_id = f.customer_snapshot_id);

  -- Insert new rows, or update existing ones (upsert). Rows are only updated when a value
  -- other than calculated_at has changed, so an identical rerun keeps the original calculated_at.
  INSERT INTO gold.fact_customer_snapshot AS f
  SELECT * FROM tmp_snapshot
  ON CONFLICT (customer_snapshot_id) DO UPDATE SET
    customer_key = EXCLUDED.customer_key, risk_assessment_id = EXCLUDED.risk_assessment_id,
    total_account_balance = EXCLUDED.total_account_balance,
    total_outstanding_loans = EXCLUDED.total_outstanding_loans,
    total_overdraft_balance = EXCLUDED.total_overdraft_balance, total_debt = EXCLUDED.total_debt,
    banking_credit_exposure = EXCLUDED.banking_credit_exposure,
    lending_credit_exposure = EXCLUDED.lending_credit_exposure,
    total_credit_exposure = EXCLUDED.total_credit_exposure,
    total_income = EXCLUDED.total_income, total_cost = EXCLUDED.total_cost,
    net_profit = EXCLUDED.net_profit, financial_data_status = EXCLUDED.financial_data_status,
    risk_score = EXCLUDED.risk_score, risk_rating = EXCLUDED.risk_rating,
    kyc_status = EXCLUDED.kyc_status, aml_risk_level = EXCLUDED.aml_risk_level,
    calculated_at = EXCLUDED.calculated_at
  WHERE (to_jsonb(f) - 'calculated_at') IS DISTINCT FROM (to_jsonb(EXCLUDED) - 'calculated_at');
END;
$$;

COMMIT;
