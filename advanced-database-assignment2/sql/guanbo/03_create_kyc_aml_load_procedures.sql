-- PostgreSQL 15+
-- Member 5: publish validated KYC verification and AML screening events from
-- Bronze into Silver.
--
-- The procedure is event-driven rather than batch-state driven: a batch is
-- published when its raw rows exist in Bronze. That matters for B2-AMLKYC,
-- which Member 1 deliberately leaves FAILED because a supplied CDC event has a
-- blank operation_type. Its compliance row is still present in Bronze and is
-- still required by the exception report, so it is published here.
--
-- BLOCKING findings (see 04_create_kyc_aml_validation.sql) stop the affected
-- event from being published and remain open in silver.data_quality_issue.
-- Every other finding is published and reported.

CREATE OR REPLACE PROCEDURE silver.publish_kyc_verification_batch(
  p_batch_id varchar,
  p_reference_date date DEFAULT current_date
)
LANGUAGE plpgsql
AS $publish_kyc$
DECLARE
  v_staged_count integer;
  v_blocking_count integer;
  v_published_count integer := 0;
BEGIN
  DROP TABLE IF EXISTS tmp_kyc_staged;
  CREATE TEMP TABLE tmp_kyc_staged ON COMMIT DROP AS
  SELECT
    raw.bronze_record_reference,
    raw.batch_id,
    raw.source_system_id,
    btrim(raw.source_kyc_reference) AS source_kyc_reference,
    btrim(raw.source_customer_reference) AS source_customer_reference,
    raw.verification_type,
    raw.verification_status,
    raw.verification_date,
    raw.expiry_date,
    raw.risk_level_at_verification,
    (
      SELECT min(source_record.source_customer_record_id)
      FROM silver.source_customer_record source_record
      WHERE source_record.source_system_id = raw.source_system_id
        AND source_record.source_customer_reference = btrim(raw.source_customer_reference)
        AND source_record.is_current_version
    ) AS source_customer_record_id,
    (
      SELECT min(current_match.customer_id)
      FROM silver.source_customer_record source_record
      JOIN silver.customer_source_match current_match
        ON current_match.source_customer_record_id = source_record.source_customer_record_id
       AND current_match.is_current_match
       AND current_match.match_status = 'ACCEPTED'
      WHERE source_record.source_system_id = raw.source_system_id
        AND source_record.source_customer_reference = btrim(raw.source_customer_reference)
    ) AS customer_id,
    (
      SELECT min(btrim(reviewer.user_id))
      FROM silver.user_account reviewer
      WHERE reviewer.username = btrim(COALESCE(raw.reviewer_reference, ''))
    ) AS reviewed_by
  FROM bronze.raw_kyc_verification raw
  WHERE raw.batch_id = p_batch_id;

  SELECT count(*)::integer INTO v_staged_count FROM tmp_kyc_staged;

  IF v_staged_count = 0 THEN
    RAISE NOTICE 'No Bronze KYC verification rows for batch %; nothing to publish',
      p_batch_id;
    RETURN;
  END IF;

  DROP TABLE IF EXISTS tmp_kyc_issues;

  CREATE TEMP TABLE tmp_kyc_issues ON COMMIT DROP AS
  SELECT *
  FROM silver.detect_kyc_verification_issues(p_batch_id, p_reference_date);

  SELECT count(*)::integer
  INTO v_blocking_count
  FROM tmp_kyc_issues
  WHERE issue_severity = 'BLOCKING';

  INSERT INTO silver.kyc_verification_record (
    kyc_verification_id,
    customer_id,
    source_customer_record_id,
    source_system_id,
    reviewed_by,
    source_kyc_reference,
    verification_type,
    verification_status,
    verification_date,
    expiry_date,
    risk_level_at_verification
  )
  SELECT
    'KYC-' || upper(substr(md5(staged.source_system_id || ':' || staged.source_kyc_reference), 1, 16)),
    staged.customer_id,
    staged.source_customer_record_id,
    staged.source_system_id,
    staged.reviewed_by,
    staged.source_kyc_reference,
    staged.verification_type,
    staged.verification_status,
    staged.verification_date,
    staged.expiry_date,
    staged.risk_level_at_verification
  FROM tmp_kyc_staged staged
  WHERE NOT EXISTS (
    SELECT 1
    FROM tmp_kyc_issues blocking
    WHERE blocking.issue_severity = 'BLOCKING'
      AND blocking.source_record_reference = staged.bronze_record_reference
  )
  ON CONFLICT (source_system_id, source_kyc_reference) DO UPDATE SET
    customer_id = EXCLUDED.customer_id,
    source_customer_record_id = EXCLUDED.source_customer_record_id,
    reviewed_by = EXCLUDED.reviewed_by,
    verification_type = EXCLUDED.verification_type,
    verification_status = EXCLUDED.verification_status,
    verification_date = EXCLUDED.verification_date,
    expiry_date = EXCLUDED.expiry_date,
    risk_level_at_verification = EXCLUDED.risk_level_at_verification;

  GET DIAGNOSTICS v_published_count = ROW_COUNT;

  WITH published AS (
    SELECT
      verification.kyc_verification_id,
      staged.bronze_record_reference,
      staged.batch_id,
      staged.source_system_id
    FROM tmp_kyc_staged staged
    JOIN silver.kyc_verification_record verification
      ON verification.source_system_id = staged.source_system_id
     AND verification.source_kyc_reference = staged.source_kyc_reference
  )
  INSERT INTO silver.data_lineage_record (
    lineage_id,
    batch_id,
    source_system_id,
    transformation_run_id,
    source_layer,
    source_entity_name,
    source_record_reference,
    source_version_reference,
    source_attribute_name,
    source_record_snapshot,
    target_layer,
    target_entity_name,
    target_record_reference,
    target_version_reference,
    target_attribute_name,
    target_record_snapshot,
    transformation_name,
    transformation_version,
    transformation_timestamp
  )
  SELECT
    'LIN-KYC-' || upper(substr(md5(published.bronze_record_reference), 1, 20)),
    published.batch_id,
    published.source_system_id,
    'KYC-AML-M5-' || published.batch_id,
    'BRONZE',
    'RAW_KYC_VERIFICATION',
    published.bronze_record_reference,
    published.batch_id,
    NULL,
    concat_ws(
      '|',
      'source_kyc_reference=' || staged.source_kyc_reference,
      'verification_type=' || staged.verification_type,
      'verification_status=' || staged.verification_status,
      'verification_date=' || staged.verification_date::text
    ),
    'SILVER',
    'KYC_VERIFICATION_RECORD',
    published.kyc_verification_id,
    published.batch_id,
    NULL,
    concat_ws(
      '|',
      'customer_id=' || COALESCE(staged.customer_id, 'NULL'),
      'source_customer_record_id=' || COALESCE(staged.source_customer_record_id, 'NULL'),
      'verification_status=' || staged.verification_status
    ),
    'PUBLISH_KYC_VERIFICATION_EVENT',
    '1.0',
    COALESCE(staged.verification_date, clock_timestamp())
  FROM published
  JOIN tmp_kyc_staged staged
    ON staged.bronze_record_reference = published.bronze_record_reference
  ON CONFLICT (lineage_id) DO NOTHING;

  RAISE NOTICE
    'Batch %: % Bronze KYC rows staged, % published, % blocking',
    p_batch_id,
    v_staged_count,
    v_published_count,
    v_blocking_count;
END;
$publish_kyc$;

COMMENT ON PROCEDURE silver.publish_kyc_verification_batch(varchar, date) IS
  'Publishes one batch of Bronze KYC verification rows to Silver, withholding rows that fail a blocking validation rule.';

CREATE OR REPLACE PROCEDURE silver.publish_aml_screening_batch(
  p_batch_id varchar,
  p_reference_date date DEFAULT current_date
)
LANGUAGE plpgsql
AS $publish_aml$
DECLARE
  v_staged_count integer;
  v_blocking_count integer;
  v_published_count integer := 0;
BEGIN
  DROP TABLE IF EXISTS tmp_aml_staged;
  CREATE TEMP TABLE tmp_aml_staged ON COMMIT DROP AS
  SELECT
    raw.bronze_record_reference,
    raw.batch_id,
    raw.source_system_id,
    btrim(raw.source_screening_reference) AS source_screening_reference,
    btrim(raw.source_customer_reference) AS source_customer_reference,
    raw.screening_type,
    raw.screening_date,
    raw.screening_result,
    raw.match_score,
    raw.provider_reference,
    COALESCE(raw.review_required_flag, false) AS review_required_flag,
    (
      SELECT min(source_record.source_customer_record_id)
      FROM silver.source_customer_record source_record
      WHERE source_record.source_system_id = raw.source_system_id
        AND source_record.source_customer_reference = btrim(raw.source_customer_reference)
        AND source_record.is_current_version
    ) AS source_customer_record_id,
    (
      SELECT min(current_match.customer_id)
      FROM silver.source_customer_record source_record
      JOIN silver.customer_source_match current_match
        ON current_match.source_customer_record_id = source_record.source_customer_record_id
       AND current_match.is_current_match
       AND current_match.match_status = 'ACCEPTED'
      WHERE source_record.source_system_id = raw.source_system_id
        AND source_record.source_customer_reference = btrim(raw.source_customer_reference)
    ) AS customer_id
  FROM bronze.raw_aml_screening raw
  WHERE raw.batch_id = p_batch_id;

  SELECT count(*)::integer INTO v_staged_count FROM tmp_aml_staged;

  IF v_staged_count = 0 THEN
    RAISE NOTICE 'No Bronze AML screening rows for batch %; nothing to publish',
      p_batch_id;
    RETURN;
  END IF;

  DROP TABLE IF EXISTS tmp_aml_issues;

  CREATE TEMP TABLE tmp_aml_issues ON COMMIT DROP AS
  SELECT *
  FROM silver.detect_aml_screening_issues(p_batch_id, p_reference_date);

  SELECT count(*)::integer
  INTO v_blocking_count
  FROM tmp_aml_issues
  WHERE issue_severity = 'BLOCKING';

  INSERT INTO silver.aml_screening_result (
    aml_screening_id,
    customer_id,
    source_customer_record_id,
    source_system_id,
    source_screening_reference,
    screening_type,
    screening_date,
    screening_result,
    match_score,
    provider_reference,
    review_required_flag
  )
  SELECT
    'AML-' || upper(substr(md5(staged.source_system_id || ':' || staged.source_screening_reference), 1, 16)),
    staged.customer_id,
    staged.source_customer_record_id,
    staged.source_system_id,
    staged.source_screening_reference,
    staged.screening_type,
    staged.screening_date,
    staged.screening_result,
    staged.match_score,
    staged.provider_reference,
    staged.review_required_flag
  FROM tmp_aml_staged staged
  WHERE NOT EXISTS (
    SELECT 1
    FROM tmp_aml_issues blocking
    WHERE blocking.issue_severity = 'BLOCKING'
      AND blocking.source_record_reference = staged.bronze_record_reference
  )
  ON CONFLICT (source_system_id, source_screening_reference) DO UPDATE SET
    customer_id = EXCLUDED.customer_id,
    source_customer_record_id = EXCLUDED.source_customer_record_id,
    screening_type = EXCLUDED.screening_type,
    screening_date = EXCLUDED.screening_date,
    screening_result = EXCLUDED.screening_result,
    match_score = EXCLUDED.match_score,
    provider_reference = EXCLUDED.provider_reference,
    review_required_flag = EXCLUDED.review_required_flag;

  GET DIAGNOSTICS v_published_count = ROW_COUNT;

  WITH published AS (
    SELECT
      screening.aml_screening_id,
      staged.bronze_record_reference,
      staged.batch_id,
      staged.source_system_id
    FROM tmp_aml_staged staged
    JOIN silver.aml_screening_result screening
      ON screening.source_system_id = staged.source_system_id
     AND screening.source_screening_reference = staged.source_screening_reference
  )
  INSERT INTO silver.data_lineage_record (
    lineage_id,
    batch_id,
    source_system_id,
    transformation_run_id,
    source_layer,
    source_entity_name,
    source_record_reference,
    source_version_reference,
    source_attribute_name,
    source_record_snapshot,
    target_layer,
    target_entity_name,
    target_record_reference,
    target_version_reference,
    target_attribute_name,
    target_record_snapshot,
    transformation_name,
    transformation_version,
    transformation_timestamp
  )
  SELECT
    'LIN-AML-' || upper(substr(md5(published.bronze_record_reference), 1, 20)),
    published.batch_id,
    published.source_system_id,
    'KYC-AML-M5-' || published.batch_id,
    'BRONZE',
    'RAW_AML_SCREENING',
    published.bronze_record_reference,
    published.batch_id,
    NULL,
    concat_ws(
      '|',
      'source_screening_reference=' || staged.source_screening_reference,
      'screening_type=' || staged.screening_type,
      'screening_result=' || staged.screening_result,
      'match_score=' || COALESCE(staged.match_score::text, 'NULL')
    ),
    'SILVER',
    'AML_SCREENING_RESULT',
    published.aml_screening_id,
    published.batch_id,
    NULL,
    concat_ws(
      '|',
      'customer_id=' || COALESCE(staged.customer_id, 'NULL'),
      'source_customer_record_id=' || COALESCE(staged.source_customer_record_id, 'NULL'),
      'review_required_flag=' || staged.review_required_flag::text
    ),
    'PUBLISH_AML_SCREENING_EVENT',
    '1.0',
    COALESCE(staged.screening_date, clock_timestamp())
  FROM published
  JOIN tmp_aml_staged staged
    ON staged.bronze_record_reference = published.bronze_record_reference
  ON CONFLICT (lineage_id) DO NOTHING;

  RAISE NOTICE
    'Batch %: % Bronze AML rows staged, % published, % blocking',
    p_batch_id,
    v_staged_count,
    v_published_count,
    v_blocking_count;
END;
$publish_aml$;

COMMENT ON PROCEDURE silver.publish_aml_screening_batch(varchar, date) IS
  'Publishes one batch of Bronze AML screening rows to Silver, withholding rows that fail a blocking validation rule.';

-- One entry point per batch: stage the identity the events need, publish both
-- event types, then apply the validation rules and raise the resulting issues.
CREATE OR REPLACE PROCEDURE silver.process_kyc_aml_batch(
  p_batch_id varchar,
  p_reference_date date DEFAULT current_date
)
LANGUAGE plpgsql
AS $process_batch$
DECLARE
  v_source_system_id varchar(50);
  v_kyc_count integer;
  v_aml_count integer;
BEGIN
  IF p_reference_date IS NULL THEN
    RAISE EXCEPTION 'A reference date is required to evaluate KYC expiry';
  END IF;

  SELECT min(source_system_id)
  INTO v_source_system_id
  FROM (
    SELECT source_system_id FROM bronze.raw_kyc_verification WHERE batch_id = p_batch_id
    UNION ALL
    SELECT source_system_id FROM bronze.raw_aml_screening WHERE batch_id = p_batch_id
  ) batch_sources;

  IF v_source_system_id IS NULL THEN
    RAISE EXCEPTION 'Batch % has no Bronze KYC or AML screening rows', p_batch_id;
  END IF;

  -- The identity staging is a full reference scan, so it runs once per session
  -- rather than once per batch.
  BEGIN
    CREATE TEMP TABLE IF NOT EXISTS tmp_member5_identity_loaded (
      loaded_at timestamp NOT NULL
    ) ON COMMIT PRESERVE ROWS;

    IF NOT EXISTS (SELECT 1 FROM tmp_member5_identity_loaded) THEN
      CALL silver.load_kyc_aml_customer_identity();
      INSERT INTO tmp_member5_identity_loaded (loaded_at) VALUES (clock_timestamp());
    END IF;
  END;

  CALL silver.publish_kyc_verification_batch(p_batch_id, p_reference_date);
  CALL silver.publish_aml_screening_batch(p_batch_id, p_reference_date);

  SELECT count(*)::integer INTO v_kyc_count FROM silver.detect_kyc_verification_issues(p_batch_id, p_reference_date);
  SELECT count(*)::integer INTO v_aml_count FROM silver.detect_aml_screening_issues(p_batch_id, p_reference_date);

  PERFORM silver.register_compliance_finding(
    p_batch_id,
    v_source_system_id,
    'KYC_VERIFICATION_RECORD',
    issue.source_record_reference,
    issue.source_batch_reference,
    issue.issue_attribute_name,
    issue.rule_name,
    issue.issue_type,
    issue.issue_description,
    issue.issue_severity,
    issue.rule_case_type
  )
  FROM silver.detect_kyc_verification_issues(p_batch_id, p_reference_date) issue;

  PERFORM silver.register_compliance_finding(
    p_batch_id,
    v_source_system_id,
    'AML_SCREENING_RESULT',
    issue.source_record_reference,
    issue.source_batch_reference,
    issue.issue_attribute_name,
    issue.rule_name,
    issue.issue_type,
    issue.issue_description,
    issue.issue_severity,
    issue.rule_case_type
  )
  FROM silver.detect_aml_screening_issues(p_batch_id, p_reference_date) issue;

  RAISE NOTICE
    'Batch % processed at reference date %: % KYC findings, % AML findings',
    p_batch_id,
    p_reference_date,
    v_kyc_count,
    v_aml_count;
END;
$process_batch$;

COMMENT ON PROCEDURE silver.process_kyc_aml_batch(varchar, date) IS
  'End-to-end Member 5 batch step: stage identity, publish KYC and AML events to Silver, then apply the compliance validation rules.';
