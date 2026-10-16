-- Step 1: Load accounts, loans and transactions from Bronze into Silver.
-- Run: CALL silver.load_financials(DATE '2026-09-15');
BEGIN;

-- Load one reporting date of financial data into Silver.
CREATE OR REPLACE PROCEDURE silver.load_financials(p_date date)
LANGUAGE plpgsql AS $$
DECLARE
  v_run text := 'FIN-' || p_date;
BEGIN
  -- Stop if Silver already has a later date.
  IF EXISTS (SELECT 1 FROM silver.banking_account WHERE as_of_date > p_date)
     OR EXISTS (SELECT 1 FROM silver.loan WHERE as_of_date > p_date) THEN
    RAISE EXCEPTION 'Silver already holds data after %; earlier dates cannot be reloaded', p_date;
  END IF;

  -- Clear old issues from the last run of this date.
  DELETE FROM silver.data_quality_issue WHERE validation_run_id = v_run;

  -- Get the latest version of each account and its matched customer_id.
  DROP TABLE IF EXISTS tmp_account;
  CREATE TEMP TABLE tmp_account ON COMMIT DROP AS
  SELECT DISTINCT ON (r.source_system_id, r.source_account_reference)
         r.*, m.customer_id
  FROM bronze.raw_banking_account_snapshot r
  JOIN silver.ingestion_batch b ON b.batch_id = r.batch_id AND b.load_status = 'SUCCEEDED'
  LEFT JOIN silver.source_customer_record s
    ON s.source_system_id = r.source_system_id
   AND s.source_customer_reference = r.source_customer_reference
   AND s.is_current_version
  LEFT JOIN silver.customer_source_match m
    ON m.source_customer_record_id = s.source_customer_record_id
   AND m.is_current_match AND m.match_status = 'ACCEPTED'
  WHERE r.as_of_date <= p_date
  ORDER BY r.source_system_id, r.source_account_reference, r.source_record_version DESC;

  -- Get the latest version of each loan and its matched customer_id.
  DROP TABLE IF EXISTS tmp_loan;
  CREATE TEMP TABLE tmp_loan ON COMMIT DROP AS
  SELECT DISTINCT ON (r.source_system_id, r.source_loan_reference)
         r.*, m.customer_id
  FROM bronze.raw_loan_snapshot r
  JOIN silver.ingestion_batch b ON b.batch_id = r.batch_id AND b.load_status = 'SUCCEEDED'
  LEFT JOIN silver.source_customer_record s
    ON s.source_system_id = r.source_system_id
   AND s.source_customer_reference = r.source_customer_reference
   AND s.is_current_version
  LEFT JOIN silver.customer_source_match m
    ON m.source_customer_record_id = s.source_customer_record_id
   AND m.is_current_match AND m.match_status = 'ACCEPTED'
  WHERE r.as_of_date <= p_date
  ORDER BY r.source_system_id, r.source_loan_reference, r.source_record_version DESC;

  -- Log rows that cannot be loaded (no customer match, non-AUD, delete).
  INSERT INTO silver.data_quality_issue (
    data_quality_issue_id, validation_run_id, data_layer, entity_name, record_reference,
    record_version_reference, rule_name, rule_version, issue_type, issue_description,
    severity, detected_at, issue_status)
  SELECT left('FIN-' || md5(v_run || x.entity || x.ref), 50), v_run, 'SILVER', x.entity, x.ref,
         x.version::text, 'financial_load_validation', '1', 'FINANCIAL_LOAD', x.problem,
         'ERROR', now(), 'OPEN'
  FROM (
    SELECT 'banking_account' AS entity, source_account_reference AS ref, source_record_version AS version,
           CASE WHEN customer_id IS NULL THEN 'NO_ACCEPTED_CUSTOMER_MATCH'
                WHEN currency_code <> 'AUD' THEN 'NON_AUD_CURRENCY'
                WHEN operation_type = 'D' THEN 'DELETE_NEEDS_REVIEW' END AS problem
    FROM tmp_account
    UNION ALL
    SELECT 'loan', source_loan_reference, source_record_version,
           CASE WHEN customer_id IS NULL THEN 'NO_ACCEPTED_CUSTOMER_MATCH'
                WHEN operation_type = 'D' THEN 'DELETE_NEEDS_REVIEW' END
    FROM tmp_loan
  ) x
  WHERE x.problem IS NOT NULL;

  -- Insert or update valid accounts.
  INSERT INTO silver.banking_account AS t (
    account_id, customer_id, source_system_id, source_account_reference, account_type,
    account_status, current_balance, opened_date, closed_date, source_last_updated_at,
    as_of_date, daily_income, daily_cost, credit_exposure)
  SELECT 'ACC-' || md5(source_system_id || '|' || source_account_reference), customer_id,
         source_system_id, source_account_reference, account_type, account_status,
         current_balance, opened_date, closed_date, source_last_updated_at, as_of_date,
         daily_income, daily_cost, credit_exposure
  FROM tmp_account
  WHERE customer_id IS NOT NULL AND currency_code = 'AUD' AND operation_type <> 'D'
  ON CONFLICT (account_id) DO UPDATE SET
    customer_id = EXCLUDED.customer_id, account_type = EXCLUDED.account_type,
    account_status = EXCLUDED.account_status, current_balance = EXCLUDED.current_balance,
    opened_date = EXCLUDED.opened_date, closed_date = EXCLUDED.closed_date,
    source_last_updated_at = EXCLUDED.source_last_updated_at, as_of_date = EXCLUDED.as_of_date,
    daily_income = EXCLUDED.daily_income, daily_cost = EXCLUDED.daily_cost,
    credit_exposure = EXCLUDED.credit_exposure
  WHERE (t.*) IS DISTINCT FROM (EXCLUDED.*);

  -- Insert or update valid loans (loans are treated as AUD).
  INSERT INTO silver.loan AS t (
    loan_id, customer_id, source_system_id, source_loan_reference, loan_type, loan_status,
    original_amount, outstanding_balance, interest_rate, start_date, maturity_date,
    source_last_updated_at, as_of_date, daily_income, daily_cost, credit_exposure)
  SELECT 'LOAN-' || md5(source_system_id || '|' || source_loan_reference), customer_id,
         source_system_id, source_loan_reference, loan_type, loan_status, original_amount,
         outstanding_balance, interest_rate, start_date, maturity_date,
         source_last_updated_at, as_of_date, daily_income, daily_cost, credit_exposure
  FROM tmp_loan
  WHERE customer_id IS NOT NULL AND operation_type <> 'D'
  ON CONFLICT (loan_id) DO UPDATE SET
    customer_id = EXCLUDED.customer_id, loan_type = EXCLUDED.loan_type,
    loan_status = EXCLUDED.loan_status, original_amount = EXCLUDED.original_amount,
    outstanding_balance = EXCLUDED.outstanding_balance, interest_rate = EXCLUDED.interest_rate,
    start_date = EXCLUDED.start_date, maturity_date = EXCLUDED.maturity_date,
    source_last_updated_at = EXCLUDED.source_last_updated_at, as_of_date = EXCLUDED.as_of_date,
    daily_income = EXCLUDED.daily_income, daily_cost = EXCLUDED.daily_cost,
    credit_exposure = EXCLUDED.credit_exposure
  WHERE (t.*) IS DISTINCT FROM (EXCLUDED.*);

  -- Insert new transactions for accounts already in Silver.
  INSERT INTO silver.account_transaction (
    transaction_id, account_id, source_system_id, source_transaction_reference,
    transaction_date, transaction_type, transaction_amount, transaction_status)
  SELECT 'TXN-' || md5(r.source_system_id || '|' || r.source_transaction_reference),
         a.account_id, r.source_system_id, r.source_transaction_reference,
         r.transaction_date, r.transaction_type, r.transaction_amount, r.transaction_status
  FROM bronze.raw_account_transaction r
  JOIN silver.ingestion_batch b ON b.batch_id = r.batch_id AND b.load_status = 'SUCCEEDED'
  JOIN silver.banking_account a
    ON a.source_system_id = r.source_system_id
   AND a.source_account_reference = r.source_account_reference
  WHERE r.transaction_date < p_date + 1
  ON CONFLICT (transaction_id) DO NOTHING;

  -- Mark that the load for this date has run.
  INSERT INTO silver.data_lineage_record (
    lineage_id, transformation_run_id, source_layer, source_entity_name,
    source_record_reference, source_version_reference, source_record_snapshot,
    target_layer, target_entity_name, target_record_reference, target_version_reference,
    target_record_snapshot, transformation_name, transformation_version, transformation_timestamp)
  VALUES (v_run, v_run, 'BRONZE', 'financial_products', p_date::text, p_date::text,
          '{}', 'SILVER', 'financial_products', p_date::text, p_date::text,
          '{}', 'load_financials', '1', now())
  ON CONFLICT (lineage_id) DO UPDATE SET transformation_timestamp = EXCLUDED.transformation_timestamp;
END;
$$;

COMMIT;
