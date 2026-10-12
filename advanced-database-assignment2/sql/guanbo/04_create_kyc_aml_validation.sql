-- PostgreSQL 15+
-- Member 5: KYC/AML validation rules and issue registration.
--
-- Reportable KYC gaps, identity mismatches and status discrepancies must create
-- or reuse a case of type KYC_GAP, IDENTITY_MISMATCH or STATUS_DISCREPANCY.
-- Each rule therefore carries its case type in rule_case_decision; a rule with
-- NULL there remains a quality record only.
--
-- Detection functions return every finding, including the ones raised for
-- records that a BLOCKING rule withheld. Withheld events are not published to
-- Silver, so registering their issues would break the optional foreign key from
-- silver.data_quality_issue to silver.special_verification_case; the batch
-- procedure in 03_create_kyc_aml_load_procedures.sql consequently registers
-- issues only for events that were actually published to Silver. The DQ issue
-- identifier is scoped per batch and rule, so a record that fails the same rule in
-- a later batch raises its own finding rather than reopening an earlier one.

-- Decision values three-valued: CONFIRMED (rule applies), NOT_APPLICABLE or
-- UNKNOWN (rule does not apply). UNKNOWN deliberately does not trigger a case,
-- so the module does not report a discrepancy it cannot prove.
-- The detection functions are dropped and recreated so their result signature
-- stays in step with the module when it is upgraded in place.
DROP FUNCTION IF EXISTS silver.detect_kyc_verification_issues(varchar, date);
DROP FUNCTION IF EXISTS silver.detect_aml_screening_issues(varchar, date);

CREATE OR REPLACE FUNCTION silver.detect_kyc_verification_issues(
  p_batch_id varchar,
  p_reference_date date DEFAULT current_date
)
RETURNS TABLE (
  bronze_record_reference varchar,
  source_record_reference varchar,
  source_batch_reference varchar,
  customer_reference varchar,
  customer_id varchar,
  issue_attribute_name varchar,
  rule_name varchar,
  issue_type varchar,
  issue_description varchar,
  issue_severity varchar,
  rule_case_type varchar
)
LANGUAGE sql
STABLE
AS $detect_kyc$
  WITH reference_date AS (
    SELECT COALESCE(p_reference_date, current_date) AS as_of_date
  ),
  staged AS (
    SELECT DISTINCT ON (raw.source_system_id, btrim(raw.source_kyc_reference))
      raw.bronze_record_reference,
      raw.batch_id,
      raw.source_system_id,
      btrim(raw.source_kyc_reference) AS source_kyc_reference,
      btrim(raw.source_customer_reference) AS source_customer_reference,
      raw.verification_type,
      raw.verification_status,
      raw.verification_date,
      raw.expiry_date,
      raw.risk_level_at_verification
    FROM bronze.raw_kyc_verification raw
    WHERE p_batch_id IS NULL OR raw.batch_id = p_batch_id
    ORDER BY
      raw.source_system_id,
      btrim(raw.source_kyc_reference),
      raw.ingested_at DESC,
      raw.batch_id DESC,
      raw.bronze_record_reference DESC
  ),
  identity AS (
    SELECT
      staged.bronze_record_reference,
      (
        SELECT min(source_record.source_customer_record_id)
        FROM silver.source_customer_record source_record
        WHERE source_record.source_system_id = staged.source_system_id
          AND source_record.source_customer_reference = staged.source_customer_reference
          AND source_record.is_current_version
      ) AS source_customer_record_id,
      (
        SELECT min(current_match.customer_id)
        FROM silver.source_customer_record source_record
        JOIN silver.customer_source_match current_match
          ON current_match.source_customer_record_id = source_record.source_customer_record_id
         AND current_match.is_current_match
         AND current_match.match_status = 'ACCEPTED'
        WHERE source_record.source_system_id = staged.source_system_id
          AND source_record.source_customer_reference = staged.source_customer_reference
      ) AS customer_id
    FROM staged
  ),
  evaluated AS (
    SELECT
      staged.bronze_record_reference,
      staged.batch_id,
      staged.source_kyc_reference,
      staged.source_customer_reference,
      staged.verification_type,
      staged.verification_status,
      staged.verification_date,
      staged.expiry_date,
      identity.source_customer_record_id,
      identity.customer_id,
      reference_date.as_of_date
    FROM staged
    JOIN identity ON identity.bronze_record_reference = staged.bronze_record_reference
    CROSS JOIN reference_date
  ),
  rule_evaluation AS (
    SELECT
      evaluated.*,
      evaluated.verification_type IN (
        'IDENTITY_DOCUMENT', 'ADDRESS_VERIFICATION', 'SOURCE_OF_FUNDS',
        'ENHANCED_DUE_DILIGENCE', 'PERIODIC_REVIEW'
      ) AS type_is_known,
      evaluated.verification_status IN (
        'VERIFIED', 'PENDING', 'MISSING_DOCUMENT', 'FAILED', 'EXPIRED'
      ) AS status_is_known,
      -- An event whose validity has lapsed at the reference date, whatever the
      -- recorded status says. A check performed on or after the reference date
      -- cannot have lapsed yet.
      CASE
        WHEN evaluated.expiry_date IS NULL THEN 'NOT_APPLICABLE'
        WHEN evaluated.verification_date::date >= evaluated.as_of_date THEN 'NOT_APPLICABLE'
        WHEN evaluated.expiry_date >= evaluated.as_of_date THEN 'NOT_APPLICABLE'
        WHEN evaluated.verification_status IN ('PENDING', 'MISSING_DOCUMENT', 'FAILED')
          THEN 'NOT_APPLICABLE'
        ELSE 'CONFIRMED'
      END AS confirmed_expiry_verdict,
      -- A successful check that cannot be relied on as recorded. The source
      -- already flags an expiry through EXPIRED, so this rule reports the states
      -- that contradict the recorded status rather than repeating that flag.
      CASE
        WHEN evaluated.verification_status <> 'VERIFIED' THEN 'NOT_APPLICABLE'
        WHEN evaluated.expiry_date IS NULL THEN 'CONFIRMED'
        WHEN evaluated.expiry_date < evaluated.verification_date::date THEN 'CONFIRMED'
        WHEN evaluated.expiry_date < evaluated.as_of_date THEN 'CONFIRMED'
        ELSE 'NOT_APPLICABLE'
      END AS status_discrepancy_verdict,
      -- The check did not complete, so the customer has a KYC gap. An EXPIRED
      -- event is reported by the expiry rule instead, not as an unfinished check.
      CASE
        WHEN evaluated.verification_status IN ('PENDING', 'MISSING_DOCUMENT', 'FAILED')
          THEN 'CONFIRMED'
        ELSE 'NOT_APPLICABLE'
      END AS gap_verdict
    FROM evaluated
  ),
  rule_findings AS (
    SELECT
      rule_evaluation.*,
      'subject_reference' AS issue_attribute_name,
      'KYC_EVENT_SUBJECT_REQUIRED' AS rule_name,
      'KYC_SUBJECT_MISSING' AS issue_type,
      'The verification event has no customer and no source customer record; a subject reference is required.' AS issue_description,
      'BLOCKING' AS issue_severity,
      NULL::varchar AS rule_case_type,
      1 AS rule_priority
    FROM rule_evaluation
    WHERE rule_evaluation.customer_id IS NULL
      AND rule_evaluation.source_customer_record_id IS NULL

    UNION ALL

    SELECT
      rule_evaluation.*,
      'subject_reference',
      'KYC_IDENTITY_LINK_MISMATCH',
      'KYC_IDENTITY_MISMATCH',
      'The event is linked to a golden customer and a source customer record that do not represent the same accepted identity.',
      'HIGH',
      'IDENTITY_MISMATCH',
      2
    FROM rule_evaluation
    WHERE rule_evaluation.customer_id IS NOT NULL
      AND rule_evaluation.source_customer_record_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM silver.customer_source_match accepted_match
        WHERE accepted_match.source_customer_record_id = rule_evaluation.source_customer_record_id
          AND accepted_match.customer_id = rule_evaluation.customer_id
          AND accepted_match.match_status = 'ACCEPTED'
          AND accepted_match.is_current_match
      )

    UNION ALL

    SELECT
      rule_evaluation.*,
      'verification_type',
      'KYC_VERIFICATION_TYPE_INVALID',
      'KYC_VERIFICATION_TYPE_INVALID',
      concat('Verification type ', COALESCE(rule_evaluation.verification_type, 'NULL'), ' is not a recognised KYC verification type.'),
      'MEDIUM',
      NULL::varchar,
      3
    FROM rule_evaluation
    WHERE NOT rule_evaluation.type_is_known

    UNION ALL

    SELECT
      rule_evaluation.*,
      'verification_status',
      'KYC_VERIFICATION_STATUS_INVALID',
      'KYC_VERIFICATION_STATUS_INVALID',
      concat('Verification status ', COALESCE(rule_evaluation.verification_status, 'NULL'), ' is not a recognised KYC verification status.'),
      'MEDIUM',
      NULL::varchar,
      3
    FROM rule_evaluation
    WHERE NOT rule_evaluation.status_is_known

    UNION ALL

    SELECT
      rule_evaluation.*,
      'expiry_date',
      'KYC_VERIFICATION_EXPIRED',
      'KYC_VERIFICATION_EXPIRED',
      concat(
        'The check is no longer valid at the reference date: status ',
        rule_evaluation.verification_status,
        ' with expiry date ',
        COALESCE(rule_evaluation.expiry_date::text, 'NULL'),
        '.'
      ),
      'HIGH',
      'STATUS_DISCREPANCY',
      2
    FROM rule_evaluation
    WHERE rule_evaluation.confirmed_expiry_verdict = 'CONFIRMED'

    UNION ALL

    SELECT
      rule_evaluation.*,
      'verification_status',
      'KYC_VERIFICATION_STATUS_DISCREPANCY',
      'KYC_VERIFICATION_STATUS_DISCREPANCY',
      concat(
        'A successful check cannot carry an expiry date of ',
        rule_evaluation.expiry_date::text,
        ' after being performed on ',
        rule_evaluation.verification_date::date::text,
        '.'
      ),
      'HIGH',
      'STATUS_DISCREPANCY',
      2
    FROM rule_evaluation
    WHERE rule_evaluation.status_discrepancy_verdict = 'CONFIRMED'

    UNION ALL

    SELECT
      rule_evaluation.*,
      'verification_status',
      'KYC_VERIFICATION_INCOMPLETE',
      'KYC_VERIFICATION_GAP',
      concat(
        'The KYC check is not a completed successful check: status ',
        rule_evaluation.verification_status,
        '.'
      ),
      'MEDIUM',
      'KYC_GAP',
      3
    FROM rule_evaluation
    WHERE rule_evaluation.gap_verdict = 'CONFIRMED'

    UNION ALL

    SELECT
      rule_evaluation.*,
      'customer_id',
      'KYC_VERIFICATION_UNRESOLVED_IDENTITY',
      'KYC_IDENTITY_UNRESOLVED',
      'The verification event is retained against a source customer record whose golden customer is not yet confirmed; the report must still include it.',
      'LOW',
      NULL::varchar,
      4
    FROM rule_evaluation
    WHERE rule_evaluation.customer_id IS NULL
      AND rule_evaluation.source_customer_record_id IS NOT NULL
  ),
  ranked AS (
    SELECT
      rule_findings.*,
      row_number() OVER (
        PARTITION BY rule_findings.bronze_record_reference
        ORDER BY
          rule_findings.rule_priority,
          CASE rule_findings.issue_severity
            WHEN 'BLOCKING' THEN 1
            WHEN 'HIGH' THEN 2
            WHEN 'MEDIUM' THEN 3
            ELSE 4
          END,
          rule_findings.rule_name
      ) AS finding_rank
    FROM rule_findings
  )
  SELECT
    ranked.bronze_record_reference::varchar,
    ranked.source_kyc_reference::varchar,
    ranked.batch_id::varchar,
    ranked.source_customer_reference::varchar,
    ranked.customer_id::varchar,
    ranked.issue_attribute_name::varchar,
    ranked.rule_name::varchar,
    ranked.issue_type::varchar,
    ranked.issue_description::varchar,
    ranked.issue_severity::varchar,
    ranked.rule_case_type::varchar
  FROM ranked
  WHERE ranked.finding_rank = 1;
$detect_kyc$;

COMMENT ON FUNCTION silver.detect_kyc_verification_issues(varchar, date) IS
  'Applies the Member 5 KYC verification rules to one Bronze batch and returns the highest-priority finding per record.';

CREATE OR REPLACE FUNCTION silver.detect_aml_screening_issues(
  p_batch_id varchar,
  p_reference_date date DEFAULT current_date
)
RETURNS TABLE (
  bronze_record_reference varchar,
  source_record_reference varchar,
  source_batch_reference varchar,
  customer_reference varchar,
  customer_id varchar,
  issue_attribute_name varchar,
  rule_name varchar,
  issue_type varchar,
  issue_description varchar,
  issue_severity varchar,
  rule_case_type varchar
)
LANGUAGE sql
STABLE
AS $detect_aml$
  WITH reference_date AS (
    SELECT COALESCE(p_reference_date, current_date) AS as_of_date
  ),
  staged AS (
    SELECT DISTINCT ON (raw.source_system_id, btrim(raw.source_screening_reference))
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
      COALESCE(raw.review_required_flag, false) AS review_required_flag
    FROM bronze.raw_aml_screening raw
    WHERE p_batch_id IS NULL OR raw.batch_id = p_batch_id
    ORDER BY
      raw.source_system_id,
      btrim(raw.source_screening_reference),
      raw.ingested_at DESC,
      raw.batch_id DESC,
      raw.bronze_record_reference DESC
  ),
  identity AS (
    SELECT
      staged.bronze_record_reference,
      (
        SELECT min(source_record.source_customer_record_id)
        FROM silver.source_customer_record source_record
        WHERE source_record.source_system_id = staged.source_system_id
          AND source_record.source_customer_reference = staged.source_customer_reference
          AND source_record.is_current_version
      ) AS source_customer_record_id,
      (
        SELECT min(current_match.customer_id)
        FROM silver.source_customer_record source_record
        JOIN silver.customer_source_match current_match
          ON current_match.source_customer_record_id = source_record.source_customer_record_id
         AND current_match.is_current_match
         AND current_match.match_status = 'ACCEPTED'
        WHERE source_record.source_system_id = staged.source_system_id
          AND source_record.source_customer_reference = staged.source_customer_reference
      ) AS customer_id
    FROM staged
  ),
  evaluated AS (
    SELECT
      staged.bronze_record_reference,
      staged.batch_id,
      staged.source_screening_reference,
      staged.source_customer_reference,
      staged.screening_type,
      staged.screening_date,
      staged.screening_result,
      staged.match_score,
      staged.review_required_flag,
      identity.source_customer_record_id,
      identity.customer_id,
      reference_date.as_of_date
    FROM staged
    JOIN identity ON identity.bronze_record_reference = staged.bronze_record_reference
    CROSS JOIN reference_date
  ),
  screening_flags AS (
    -- A column alias cannot be referenced by another expression in the same
    -- select list, so the shared screening flags are computed in their own step.
    SELECT
      evaluated.*,
      evaluated.screening_type IN ('SANCTIONS', 'PEP', 'WATCHLIST', 'ADVERSE_MEDIA') AS type_is_known,
      evaluated.screening_result IN (
        'CLEAR', 'POTENTIAL_MATCH', 'CONFIRMED_MATCH', 'FALSE_POSITIVE'
      ) AS result_is_known,
      evaluated.screening_result IN ('POTENTIAL_MATCH', 'CONFIRMED_MATCH') AS result_is_alert,
      evaluated.screening_result IN ('CLEAR', 'FALSE_POSITIVE') AS result_is_negative
    FROM evaluated
  ),
  rule_evaluation AS (
    SELECT
      screening_flags.*,
      CASE
        WHEN screening_flags.screening_result = 'CLEAR'
          THEN CASE
            WHEN screening_flags.match_score IS NULL THEN 'NOT_APPLICABLE'
            WHEN screening_flags.match_score >= 0.7500 THEN 'CONFIRMED'
            ELSE 'NOT_APPLICABLE'
          END
        ELSE 'NOT_APPLICABLE'
      END AS clear_with_alert_score_verdict,
      CASE
        WHEN screening_flags.screening_result <> 'CLEAR' THEN 'NOT_APPLICABLE'
        WHEN screening_flags.review_required_flag
          AND COALESCE(screening_flags.match_score, 0) < 0.7500 THEN 'CONFIRMED'
        ELSE 'NOT_APPLICABLE'
      END AS clear_with_review_verdict,
      CASE
        WHEN NOT screening_flags.result_is_alert THEN 'NOT_APPLICABLE'
        WHEN screening_flags.review_required_flag THEN 'NOT_APPLICABLE'
        ELSE 'CONFIRMED'
      END AS review_flag_verdict
    FROM screening_flags
  ),
  rule_findings AS (
    SELECT
      rule_evaluation.*,
      'subject_reference' AS issue_attribute_name,
      'AML_EVENT_SUBJECT_REQUIRED' AS rule_name,
      'AML_SUBJECT_MISSING' AS issue_type,
      'The screening event has no customer and no source customer record; a subject reference is required.' AS issue_description,
      'BLOCKING' AS issue_severity,
      NULL::varchar AS rule_case_type,
      1 AS rule_priority
    FROM rule_evaluation
    WHERE rule_evaluation.customer_id IS NULL
      AND rule_evaluation.source_customer_record_id IS NULL

    UNION ALL

    SELECT
      rule_evaluation.*,
      'subject_reference',
      'AML_IDENTITY_LINK_MISMATCH',
      'AML_IDENTITY_MISMATCH',
      'The screening event is linked to a golden customer and a source customer record that do not represent the same accepted identity.',
      'HIGH',
      'IDENTITY_MISMATCH',
      2
    FROM rule_evaluation
    WHERE rule_evaluation.customer_id IS NOT NULL
      AND rule_evaluation.source_customer_record_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM silver.customer_source_match accepted_match
        WHERE accepted_match.source_customer_record_id = rule_evaluation.source_customer_record_id
          AND accepted_match.customer_id = rule_evaluation.customer_id
          AND accepted_match.match_status = 'ACCEPTED'
          AND accepted_match.is_current_match
      )

    UNION ALL

    SELECT
      rule_evaluation.*,
      'screening_type',
      'AML_SCREENING_TYPE_INVALID',
      'AML_SCREENING_TYPE_INVALID',
      concat('Screening type ', COALESCE(rule_evaluation.screening_type, 'NULL'), ' is not a recognised screening type.'),
      'MEDIUM',
      NULL::varchar,
      3
    FROM rule_evaluation
    WHERE NOT rule_evaluation.type_is_known

    UNION ALL

    SELECT
      rule_evaluation.*,
      'screening_result',
      'AML_SCREENING_RESULT_INVALID',
      'AML_SCREENING_RESULT_INVALID',
      concat('Screening result ', COALESCE(rule_evaluation.screening_result, 'NULL'), ' is not a recognised screening result.'),
      'MEDIUM',
      NULL::varchar,
      3
    FROM rule_evaluation
    WHERE NOT rule_evaluation.result_is_known

    UNION ALL

    SELECT
      rule_evaluation.*,
      'match_score',
      'AML_REVIEW_FLAG_INCONSISTENT',
      'AML_REVIEW_FLAG_MISSING',
      concat(
        'Screening result ',
        rule_evaluation.screening_result,
        ' is an alert but review_required_flag is false; a potential match is not a confirmed finding and must be reviewed.'
      ),
      'HIGH',
      'STATUS_DISCREPANCY',
      2
    FROM rule_evaluation
    WHERE rule_evaluation.review_flag_verdict = 'CONFIRMED'

    UNION ALL

    SELECT
      rule_evaluation.*,
      'screening_result',
      'AML_REVIEW_REQUIRED',
      'AML_SCREENING_ALERT',
      concat(
        'Screening returned ',
        rule_evaluation.screening_result,
        ' with match score ',
        COALESCE(rule_evaluation.match_score::text, 'NULL'),
        '; the alert requires investigation and is not itself a confirmed finding.'
      ),
      'MEDIUM',
      NULL::varchar,
      2
    FROM rule_evaluation
    WHERE rule_evaluation.result_is_alert

    UNION ALL
    SELECT
      rule_evaluation.*,
      'review_required_flag',
      'AML_CLEAR_SCREENING_WITH_REVIEW',
      'AML_STATUS_DISCREPANCY',
      concat(
        'Screening result CLEAR requires review without an alert-level score: match_score ',
        COALESCE(rule_evaluation.match_score::text, 'NULL'),
        '.'
      ),
      'MEDIUM',
      'STATUS_DISCREPANCY',
      3
    FROM rule_evaluation
    WHERE rule_evaluation.clear_with_review_verdict = 'CONFIRMED'

    UNION ALL

    SELECT
      rule_evaluation.*,
      'match_score',
      'AML_CLEAR_SCREENING_SCORE_INCONSISTENT',
      'AML_STATUS_DISCREPANCY',
      concat(
        'Screening result CLEAR carries match_score ',
        rule_evaluation.match_score::text,
        ', which is an alert-level score.'
      ),
      'MEDIUM',
      'STATUS_DISCREPANCY',
      3
    FROM rule_evaluation
    WHERE rule_evaluation.clear_with_alert_score_verdict = 'CONFIRMED'

    UNION ALL

    SELECT
      rule_evaluation.*,
      'match_score',
      'AML_MATCH_SCORE_OUT_OF_RANGE',
      'AML_MATCH_SCORE_INVALID',
      concat('Match score ', rule_evaluation.match_score::text, ' is outside the valid range 0.0000 to 1.0000.'),
      'MEDIUM',
      NULL::varchar,
      3
    FROM rule_evaluation
    WHERE rule_evaluation.match_score IS NOT NULL
      AND (rule_evaluation.match_score < 0 OR rule_evaluation.match_score > 1)

    UNION ALL

    SELECT
      rule_evaluation.*,
      'match_score',
      'AML_MATCH_SCORE_MISSING',
      'AML_MATCH_SCORE_MISSING',
      'An alert result was returned without a match score, so the strength of the match cannot be assessed.',
      'MEDIUM',
      NULL::varchar,
      3
    FROM rule_evaluation
    WHERE rule_evaluation.result_is_alert
      AND rule_evaluation.match_score IS NULL

    UNION ALL

    SELECT
      rule_evaluation.*,
      'customer_id',
      'AML_SCREENING_UNRESOLVED_IDENTITY',
      'AML_IDENTITY_UNRESOLVED',
      'The screening event is retained against a source customer record whose golden customer is not yet confirmed; the report must still include it.',
      'LOW',
      NULL::varchar,
      4
    FROM rule_evaluation
    WHERE rule_evaluation.customer_id IS NULL
      AND rule_evaluation.source_customer_record_id IS NOT NULL
  ),
  ranked AS (
    SELECT
      rule_findings.*,
      row_number() OVER (
        PARTITION BY rule_findings.bronze_record_reference
        ORDER BY
          rule_findings.rule_priority,
          CASE rule_findings.issue_severity
            WHEN 'BLOCKING' THEN 1
            WHEN 'HIGH' THEN 2
            WHEN 'MEDIUM' THEN 3
            ELSE 4
          END,
          rule_findings.rule_name
      ) AS finding_rank
    FROM rule_findings
  )
  SELECT
    ranked.bronze_record_reference::varchar,
    ranked.source_screening_reference::varchar,
    ranked.batch_id::varchar,
    ranked.source_customer_reference::varchar,
    ranked.customer_id::varchar,
    ranked.issue_attribute_name::varchar,
    ranked.rule_name::varchar,
    ranked.issue_type::varchar,
    ranked.issue_description::varchar,
    ranked.issue_severity::varchar,
    ranked.rule_case_type::varchar
  FROM ranked
  WHERE ranked.finding_rank = 1;
$detect_aml$;

COMMENT ON FUNCTION silver.detect_aml_screening_issues(varchar, date) IS
  'Applies the Member 5 AML screening rules to one Bronze batch and returns the highest-priority finding per record.';

-- Registers one finding in silver.data_quality_issue. The identifier is derived
-- from the batch, rule and record so a rerun updates the same row instead of
-- appending a duplicate. Reportable findings are linked to the case that
-- 05_create_case_processing.sql opens or reuses for the same record.
-- Single source of truth for the report's rule requirement: a reportable KYC
-- gap, identity mismatch or status discrepancy must map to KYC_GAP,
-- IDENTITY_MISMATCH or STATUS_DISCREPANCY. A rule that is not reportable returns
-- null and stays a quality record only.
-- The published record identifiers are derived from the source keys, so the
-- case-processing step can address a record by its source reference without
-- reading it back. These functions mirror 03_create_kyc_aml_load_procedures.sql.
CREATE OR REPLACE FUNCTION silver.kyc_verification_id(
  p_source_system_id varchar,
  p_source_kyc_reference varchar
)
RETURNS varchar
LANGUAGE sql
IMMUTABLE
AS $kyc_id$
  SELECT 'KYC-' || upper(substr(md5(p_source_system_id || ':' || p_source_kyc_reference), 1, 16));
$kyc_id$;

CREATE OR REPLACE FUNCTION silver.aml_screening_id(
  p_source_system_id varchar,
  p_source_screening_reference varchar
)
RETURNS varchar
LANGUAGE sql
IMMUTABLE
AS $aml_id$
  SELECT 'AML-' || upper(substr(md5(p_source_system_id || ':' || p_source_screening_reference), 1, 16));
$aml_id$;
CREATE SEQUENCE IF NOT EXISTS silver.compliance_case_seed;

CREATE OR REPLACE FUNCTION silver.compliance_rule_case_type(
  p_rule_name varchar
)
RETURNS varchar
LANGUAGE sql
IMMUTABLE
AS $rule_case_type$
  SELECT CASE p_rule_name
    WHEN 'KYC_VERIFICATION_INCOMPLETE' THEN 'KYC_GAP'
    WHEN 'KYC_VERIFICATION_EXPIRED' THEN 'STATUS_DISCREPANCY'
    WHEN 'KYC_VERIFICATION_STATUS_DISCREPANCY' THEN 'STATUS_DISCREPANCY'
    WHEN 'KYC_IDENTITY_LINK_MISMATCH' THEN 'IDENTITY_MISMATCH'
    WHEN 'AML_IDENTITY_LINK_MISMATCH' THEN 'IDENTITY_MISMATCH'
    WHEN 'AML_REVIEW_REQUIRED' THEN 'AML_SCREENING_REVIEW'
    WHEN 'AML_REVIEW_FLAG_INCONSISTENT' THEN 'STATUS_DISCREPANCY'
    WHEN 'AML_CLEAR_SCREENING_WITH_REVIEW' THEN 'STATUS_DISCREPANCY'
    WHEN 'AML_CLEAR_SCREENING_SCORE_INCONSISTENT' THEN 'STATUS_DISCREPANCY'
    ELSE NULL
  END;
$rule_case_type$;

COMMENT ON FUNCTION silver.compliance_rule_case_type(varchar) IS
  'Maps a validation rule to the case type the report requires, or null when the finding stays a quality record only.';
CREATE OR REPLACE FUNCTION silver.register_compliance_finding(
  p_batch_id varchar,
  p_source_system_id varchar,
  p_entity_name varchar,
  p_record_reference varchar,
  p_record_version_reference varchar,
  p_attribute_name varchar,
  p_rule_name varchar,
  p_issue_type varchar,
  p_issue_description text,
  p_severity varchar,
  p_rule_case_type varchar
)
RETURNS void
LANGUAGE plpgsql
AS $record_issue$
DECLARE
  v_issue_id varchar(50);
BEGIN
  v_issue_id := 'DQ-KYCAML-' || upper(
    substr(
      md5(concat_ws(':', p_batch_id, p_rule_name, p_entity_name, p_record_reference)),
      1,
      16
    )
  );

  -- The case is opened by 05_create_case_processing.sql, which is the single
  -- place that knows how a rule maps to a case type. Linking it here would make
  -- this file depend on the next one, so the link is written there instead.

  INSERT INTO silver.data_quality_issue (
    data_quality_issue_id,
    batch_id,
    source_system_id,
    verification_case_id,
    validation_run_id,
    data_layer,
    entity_name,
    record_reference,
    record_version_reference,
    attribute_name,
    rule_name,
    rule_version,
    issue_type,
    issue_description,
    severity,
    detected_at,
    resolved_at,
    issue_status
  )
  VALUES (
    v_issue_id,
    p_batch_id,
    p_source_system_id,
    NULL,
    'KYC-AML-M5-' || p_batch_id,
    'SILVER',
    p_entity_name,
    p_record_reference,
    p_record_version_reference,
    p_attribute_name,
    p_rule_name,
    '1.0',
    p_issue_type,
    left(p_issue_description, 1000),
    p_severity,
    clock_timestamp(),
    NULL,
    'OPEN'
  )
  ON CONFLICT (data_quality_issue_id) DO UPDATE SET
    verification_case_id = EXCLUDED.verification_case_id,
    attribute_name = EXCLUDED.attribute_name,
    issue_type = EXCLUDED.issue_type,
    issue_description = EXCLUDED.issue_description,
    severity = EXCLUDED.severity,
    detected_at = EXCLUDED.detected_at,
    issue_status = 'OPEN';

  RAISE NOTICE 'Rule % on % produced % issue % (case type %)',
    p_rule_name,
    p_record_reference,
    p_severity,
    v_issue_id,
    COALESCE(p_rule_case_type, 'none');
END;
$record_issue$;

COMMENT ON FUNCTION silver.register_compliance_finding(varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, text, varchar, varchar) IS
  'Registers one KYC/AML validation finding as a Silver data-quality issue and links it to the compliance case that represents it.';

-- The batch-reconciliation step resolves issues by (validation run, rule,
-- record), so index that access path.
CREATE INDEX IF NOT EXISTS ix_data_quality_issue_run_record
  ON silver.data_quality_issue (validation_run_id, rule_name, record_reference);
