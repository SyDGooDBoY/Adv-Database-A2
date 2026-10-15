-- PostgreSQL 15+
-- Member 5: validate the Bronze KYC verification and AML screening rows and publish them to Silver.
--
-- Publication is driven by the presence of Bronze rows, not by the batch status:
--   B2-AMLKYC has a source row whose CDC operation_type is blank, so Member 1 marks that
--   batch FAILED on purpose, yet its retained rows are still reportable.

-- Section 1: steps shared by both publishers

-- Stage one batch's Bronze rows into a temp table and attach the identity lookup result.
--
-- The lookup answers two questions:
--   source_customer_record_id: which Silver record this source customer reference maps to
--   customer_id: which golden customer it merged into, when the merge succeeded
-- Both are NULL when nothing is found. The event is still published, and the rules then report the unresolved identity.
CREATE OR REPLACE PROCEDURE silver.stage_bronze_batch(
  p_entity varchar,
  p_batch_id varchar
)
LANGUAGE plpgsql
AS $stage_batch$
BEGIN
  IF p_entity = 'KYC' THEN
    DROP TABLE IF EXISTS tmp_staged;
    CREATE TEMP TABLE tmp_staged ON COMMIT DROP AS
    SELECT
      raw.bronze_record_reference,
      raw.batch_id,
      raw.source_system_id,
      btrim(raw.source_kyc_reference) AS event_reference,
      btrim(raw.source_customer_reference) AS customer_reference,
      raw.verification_type AS event_type,
      raw.verification_status AS event_status,
      raw.verification_date AS event_time,
      raw.expiry_date,
      raw.risk_level_at_verification,
      raw.reviewer_reference,
      NULL::numeric AS match_score,
      NULL::varchar AS provider_reference,
      NULL::boolean AS review_required_flag,
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
  ELSIF p_entity = 'AML' THEN
    DROP TABLE IF EXISTS tmp_staged;
    CREATE TEMP TABLE tmp_staged ON COMMIT DROP AS
    SELECT
      raw.bronze_record_reference,
      raw.batch_id,
      raw.source_system_id,
      btrim(raw.source_screening_reference) AS event_reference,
      btrim(raw.source_customer_reference) AS customer_reference,
      raw.screening_type AS event_type,
      raw.screening_result AS event_status,
      raw.screening_date AS event_time,
      NULL::date AS expiry_date,
      NULL::varchar AS risk_level_at_verification,
      NULL::varchar AS reviewer_reference,
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
      ) AS customer_id,
      NULL::varchar AS reviewed_by
    FROM bronze.raw_aml_screening raw
    WHERE raw.batch_id = p_batch_id;
  ELSE
    RAISE EXCEPTION 'Unsupported entity %; expected KYC or AML', p_entity;
  END IF;
END;
$stage_batch$;

-- Record published events in the lineage table, linking the Bronze row to the Silver event.
-- Republishing the same row adds no duplicate lineage, because lineage_id is derived.
CREATE OR REPLACE PROCEDURE silver.record_event_lineage(
  p_entity varchar,
  p_batch_id varchar
)
LANGUAGE plpgsql
AS $record_lineage$
BEGIN
  INSERT INTO silver.data_lineage_record (
    lineage_id, batch_id, source_system_id, transformation_run_id,
    source_layer, source_entity_name, source_record_reference,
    source_version_reference, source_attribute_name, source_record_snapshot,
    target_layer, target_entity_name, target_record_reference,
    target_version_reference, target_attribute_name, target_record_snapshot,
    transformation_name, transformation_version, transformation_timestamp
  )
  SELECT
    'LIN-' || p_entity || '-' || upper(substr(md5(staged.bronze_record_reference), 1, 20)),
    staged.batch_id,
    staged.source_system_id,
    'KYC-AML-M5-' || staged.batch_id,
    'BRONZE',
    CASE p_entity WHEN 'KYC' THEN 'RAW_KYC_VERIFICATION' ELSE 'RAW_AML_SCREENING' END,
    staged.bronze_record_reference,
    staged.batch_id,
    NULL,
    concat_ws(
      '|',
      'event_reference=' || staged.event_reference,
      'event_type=' || staged.event_type,
      'event_status=' || staged.event_status,
      'event_time=' || staged.event_time::text
    ),
    'SILVER',
    CASE p_entity WHEN 'KYC' THEN 'KYC_VERIFICATION_RECORD' ELSE 'AML_SCREENING_RESULT' END,
    published.target_record_reference,
    staged.batch_id,
    NULL,
    concat_ws(
      '|',
      'customer_id=' || COALESCE(staged.customer_id, 'NULL'),
      'source_customer_record_id=' || COALESCE(staged.source_customer_record_id, 'NULL'),
      'event_status=' || staged.event_status
    ),
    CASE p_entity
      WHEN 'KYC' THEN 'PUBLISH_KYC_VERIFICATION_EVENT'
      ELSE 'PUBLISH_AML_SCREENING_EVENT'
    END,
    '1.0',
    COALESCE(staged.event_time, clock_timestamp())
  FROM tmp_staged staged
  JOIN (
    SELECT
      verification.source_system_id,
      verification.source_kyc_reference AS event_reference,
      verification.kyc_verification_id AS target_record_reference
    FROM silver.kyc_verification_record verification
    WHERE p_entity = 'KYC'
    UNION ALL
    SELECT
      screening.source_system_id,
      screening.source_screening_reference,
      screening.aml_screening_id
    FROM silver.aml_screening_result screening
    WHERE p_entity = 'AML'
  ) published
    ON published.source_system_id = staged.source_system_id
   AND published.event_reference = staged.event_reference
  ON CONFLICT (lineage_id) DO NOTHING;
END;
$record_lineage$;

-- Section 2: event publication, one procedure per event type with columns listed explicitly

-- Publish KYC verification events: stage and resolve identity, detect issues, publish the survivors.
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
  CALL silver.stage_bronze_batch('KYC', p_batch_id);

  SELECT count(*)::integer INTO v_staged_count FROM tmp_staged;

  IF v_staged_count = 0 THEN
    RAISE NOTICE 'Batch % has no KYC verification rows in Bronze; nothing to publish', p_batch_id;
    RETURN;
  END IF;

  DROP TABLE IF EXISTS tmp_findings;
  CREATE TEMP TABLE tmp_findings ON COMMIT DROP AS
  SELECT * FROM silver.detect_kyc_verification_issues(p_batch_id, p_reference_date);

  SELECT count(*)::integer INTO v_blocking_count
  FROM tmp_findings WHERE issue_severity = 'BLOCKING';

  INSERT INTO silver.kyc_verification_record (
    kyc_verification_id, customer_id, source_customer_record_id, source_system_id,
    reviewed_by, source_kyc_reference, verification_type, verification_status,
    verification_date, expiry_date, risk_level_at_verification
  )
  SELECT
    silver.kyc_verification_id(staged.source_system_id, staged.event_reference),
    staged.customer_id,
    staged.source_customer_record_id,
    staged.source_system_id,
    staged.reviewed_by,
    staged.event_reference,
    staged.event_type,
    staged.event_status,
    staged.event_time,
    staged.expiry_date,
    staged.risk_level_at_verification
  FROM tmp_staged staged
  -- Rows with a blocking finding are not published.
  WHERE staged.bronze_record_reference NOT IN (
    SELECT finding.source_record_reference
    FROM tmp_findings finding
    WHERE finding.issue_severity = 'BLOCKING'
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

  CALL silver.record_event_lineage('KYC', p_batch_id);

  RAISE NOTICE 'Batch %: % KYC rows staged, % published, % blocked',
    p_batch_id, v_staged_count, v_published_count, v_blocking_count;
END;
$publish_kyc$;

COMMENT ON PROCEDURE silver.publish_kyc_verification_batch(varchar, date) IS
  'Validate one batch of Bronze KYC verification rows and publish them to Silver, withholding rows that carry a blocking finding.';

-- Publish AML screening events: the same steps as the KYC publisher, against different tables.
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
  CALL silver.stage_bronze_batch('AML', p_batch_id);

  SELECT count(*)::integer INTO v_staged_count FROM tmp_staged;

  IF v_staged_count = 0 THEN
    RAISE NOTICE 'Batch % has no AML screening rows in Bronze; nothing to publish', p_batch_id;
    RETURN;
  END IF;

  DROP TABLE IF EXISTS tmp_findings;
  CREATE TEMP TABLE tmp_findings ON COMMIT DROP AS
  SELECT * FROM silver.detect_aml_screening_issues(p_batch_id, p_reference_date);

  SELECT count(*)::integer INTO v_blocking_count
  FROM tmp_findings WHERE issue_severity = 'BLOCKING';

  INSERT INTO silver.aml_screening_result (
    aml_screening_id, customer_id, source_customer_record_id, source_system_id,
    source_screening_reference, screening_type, screening_date, screening_result,
    match_score, provider_reference, review_required_flag
  )
  SELECT
    silver.aml_screening_id(staged.source_system_id, staged.event_reference),
    staged.customer_id,
    staged.source_customer_record_id,
    staged.source_system_id,
    staged.event_reference,
    staged.event_type,
    staged.event_time,
    staged.event_status,
    staged.match_score,
    staged.provider_reference,
    staged.review_required_flag
  FROM tmp_staged staged
  WHERE staged.bronze_record_reference NOT IN (
    SELECT finding.source_record_reference
    FROM tmp_findings finding
    WHERE finding.issue_severity = 'BLOCKING'
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

  CALL silver.record_event_lineage('AML', p_batch_id);

  RAISE NOTICE 'Batch %: % AML rows staged, % published, % blocked',
    p_batch_id, v_staged_count, v_published_count, v_blocking_count;
END;
$publish_aml$;

COMMENT ON PROCEDURE silver.publish_aml_screening_batch(varchar, date) IS
  'Validate one batch of Bronze AML screening rows and publish them to Silver, withholding rows that carry a blocking finding.';

-- Section 3: the per-batch entry point

-- Run one batch end to end: resolve identity, publish both event types, then run the rules.
--
-- Findings are staged in a temp table that both the counting and the registration step reuse.
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
    RAISE EXCEPTION 'A reporting date is required to decide whether a KYC verification has expired';
  END IF;

  SELECT min(source_system_id)
  INTO v_source_system_id
  FROM (
    SELECT source_system_id FROM bronze.raw_kyc_verification WHERE batch_id = p_batch_id
    UNION ALL
    SELECT source_system_id FROM bronze.raw_aml_screening WHERE batch_id = p_batch_id
  ) batch_sources;

  IF v_source_system_id IS NULL THEN
    RAISE EXCEPTION 'Batch % has neither KYC nor AML rows in Bronze', p_batch_id;
  END IF;

  -- Identity resolution scans every customer reference, so it runs once per session.
  CREATE TEMP TABLE IF NOT EXISTS tmp_identity_loaded (
    loaded_at timestamp NOT NULL
  ) ON COMMIT PRESERVE ROWS;

  IF NOT EXISTS (SELECT 1 FROM tmp_identity_loaded) THEN
    CALL silver.load_kyc_aml_customer_identity();
    INSERT INTO tmp_identity_loaded (loaded_at) VALUES (clock_timestamp());
  END IF;

  CALL silver.publish_kyc_verification_batch(p_batch_id, p_reference_date);
  CALL silver.publish_aml_screening_batch(p_batch_id, p_reference_date);

  -- Stage the rule findings so counting and registration share one evaluation.
  DROP TABLE IF EXISTS tmp_kyc_findings;
  CREATE TEMP TABLE tmp_kyc_findings ON COMMIT DROP AS
  SELECT * FROM silver.detect_kyc_verification_issues(p_batch_id, p_reference_date);

  DROP TABLE IF EXISTS tmp_aml_findings;
  CREATE TEMP TABLE tmp_aml_findings ON COMMIT DROP AS
  SELECT * FROM silver.detect_aml_screening_issues(p_batch_id, p_reference_date);

  SELECT count(*)::integer INTO v_kyc_count FROM tmp_kyc_findings;
  SELECT count(*)::integer INTO v_aml_count FROM tmp_aml_findings;

  -- Register as data quality issues. Cases are opened by 05_create_case_processing.sql.
  PERFORM silver.register_compliance_finding(
    p_batch_id, v_source_system_id, 'KYC_VERIFICATION_RECORD',
    issue.source_record_reference, issue.source_batch_reference, issue.issue_attribute_name,
    issue.rule_name, issue.issue_type, issue.issue_description,
    issue.issue_severity, issue.rule_case_type
  )
  FROM tmp_kyc_findings issue;

  PERFORM silver.register_compliance_finding(
    p_batch_id, v_source_system_id, 'AML_SCREENING_RESULT',
    issue.source_record_reference, issue.source_batch_reference, issue.issue_attribute_name,
    issue.rule_name, issue.issue_type, issue.issue_description,
    issue.issue_severity, issue.rule_case_type
  )
  FROM tmp_aml_findings issue;

  RAISE NOTICE 'Batch % complete as of %: % KYC findings, % AML findings',
    p_batch_id, p_reference_date, v_kyc_count, v_aml_count;
END;
$process_batch$;

COMMENT ON PROCEDURE silver.process_kyc_aml_batch(varchar, date) IS
  'Member 5 batch entry point: resolve customer identity, publish KYC and AML events to Silver, run the rules and register the findings.';
