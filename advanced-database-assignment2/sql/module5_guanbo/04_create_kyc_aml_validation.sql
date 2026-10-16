-- PostgreSQL 15+
-- Member 5: the KYC/AML validation rules, and registration of findings as data quality issues.
--
-- Layout: identifiers, identity resolution, 8 KYC rules, 10 AML rules, rule-to-case mapping, registration.
-- Design: each record keeps only its most severe finding, ordered by one shared ranking; a rule never
--       opens a case itself, and a NULL batch means every batch at its latest Bronze version.

-- The key is derived from the source system and reference, which gives two properties:
--   1. reprocessing the same data yields the same key, so inserts stay idempotent;
--   2. a published event can be located from its business reference without a lookup.
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

COMMENT ON FUNCTION silver.kyc_verification_id(varchar, varchar) IS
  'Stable verification event key derived from the source system and source KYC reference, so reprocessing adds no duplicate rows.';

COMMENT ON FUNCTION silver.aml_screening_id(varchar, varchar) IS
  'Stable screening event key derived from the source system and source screening reference, as for the KYC version.';

-- Section 2: identity resolution, shared by both detection functions

-- An event has to answer who it is about. This function returns two identifiers:
--   source_customer_record_id: the Silver record for that source customer reference
--   customer_id: the golden customer it merged into, when the merge succeeded
-- Either is NULL when nothing is found, which is how a caller detects an unresolved identity.
CREATE OR REPLACE FUNCTION silver.resolve_event_identity(
  p_entity varchar,
  p_source_system_id varchar,
  p_source_reference varchar,
  p_batch_id varchar
)
RETURNS TABLE (
  source_customer_record_id varchar,
  customer_id varchar
)
LANGUAGE plpgsql
STABLE
AS $resolve_identity$
DECLARE
  v_customer_reference varchar(100);
BEGIN
  -- Read the source customer reference this event points at.
  IF p_entity = 'KYC' THEN
    SELECT btrim(raw.source_customer_reference)
    INTO v_customer_reference
    FROM bronze.raw_kyc_verification raw
    WHERE (p_batch_id IS NULL OR raw.batch_id = p_batch_id)
      AND raw.source_system_id = p_source_system_id
      AND btrim(raw.source_kyc_reference) = p_source_reference
    ORDER BY raw.ingested_at DESC, raw.batch_id DESC, raw.bronze_record_reference DESC
    LIMIT 1;
  ELSIF p_entity = 'AML' THEN
    SELECT btrim(raw.source_customer_reference)
    INTO v_customer_reference
    FROM bronze.raw_aml_screening raw
    WHERE (p_batch_id IS NULL OR raw.batch_id = p_batch_id)
      AND raw.source_system_id = p_source_system_id
      AND btrim(raw.source_screening_reference) = p_source_reference
    ORDER BY raw.ingested_at DESC, raw.batch_id DESC, raw.bronze_record_reference DESC
    LIMIT 1;
  ELSE
    RAISE EXCEPTION 'Unsupported entity %: expected KYC or AML', p_entity;
  END IF;

  SELECT min(source_record.source_customer_record_id)
  INTO source_customer_record_id
  FROM silver.source_customer_record source_record
  WHERE source_record.source_system_id = p_source_system_id
    AND source_record.source_customer_reference = v_customer_reference
    AND source_record.is_current_version;

  -- Only a current ACCEPTED match counts as a confirmed identity.
  SELECT min(current_match.customer_id)
  INTO customer_id
  FROM silver.source_customer_record source_record
  JOIN silver.customer_source_match current_match
    ON current_match.source_customer_record_id = source_record.source_customer_record_id
   AND current_match.is_current_match
   AND current_match.match_status = 'ACCEPTED'
  WHERE source_record.source_system_id = p_source_system_id
    AND source_record.source_customer_reference = v_customer_reference;

  RETURN NEXT;
END;
$resolve_identity$;

COMMENT ON FUNCTION silver.resolve_event_identity(varchar, varchar, varchar, varchar) IS
  'Resolve the source customer record and golden customer for one event. NULL means the identity is not merged yet.';

-- Section 3: the eight KYC verification rules

DROP FUNCTION IF EXISTS silver.detect_kyc_verification_issues(varchar, date);

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
  -- One latest Bronze version per reference; a NULL batch means the latest across all batches.
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
      raw.expiry_date
    FROM bronze.raw_kyc_verification raw
    WHERE p_batch_id IS NULL OR raw.batch_id = p_batch_id
    ORDER BY
      raw.source_system_id,
      btrim(raw.source_kyc_reference),
      raw.ingested_at DESC,
      raw.batch_id DESC,
      raw.bronze_record_reference DESC
  ),
  -- Attach identity, and work out whether the type and status are recognised values.
  evaluated AS (
    SELECT
      staged.*,
      identity.source_customer_record_id,
      identity.customer_id,
      reference_date.as_of_date,
      staged.verification_type IN (
        'IDENTITY_DOCUMENT', 'ADDRESS_VERIFICATION', 'SOURCE_OF_FUNDS',
        'ENHANCED_DUE_DILIGENCE', 'PERIODIC_REVIEW'
      ) AS type_is_known,
      staged.verification_status IN (
        'VERIFIED', 'PENDING', 'MISSING_DOCUMENT', 'FAILED', 'EXPIRED'
      ) AS status_is_known
    FROM staged
    CROSS JOIN reference_date
    CROSS JOIN LATERAL silver.resolve_event_identity(
      'KYC', staged.source_system_id, staged.source_kyc_reference, p_batch_id
    ) identity
  ),
  -- Evaluate the eight rule conditions here; the blocks below project them into findings.
  evaluated_rules AS (
    SELECT
      evaluated.*,
      -- Expired. A verification dated after the reference date is not treated as expired.
      (
        evaluated.expiry_date IS NOT NULL
        AND evaluated.verification_date::date < evaluated.as_of_date
        AND evaluated.expiry_date < evaluated.as_of_date
        AND evaluated.verification_status NOT IN ('PENDING', 'MISSING_DOCUMENT', 'FAILED')
      ) AS is_expired,
      -- Marked verified, but the recorded expiry no longer supports that claim.
      (
        evaluated.verification_status = 'VERIFIED'
        AND (
          evaluated.expiry_date IS NULL
          OR evaluated.expiry_date < evaluated.verification_date::date
          OR evaluated.expiry_date < evaluated.as_of_date
        )
      ) AS is_discrepancy,
      -- Verification did not complete, which is an evidence gap.
      evaluated.verification_status IN ('PENDING', 'MISSING_DOCUMENT', 'FAILED') AS is_gap
    FROM evaluated
  ),
  -- Each rule block carries only what is specific to that rule: e.* expands the shared
  -- evaluated_rules columns, then the rule name, issue type, severity and dedup priority.
  -- The eight rules' hits, projected into one finding list.
  findings AS (
    SELECT
      e.*,
      'subject_reference' AS issue_attribute_name,
      'KYC_EVENT_SUBJECT_REQUIRED' AS rule_name,
      'KYC_SUBJECT_MISSING' AS issue_type,
      'This verification event has neither a golden customer nor a source customer record, so it carries no subject reference.' AS issue_description,
      'BLOCKING' AS issue_severity, NULL::varchar AS rule_case_type, 1 AS rule_priority
    FROM evaluated_rules e
    WHERE e.customer_id IS NULL
      AND e.source_customer_record_id IS NULL

    UNION ALL
    SELECT
      e.*,
      'subject_reference', 'KYC_IDENTITY_LINK_MISMATCH', 'KYC_IDENTITY_MISMATCH',
      'The golden customer and the source customer record on this event are not the same confirmed identity.',
      'HIGH', 'IDENTITY_MISMATCH', 2
    FROM evaluated_rules e
    WHERE e.customer_id IS NOT NULL
      AND e.source_customer_record_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM silver.customer_source_match accepted_match
        WHERE accepted_match.source_customer_record_id = e.source_customer_record_id
          AND accepted_match.customer_id = e.customer_id
          AND accepted_match.match_status = 'ACCEPTED'
          AND accepted_match.is_current_match
      )

    UNION ALL
    SELECT
      e.*,
      'verification_type', 'KYC_VERIFICATION_TYPE_INVALID', 'KYC_VERIFICATION_TYPE_INVALID',
      concat('Verification type ', COALESCE(e.verification_type, 'NULL'), ' is not a recognised KYC verification type.'),
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE NOT e.type_is_known

    UNION ALL
    SELECT
      e.*,
      'verification_status', 'KYC_VERIFICATION_STATUS_INVALID', 'KYC_VERIFICATION_STATUS_INVALID',
      concat('Verification status ', COALESCE(e.verification_status, 'NULL'), ' is not a recognised KYC verification status.'),
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE NOT e.status_is_known

    UNION ALL
    SELECT
      e.*,
      'expiry_date', 'KYC_VERIFICATION_EXPIRED', 'KYC_VERIFICATION_EXPIRED',
      concat(
        'Expired by the reporting date. Status ', e.verification_status,
        ', expiry ', COALESCE(e.expiry_date::text, 'NULL'), '.'
      ),
      'HIGH', 'STATUS_DISCREPANCY', 2
    FROM evaluated_rules e
    WHERE e.is_expired

    UNION ALL
    SELECT
      e.*,
      'verification_status', 'KYC_VERIFICATION_STATUS_DISCREPANCY', 'KYC_VERIFICATION_STATUS_DISCREPANCY',
      concat(
        'Marked verified, but the recorded expiry no longer supports it. Expiry ',
        COALESCE(e.expiry_date::text, 'none'),
        ', verified ', e.verification_date::date::text, '.'
      ),
      'HIGH', 'STATUS_DISCREPANCY', 2
    FROM evaluated_rules e
    WHERE e.is_discrepancy

    UNION ALL
    SELECT
      e.*,
      'verification_status', 'KYC_VERIFICATION_INCOMPLETE', 'KYC_VERIFICATION_GAP',
      concat('Verification did not complete. Status ', e.verification_status, '.'),
      'MEDIUM', 'KYC_GAP', 3
    FROM evaluated_rules e
    WHERE e.is_gap

    UNION ALL
    SELECT
      e.*,
      'customer_id', 'KYC_VERIFICATION_UNRESOLVED_IDENTITY', 'KYC_IDENTITY_UNRESOLVED',
      'This verification event sits on a source customer record whose golden customer is not confirmed. The report still has to include it.',
      'LOW', NULL::varchar, 4
    FROM evaluated_rules e
    WHERE e.customer_id IS NULL
      AND e.source_customer_record_id IS NOT NULL
  ),
  -- Keep one finding per record. Both detection functions use this same ranking.
  ranked AS (
    SELECT
      findings.*,
      row_number() OVER (
        PARTITION BY findings.bronze_record_reference
        ORDER BY
          findings.rule_priority,
          CASE findings.issue_severity
            WHEN 'BLOCKING' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4
          END,
          findings.rule_name
      ) AS finding_rank
    FROM findings
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
  'Apply the eight rules to one batch of KYC verification events, returning only the most severe finding per record. A NULL batch checks every batch at its latest version.';

-- Section 4: the ten AML screening rules

DROP FUNCTION IF EXISTS silver.detect_aml_screening_issues(varchar, date);

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
  WITH staged AS (
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
  evaluated AS (
    SELECT
      staged.*,
      identity.source_customer_record_id,
      identity.customer_id,
      staged.screening_type IN ('SANCTIONS', 'PEP', 'WATCHLIST', 'ADVERSE_MEDIA') AS type_is_known,
      staged.screening_result IN (
        'CLEAR', 'POTENTIAL_MATCH', 'CONFIRMED_MATCH', 'FALSE_POSITIVE'
      ) AS result_is_known,
      staged.screening_result IN ('POTENTIAL_MATCH', 'CONFIRMED_MATCH') AS result_is_alert
    FROM staged
    CROSS JOIN LATERAL silver.resolve_event_identity(
      'AML', staged.source_system_id, staged.source_screening_reference, p_batch_id
    ) identity
  ),
  evaluated_rules AS (
    SELECT
      evaluated.*,
      -- No hit but flagged for review, with a score below the alert band: contradictory state.
      (
        evaluated.screening_result = 'CLEAR'
        AND evaluated.review_required_flag
        AND COALESCE(evaluated.match_score, 0) < 0.7500
      ) AS is_clear_with_review,
      -- No hit but carrying an alert-band score: contradictory state.
      (
        evaluated.screening_result = 'CLEAR'
        AND evaluated.match_score IS NOT NULL
        AND evaluated.match_score >= 0.7500
      ) AS is_clear_with_alert_score,
      -- An alert that was not flagged for review: contradictory state.
      (
        evaluated.result_is_alert
        AND NOT evaluated.review_required_flag
      ) AS is_review_flag_missing
    FROM evaluated
  ),
  findings AS (
    SELECT
      e.*,
      'subject_reference' AS issue_attribute_name,
      'AML_EVENT_SUBJECT_REQUIRED' AS rule_name,
      'AML_SUBJECT_MISSING' AS issue_type,
      'This screening event has neither a golden customer nor a source customer record, so it carries no subject reference.' AS issue_description,
      'BLOCKING' AS issue_severity, NULL::varchar AS rule_case_type, 1 AS rule_priority
    FROM evaluated_rules e
    WHERE e.customer_id IS NULL
      AND e.source_customer_record_id IS NULL

    UNION ALL
    SELECT
      e.*,
      'subject_reference', 'AML_IDENTITY_LINK_MISMATCH', 'AML_IDENTITY_MISMATCH',
      'The golden customer and the source customer record on this screening event are not the same confirmed identity.',
      'HIGH', 'IDENTITY_MISMATCH', 2
    FROM evaluated_rules e
    WHERE e.customer_id IS NOT NULL
      AND e.source_customer_record_id IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM silver.customer_source_match accepted_match
        WHERE accepted_match.source_customer_record_id = e.source_customer_record_id
          AND accepted_match.customer_id = e.customer_id
          AND accepted_match.match_status = 'ACCEPTED'
          AND accepted_match.is_current_match
      )

    UNION ALL
    SELECT
      e.*,
      'screening_type', 'AML_SCREENING_TYPE_INVALID', 'AML_SCREENING_TYPE_INVALID',
      concat('Screening type ', COALESCE(e.screening_type, 'NULL'), ' is not a recognised screening type.'),
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE NOT e.type_is_known

    UNION ALL
    SELECT
      e.*,
      'screening_result', 'AML_SCREENING_RESULT_INVALID', 'AML_SCREENING_RESULT_INVALID',
      concat('Screening result ', COALESCE(e.screening_result, 'NULL'), ' is not a recognised screening result.'),
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE NOT e.result_is_known

    UNION ALL
    SELECT
      e.*,
      'match_score', 'AML_REVIEW_FLAG_INCONSISTENT', 'AML_REVIEW_FLAG_MISSING',
      concat(
        'Screening result ', e.screening_result,
        ' is an alert but review_required_flag is false. A suspected hit has to be reviewed.'
      ),
      'HIGH', 'STATUS_DISCREPANCY', 2
    FROM evaluated_rules e
    WHERE e.is_review_flag_missing

    UNION ALL
    SELECT
      e.*,
      'screening_result', 'AML_REVIEW_REQUIRED', 'AML_SCREENING_ALERT',
      concat(
        'Screening result ', e.screening_result,
        ', similarity ', COALESCE(e.match_score::text, 'NULL'),
        '. This is an alert that needs investigation, not a confirmed problem.'
      ),
      'MEDIUM', NULL::varchar, 2
    FROM evaluated_rules e
    WHERE e.result_is_alert

    UNION ALL
    SELECT
      e.*,
      'review_required_flag', 'AML_CLEAR_SCREENING_WITH_REVIEW', 'AML_STATUS_DISCREPANCY',
      concat(
        'Result is no match but review is required, with a similarity below the alert band: ',
        COALESCE(e.match_score::text, 'NULL'), '。'
      ),
      'MEDIUM', 'STATUS_DISCREPANCY', 3
    FROM evaluated_rules e
    WHERE e.is_clear_with_review

    UNION ALL
    SELECT
      e.*,
      'match_score', 'AML_CLEAR_SCREENING_SCORE_INCONSISTENT', 'AML_STATUS_DISCREPANCY',
      concat('Result is no match yet it carries an alert-band similarity of ', e.match_score::text, '.'),
      'MEDIUM', 'STATUS_DISCREPANCY', 3
    FROM evaluated_rules e
    WHERE e.is_clear_with_alert_score

    UNION ALL
    SELECT
      e.*,
      'match_score', 'AML_MATCH_SCORE_OUT_OF_RANGE', 'AML_MATCH_SCORE_INVALID',
      concat('Similarity ', e.match_score::text, ' is outside the valid range 0.0000 to 1.0000.'),
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE e.match_score IS NOT NULL
      AND (e.match_score < 0 OR e.match_score > 1)

    UNION ALL
    SELECT
      e.*,
      'match_score', 'AML_MATCH_SCORE_MISSING', 'AML_MATCH_SCORE_MISSING',
      'An alert is reported with no similarity score, so the strength of the hit cannot be judged.',
      'MEDIUM', NULL::varchar, 3
    FROM evaluated_rules e
    WHERE e.result_is_alert
      AND e.match_score IS NULL

    UNION ALL
    SELECT
      e.*,
      'customer_id', 'AML_SCREENING_UNRESOLVED_IDENTITY', 'AML_IDENTITY_UNRESOLVED',
      'This screening event sits on a source customer record whose golden customer is not confirmed. The report still has to include it.',
      'LOW', NULL::varchar, 4
    FROM evaluated_rules e
    WHERE e.customer_id IS NULL
      AND e.source_customer_record_id IS NOT NULL
  ),
  ranked AS (
    SELECT
      findings.*,
      row_number() OVER (
        PARTITION BY findings.bronze_record_reference
        ORDER BY
          findings.rule_priority,
          CASE findings.issue_severity
            WHEN 'BLOCKING' THEN 1 WHEN 'HIGH' THEN 2 WHEN 'MEDIUM' THEN 3 ELSE 4
          END,
          findings.rule_name
      ) AS finding_rank
    FROM findings
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
  'Apply the ten rules to one batch of AML screening events, returning only the most severe finding per record. A NULL batch checks every batch at its latest version.';

-- Section 5: rule to case-type mapping, the single source for the reporting rule

CREATE SEQUENCE IF NOT EXISTS silver.compliance_case_seed;

-- The report requires a reportable KYC gap, identity mismatch or status discrepancy to open
-- one of KYC_GAP, IDENTITY_MISMATCH or STATUS_DISCREPANCY.
-- This function is where that requirement lands, so the mapping changes without touching the rules.
-- A NULL result means the rule stays a quality record, for example the LOW unresolved identity.
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
  'The single rule-to-case-type mapping. A NULL result means the rule stays a quality record and opens no case.';

-- Section 6: finding registration

-- Register one finding as a Silver data quality issue.
--
-- The issue key is derived from batch, rule and record, so a rerun updates that one row
-- instead of adding another. The issue starts OPEN and is resolved by
-- 05_create_case_processing.sql once the rules stop reporting it.
-- Returns the case type for that rule, for the case-opening step to use.
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
RETURNS varchar
LANGUAGE plpgsql
AS $register_finding$
DECLARE
  v_issue_id varchar(50);
  v_case_type varchar(50);
BEGIN
  v_issue_id := 'DQ-KYCAML-' || upper(
    substr(
      md5(concat_ws(':', p_batch_id, p_rule_name, p_entity_name, p_record_reference)),
      1,
      16
    )
  );

  v_case_type := silver.compliance_rule_case_type(p_rule_name);

  -- The case itself is opened by 05_create_case_processing.sql, so no case reference is
  -- written here, which keeps this file independent of the next one.
  INSERT INTO silver.data_quality_issue (
    data_quality_issue_id, batch_id, source_system_id, verification_case_id,
    validation_run_id, data_layer, entity_name, record_reference,
    record_version_reference, attribute_name, rule_name, rule_version,
    issue_type, issue_description, severity, detected_at, resolved_at, issue_status
  )
  VALUES (
    v_issue_id, p_batch_id, p_source_system_id, NULL,
    'KYC-AML-M5-' || p_batch_id, 'SILVER', p_entity_name, p_record_reference,
    p_record_version_reference, p_attribute_name, p_rule_name, '1.0',
    p_issue_type, left(p_issue_description, 1000), p_severity,
    clock_timestamp(), NULL, 'OPEN'
  )
  ON CONFLICT (data_quality_issue_id) DO UPDATE SET
    attribute_name = EXCLUDED.attribute_name,
    issue_type = EXCLUDED.issue_type,
    issue_description = EXCLUDED.issue_description,
    severity = EXCLUDED.severity,
    detected_at = EXCLUDED.detected_at,
    issue_status = 'OPEN';

  RETURN v_case_type;
END;
$register_finding$;

COMMENT ON FUNCTION silver.register_compliance_finding(varchar, varchar, varchar, varchar, varchar, varchar, varchar, varchar, text, varchar, varchar) IS
  'Register one validation finding as a data quality issue and return the case type for its rule.';

-- Issues are located and closed by validation batch, rule and record, so that path is indexed.
CREATE INDEX IF NOT EXISTS ix_data_quality_issue_run_record
  ON silver.data_quality_issue (validation_run_id, rule_name, record_reference);
