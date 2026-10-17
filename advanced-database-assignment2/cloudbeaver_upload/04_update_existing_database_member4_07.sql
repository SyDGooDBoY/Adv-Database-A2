-- =============================================================================
-- CloudBeaver bundle 04: update an existing deployment for Member 4 file 07
-- Target: an existing database previously deployed with this project
--
-- The update is one atomic DO statement. It can be run with Execute statement
-- or as a full script. PostgreSQL commits the whole statement on success and
-- rolls it all back on error, so it cannot leave an open BEGIN transaction.
-- Member 5 must already be loaded.
-- =============================================================================

DO $member4_two_date_update$
DECLARE
  -- Build JSON with PostgreSQL functions so CloudBeaver does not interpret
  -- JSON colon characters as named bind parameters.
  v_rules jsonb := jsonb_build_object(
    'rule_name', 'demo_rules',
    'rule_version', '2',
    'rules', jsonb_build_array(
      jsonb_build_object(
        'kyc_status', 'UNKNOWN', 'aml_risk_level', 'UNKNOWN',
        'exposure_min', 0, 'exposure_max', 50000,
        'score', 50, 'rating', 'MEDIUM',
        'kyc_risk_rating', 'UNKNOWN', 'aml_risk_rating', 'UNKNOWN',
        'reason', 'No KYC/AML result yet; exposure below 50000'),
      jsonb_build_object(
        'kyc_status', 'UNKNOWN', 'aml_risk_level', 'UNKNOWN',
        'exposure_min', 50000, 'exposure_max', NULL,
        'score', 80, 'rating', 'HIGH',
        'kyc_risk_rating', 'UNKNOWN', 'aml_risk_rating', 'UNKNOWN',
        'reason', 'No KYC/AML result yet; exposure 50000 or more'),
      jsonb_build_object(
        'kyc_status', 'VERIFIED', 'aml_risk_level', 'CLEAR',
        'exposure_min', 0, 'exposure_max', NULL,
        'score', 20, 'rating', 'LOW',
        'kyc_risk_rating', 'LOW', 'aml_risk_rating', 'LOW',
        'reason', 'KYC verified; AML screening clear'),
      jsonb_build_object(
        'kyc_status', 'VERIFIED', 'aml_risk_level', 'POTENTIAL_MATCH',
        'exposure_min', 0, 'exposure_max', NULL,
        'score', 60, 'rating', 'MEDIUM',
        'kyc_risk_rating', 'LOW', 'aml_risk_rating', 'MEDIUM',
        'reason', 'KYC verified; AML potential match'),
      jsonb_build_object(
        'kyc_status', 'VERIFIED', 'aml_risk_level', 'MEDIUM',
        'exposure_min', 0, 'exposure_max', NULL,
        'score', 60, 'rating', 'MEDIUM',
        'kyc_risk_rating', 'LOW', 'aml_risk_rating', 'MEDIUM',
        'reason', 'KYC verified; open AML case rated MEDIUM'),
      jsonb_build_object(
        'kyc_status', 'VERIFIED', 'aml_risk_level', 'HIGH',
        'exposure_min', 0, 'exposure_max', NULL,
        'score', 90, 'rating', 'HIGH',
        'kyc_risk_rating', 'LOW', 'aml_risk_rating', 'HIGH',
        'reason', 'KYC verified; open AML case rated HIGH'),
      jsonb_build_object(
        'kyc_status', 'EXPIRED', 'aml_risk_level', 'CLEAR',
        'exposure_min', 0, 'exposure_max', NULL,
        'score', 75, 'rating', 'HIGH',
        'kyc_risk_rating', 'HIGH', 'aml_risk_rating', 'LOW',
        'reason', 'KYC expired; AML screening clear'),
      jsonb_build_object(
        'kyc_status', 'MISSING_DOCUMENT', 'aml_risk_level', 'CLEAR',
        'exposure_min', 0, 'exposure_max', NULL,
        'score', 75, 'rating', 'HIGH',
        'kyc_risk_rating', 'HIGH', 'aml_risk_rating', 'LOW',
        'reason', 'KYC document missing; AML screening clear')
    )
  );
  v_sep_01_count integer;
  v_sep_15_count integer;
BEGIN
  -- Rebuild only Member 4 financial, risk and snapshot data.
  TRUNCATE silver.account_transaction,
           silver.banking_account,
           silver.loan,
           gold.fact_customer_snapshot CASCADE;
  DELETE FROM silver.customer_risk_assessment;
  DELETE FROM silver.data_quality_issue
  WHERE validation_run_id LIKE 'FIN-%';

  CALL gold.load_dim_customer();

  -- Publish the older date before loading the newer Silver financial state.
  CALL silver.load_financials(DATE '2026-09-01');
  UPDATE silver.data_quality_issue
  SET issue_status = 'ACKNOWLEDGED', resolved_at = now()
  WHERE validation_run_id = 'FIN-2026-09-01'
    AND issue_status = 'OPEN';
  CALL gold.publish_snapshot(DATE '2026-09-01', v_rules);

  CALL silver.load_financials(DATE '2026-09-15');
  UPDATE silver.data_quality_issue
  SET issue_status = 'ACKNOWLEDGED', resolved_at = now()
  WHERE validation_run_id = 'FIN-2026-09-15'
    AND issue_status = 'OPEN';
  CALL gold.publish_snapshot(DATE '2026-09-15', v_rules);

  SELECT count(*) INTO v_sep_01_count
  FROM gold.fact_customer_snapshot
  WHERE snapshot_date = DATE '2026-09-01';

  SELECT count(*) INTO v_sep_15_count
  FROM gold.fact_customer_snapshot
  WHERE snapshot_date = DATE '2026-09-15';

  IF v_sep_01_count <> 9 OR v_sep_15_count <> 10 THEN
    RAISE EXCEPTION
      'Unexpected snapshot counts: 2026-09-01=%, 2026-09-15=%',
      v_sep_01_count, v_sep_15_count;
  END IF;

  RAISE NOTICE
    'Member 4 update complete: 2026-09-01=% customers, 2026-09-15=% customers',
    v_sep_01_count, v_sep_15_count;
END;
$member4_two_date_update$;

-- Optional verification result shown when the whole file is executed.
SELECT snapshot_date, count(*) AS customer_count
FROM gold.fact_customer_snapshot
GROUP BY snapshot_date
ORDER BY snapshot_date;
