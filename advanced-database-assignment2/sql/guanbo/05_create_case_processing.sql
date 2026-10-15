-- PostgreSQL 15+
-- Member 5: opening cases and moving their status, for verification cases and AML cases.
-- Two rules: a reportable finding opens its case, and a repeated finding reuses the open case;
-- case status has to agree with the closing timestamp, and a case closes only once cleared.
-- An AML alert is only a suspicion, so its case is a review, not a conclusion.

-- Returns the verification case for a KYC finding, opening one when none exists.
-- The shared find-or-open step used by both case-specific functions.
--
-- Three steps: look for a case by subject and case type, reuse it when found, otherwise
-- derive an identifier and insert. The identifier is derived from event and case type, so a
-- repeated detection lands on the same row. Returns the case id and trigger type.
CREATE OR REPLACE FUNCTION silver.find_or_open_case(
  p_entity varchar,
  p_case_type varchar,
  p_record_id varchar,
  p_rule_name varchar,
  p_issue_description text,
  p_severity varchar,
  p_default_batch varchar DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $find_or_open$
DECLARE
  v_customer_id varchar(50);
  v_source_record_id varchar(50);
  v_screening_id varchar(50);
  v_customer_reference varchar(100);
  v_screening_type varchar(50);
  v_open_at timestamp;
  v_trigger_type varchar(50);
  v_table varchar;
  v_id_column varchar;
  v_prefix varchar;
  v_case_id varchar(50);
BEGIN
  -- Read the subject, and decide which case table is written.
  IF p_entity = 'KYC' THEN
    SELECT verification.customer_id, verification.source_customer_record_id
    INTO v_customer_id, v_source_record_id
    FROM silver.kyc_verification_record verification
    WHERE verification.kyc_verification_id = p_record_id;

    v_table := 'silver.special_verification_case';
    v_id_column := 'verification_case_id';
    v_prefix := 'SVCR-';

    v_trigger_type := CASE
      WHEN v_customer_id IS NOT NULL THEN 'GOLDEN_CUSTOMER'
      ELSE 'SOURCE_CUSTOMER_RECORD'
    END;
    -- Opened at the event's business time, so a rerun cannot inflate the case age.
    v_open_at := COALESCE((
      SELECT max(lineage.transformation_timestamp)
      FROM silver.data_lineage_record lineage
      WHERE lineage.target_record_reference = p_record_id
        AND lineage.transformation_name = 'PUBLISH_KYC_VERIFICATION_EVENT'
    ), clock_timestamp());
  ELSIF p_entity = 'AML' THEN
    SELECT
      screening.customer_id,
      screening.source_customer_record_id,
      screening.source_screening_reference,
      screening.screening_type
    INTO v_customer_id, v_source_record_id, v_customer_reference, v_screening_type
    FROM silver.aml_screening_result screening
    WHERE screening.aml_screening_id = p_record_id;

    v_screening_id := p_record_id;
    v_table := 'silver.aml_case';
    v_id_column := 'aml_case_id';
    v_prefix := 'AMLC-';

    v_trigger_type := CASE v_screening_type
      WHEN 'SANCTIONS' THEN 'SANCTIONS_SCREENING'
      WHEN 'PEP' THEN 'PEP_SCREENING'
      WHEN 'WATCHLIST' THEN 'WATCHLIST_SCREENING'
      WHEN 'ADVERSE_MEDIA' THEN 'ADVERSE_MEDIA_SCREENING'
      ELSE 'SCREENING_ALERT'
    END;
    v_open_at := COALESCE((
      SELECT max(lineage.transformation_timestamp)
      FROM silver.data_lineage_record lineage
      WHERE lineage.target_record_reference = p_record_id
        AND lineage.transformation_name = 'PUBLISH_AML_SCREENING_EVENT'
    ), clock_timestamp());
  ELSE
    RAISE EXCEPTION 'Unsupported entity %: expected KYC or AML', p_entity;
  END IF;

  -- One case per subject and case type.
  EXECUTE format(
    'SELECT %I FROM %s
     WHERE case_type = $1
       AND customer_id IS NOT DISTINCT FROM $2
       AND source_customer_record_id IS NOT DISTINCT FROM $3
     ORDER BY opened_at DESC, %I DESC
     LIMIT 1',
    v_id_column, v_table, v_id_column
  )
  INTO v_case_id
  USING p_case_type, v_customer_id, v_source_record_id;

  IF v_case_id IS NULL THEN
    v_case_id := v_prefix || upper(substr(md5(p_record_id || ':' || p_case_type), 1, 16));

    -- Case severity uses the case scale, so BLOCKING never appears: that belongs to data issues.
    IF p_entity = 'KYC' THEN
      INSERT INTO silver.special_verification_case (
        verification_case_id, customer_id, source_customer_record_id, match_id,
        kyc_verification_id, assigned_user_id, case_type, trigger_type,
        case_reason, case_status, severity, opened_at, resolved_at, resolution_outcome
      )
      VALUES (
        v_case_id, v_customer_id, v_source_record_id, NULL,
        p_record_id, NULL, p_case_type, v_trigger_type,
        left(concat(p_rule_name, ': ', p_issue_description), 1000),
        'OPEN',
        CASE p_severity
          WHEN 'BLOCKING' THEN 'CRITICAL'
          WHEN 'HIGH' THEN 'HIGH'
          WHEN 'MEDIUM' THEN 'MEDIUM'
          ELSE 'LOW'
        END,
        v_open_at, NULL, NULL
      )
      ON CONFLICT (verification_case_id) DO NOTHING;
    ELSE
      -- AML risk tops out at HIGH, so BLOCKING maps to HIGH rather than CRITICAL.
      INSERT INTO silver.aml_case (
        aml_case_id, customer_id, source_customer_record_id, aml_screening_id,
        assigned_user_id, trigger_type, trigger_reference, case_type,
        case_status, risk_level, opened_at, closed_at, case_outcome
      )
      VALUES (
        v_case_id, v_customer_id, v_source_record_id, v_screening_id,
        NULL, v_trigger_type,
        left(concat(p_rule_name, ': ', v_customer_reference), 150),
        p_case_type, 'OPEN',
        CASE p_severity
          WHEN 'BLOCKING' THEN 'HIGH'
          WHEN 'HIGH' THEN 'HIGH'
          WHEN 'MEDIUM' THEN 'MEDIUM'
          ELSE 'LOW'
        END,
        v_open_at, NULL, NULL
      )
      ON CONFLICT (aml_case_id) DO NOTHING;
    END IF;

    RAISE NOTICE 'Opened case % (% / %)', v_case_id, p_case_type, p_record_id;
  ELSE
    RAISE NOTICE 'Reused case % (% / %)', v_case_id, p_case_type, p_record_id;
  END IF;

  RETURN jsonb_build_object('case_id', v_case_id, 'trigger_type', v_trigger_type);
END;
$find_or_open$;

COMMENT ON FUNCTION silver.find_or_open_case(varchar, varchar, varchar, varchar, text, varchar, varchar) IS
  'Shared find-or-open step: one case per subject and case type, reused when it already exists. Used by both KYC and AML.';

-- Verification case: wraps the shared step and returns the id, which is written back to the issue.
CREATE OR REPLACE FUNCTION silver.find_or_open_verification_case(
  p_case_type varchar,
  p_kyc_verification_id varchar,
  p_rule_name varchar,
  p_issue_description text,
  p_severity varchar
)
RETURNS varchar
LANGUAGE sql
AS $open_verification_case$
  SELECT silver.find_or_open_case(
    'KYC', p_case_type, p_kyc_verification_id, p_rule_name, p_issue_description, p_severity
  ) ->> 'case_id';
$open_verification_case$;

COMMENT ON FUNCTION silver.find_or_open_verification_case(varchar, varchar, varchar, text, varchar) IS
  'Find or open a verification case and return its identifier. One case per verification event and case type.';

-- AML case: the issue table has no AML column to write back to, so nothing is returned.
CREATE OR REPLACE FUNCTION silver.find_or_open_aml_case(
  p_case_type varchar,
  p_aml_screening_id varchar,
  p_rule_name varchar,
  p_issue_description text,
  p_severity varchar
)
RETURNS varchar
LANGUAGE sql
AS $open_aml_case$
  SELECT silver.find_or_open_case(
    'AML', p_case_type, p_aml_screening_id, p_rule_name, p_issue_description, p_severity
  ) ->> 'case_id';
$open_aml_case$;

COMMENT ON FUNCTION silver.find_or_open_aml_case(varchar, varchar, varchar, text, varchar) IS
  'Find or open an AML investigation case and return its identifier. Reuse works as for verification cases.';

-- Dispatch a finding to the right case-opening function.
-- KYC returns a verification case id; AML returns NULL, since the issue table only links a verification case.
CREATE OR REPLACE FUNCTION silver.resolve_compliance_case(
  p_entity_name varchar,
  p_case_type varchar,
  p_record_reference varchar,
  p_rule_name varchar,
  p_issue_description text,
  p_severity varchar
)
RETURNS varchar
LANGUAGE plpgsql
AS $resolve_case$
BEGIN
  IF p_entity_name = 'KYC_VERIFICATION_RECORD' THEN
    RETURN silver.find_or_open_verification_case(
      p_case_type,
      p_record_reference,
      p_rule_name,
      p_issue_description,
      p_severity
    );
  ELSIF p_entity_name = 'AML_SCREENING_RESULT' THEN
    PERFORM silver.find_or_open_aml_case(
      p_case_type,
      p_record_reference,
      p_rule_name,
      p_issue_description,
      p_severity
    );
    RETURN NULL;
  END IF;

  RAISE EXCEPTION 'Unsupported compliance entity %', p_entity_name;
END;
$resolve_case$;

COMMENT ON FUNCTION silver.resolve_compliance_case(varchar, varchar, varchar, varchar, text, varchar) IS
  'Opens or reuses the case for one finding and returns the verification case link expected by silver.data_quality_issue.';

-- Open or reuse a case for every open finding and write back the KYC case id. Safe to rerun.
CREATE OR REPLACE PROCEDURE silver.publish_compliance_cases(
  p_batch_id varchar DEFAULT NULL
)
LANGUAGE plpgsql
AS $publish_cases$
DECLARE
  v_open_issues integer;
  v_linked_issues integer := 0;
BEGIN
  -- The issue table holds the source reference while the case functions address the published
  -- record by its key, so the key is resolved here first.
  DROP TABLE IF EXISTS tmp_compliance_case_issue;
  CREATE TEMP TABLE tmp_compliance_case_issue ON COMMIT DROP AS
  SELECT
    issue.data_quality_issue_id,
    issue.batch_id,
    issue.record_reference AS source_record_reference,
    COALESCE(
      verification.kyc_verification_id,
      screening.aml_screening_id
    ) AS published_record_id,
    issue.entity_name,
    issue.rule_name,
    issue.issue_description,
    issue.severity,
    -- The rule-to-case mapping comes from 04_create_kyc_aml_validation.sql;
    -- a rule without a mapping stays a quality record.
    silver.compliance_rule_case_type(issue.rule_name) AS case_type
  FROM silver.data_quality_issue issue
  LEFT JOIN silver.kyc_verification_record verification
    ON verification.source_system_id = issue.source_system_id
   AND verification.source_kyc_reference = issue.record_reference
  LEFT JOIN silver.aml_screening_result screening
    ON screening.source_system_id = issue.source_system_id
   AND screening.source_screening_reference = issue.record_reference
  WHERE issue.validation_run_id LIKE 'KYC-AML-M5-%'
    AND issue.issue_status = 'OPEN'
    AND issue.entity_name IN ('KYC_VERIFICATION_RECORD', 'AML_SCREENING_RESULT')
    AND (p_batch_id IS NULL OR issue.batch_id = p_batch_id)
  ORDER BY issue.batch_id, issue.rule_name, issue.record_reference;
  SELECT count(*)::integer INTO v_open_issues FROM tmp_compliance_case_issue;
  IF EXISTS (
    SELECT 1
    FROM tmp_compliance_case_issue case_issue
    WHERE case_issue.published_record_id IS NULL
  ) THEN
    RAISE EXCEPTION
      'A finding refers to an event that was withheld from Silver, so it has no case: %',
      (
        SELECT string_agg(case_issue.source_record_reference, ', ')
        FROM tmp_compliance_case_issue case_issue
        WHERE case_issue.published_record_id IS NULL
      );
  END IF;
  IF v_open_issues > 0 THEN
    UPDATE silver.data_quality_issue issue
    SET verification_case_id = silver.resolve_compliance_case(
      case_issue.entity_name,
      case_issue.case_type,
      case_issue.published_record_id,
      case_issue.rule_name,
      case_issue.issue_description,
      case_issue.severity
    )
    FROM tmp_compliance_case_issue case_issue
    WHERE issue.data_quality_issue_id = case_issue.data_quality_issue_id
      -- A rule with no case mapping opens nothing and writes nothing back.
      AND case_issue.case_type IS NOT NULL;
    GET DIAGNOSTICS v_linked_issues = ROW_COUNT;
  END IF;
  RAISE NOTICE 'Compliance case publication: % open findings processed, % linked',
    v_open_issues,
    v_linked_issues;
END;
$publish_cases$;

COMMENT ON PROCEDURE silver.publish_compliance_cases(varchar) IS
  'Opens or reuses the compliance case for every open KYC/AML finding and links KYC findings to their verification case.';

-- Reconcile case status against current evidence: findings the rules no longer report are resolved;
-- a verification case whose last open finding cleared becomes RESOLVED; an AML case whose alert
-- no longer stands becomes CLOSED; a case that still has an open finding stays open so its age accrues.
CREATE OR REPLACE PROCEDURE silver.progress_compliance_cases(
  p_reference_date date DEFAULT current_date,
  p_batch_id varchar DEFAULT NULL
)
LANGUAGE plpgsql
AS $progress_cases$
DECLARE
  v_resolved_issues integer;
  v_resolved_verification_cases integer;
  v_closed_aml_cases integer;
BEGIN
  IF p_reference_date IS NULL THEN
    RAISE EXCEPTION 'A reference date is required to progress compliance cases';
  END IF;

  DROP TABLE IF EXISTS tmp_current_finding;

  CREATE TEMP TABLE tmp_current_finding ON COMMIT DROP AS
  SELECT
    finding.source_record_reference,
    finding.rule_name
  FROM silver.detect_kyc_verification_issues(NULL::varchar, p_reference_date) finding
  UNION
  SELECT
    finding.source_record_reference,
    finding.rule_name
  FROM silver.detect_aml_screening_issues(NULL::varchar, p_reference_date) finding;

  UPDATE silver.data_quality_issue issue
  SET
    resolved_at = clock_timestamp(),
    issue_status = 'RESOLVED'
  WHERE issue.validation_run_id LIKE 'KYC-AML-M5-%'
    AND issue.issue_status = 'OPEN'
    AND issue.entity_name IN ('KYC_VERIFICATION_RECORD', 'AML_SCREENING_RESULT')
    AND (p_batch_id IS NULL OR issue.batch_id = p_batch_id)
    AND NOT EXISTS (
      SELECT 1
      FROM tmp_current_finding finding
      WHERE finding.source_record_reference = issue.record_reference
        AND finding.rule_name = issue.rule_name
    );

  GET DIAGNOSTICS v_resolved_issues = ROW_COUNT;

  UPDATE silver.special_verification_case investigation
  SET
    case_status = 'RESOLVED',
    resolved_at = clock_timestamp(),
    resolution_outcome = left(
      concat(
        'All linked findings cleared by the Member 5 validation rules at reference date ',
        p_reference_date::text,
        '.'
      ),
      1000
    )
  WHERE investigation.case_status IN ('OPEN', 'IN_REVIEW')
    AND EXISTS (
      SELECT 1
      FROM silver.data_quality_issue linked_issue
      WHERE linked_issue.verification_case_id = investigation.verification_case_id
    )
    AND NOT EXISTS (
      SELECT 1
      FROM silver.data_quality_issue open_issue
      WHERE open_issue.verification_case_id = investigation.verification_case_id
        AND open_issue.issue_status = 'OPEN'
    );

  GET DIAGNOSTICS v_resolved_verification_cases = ROW_COUNT;

  UPDATE silver.aml_case investigation
  SET
    case_status = 'CLOSED',
    closed_at = clock_timestamp(),
    case_outcome = left(
      concat(
        'Screening alert reviewed; no finding remained open under the Member 5 rules at reference date ',
        p_reference_date::text,
        '.'
      ),
      1000
    )
  WHERE investigation.case_status IN ('OPEN', 'IN_REVIEW')
    AND investigation.aml_screening_id IS NOT NULL
    AND NOT EXISTS (
      SELECT 1
      FROM tmp_current_finding finding
      WHERE finding.source_record_reference = investigation.aml_screening_id
    );

  GET DIAGNOSTICS v_closed_aml_cases = ROW_COUNT;

  RAISE NOTICE
    'Case progression at %: % findings resolved, % verification cases resolved, % AML cases closed',
    p_reference_date,
    v_resolved_issues,
    v_resolved_verification_cases,
    v_closed_aml_cases;
END;
$progress_cases$;

COMMENT ON PROCEDURE silver.progress_compliance_cases(date, varchar) IS
  'Resolves findings that the current rules no longer produce and closes the cases whose findings are all cleared.';
