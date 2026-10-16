-- =============================================================================
-- CloudBeaver bundle 02: validation
-- Target: PostgreSQL 15+ through CloudBeaver
-- Run only after 01_full_deployment.sql has completed successfully.
-- Upload this file to the SQL Editor and execute the whole script with Alt+X.
-- Use a new, empty database for the first deployment.
-- Source-file boundary comments are retained for error tracing.
-- =============================================================================

-- >>> BEGIN SOURCE FILE: sql/hongfei/07_validation_tests.sql

-- Validates the Member 1 pipeline after scripts 01-06 have run.

DO $member1_tests$
DECLARE
  v_count integer;
  v_text text;
BEGIN
  -- Verifies all initial batches and their retained Bronze record counts.
  SELECT count(*)::integer
  INTO v_count
  FROM silver.ingestion_batch
  WHERE load_type = 'INITIAL'
    AND load_status = 'SUCCEEDED'
    AND records_received = records_processed;

  IF v_count <> 3 THEN
    RAISE EXCEPTION 'Expected three successful initial batches, found %', v_count;
  END IF;

  IF silver.count_bronze_batch_records('B1-CRM') <> 34 THEN
    RAISE EXCEPTION 'B1-CRM Bronze count is not 34';
  END IF;

  IF silver.count_bronze_batch_records('B1-LEND') <> 12 THEN
    RAISE EXCEPTION 'B1-LEND Bronze count is not 12';
  END IF;

  IF silver.count_bronze_batch_records('B1-AMLKYC') <> 27 THEN
    RAISE EXCEPTION 'B1-AMLKYC Bronze count is not 27';
  END IF;

  IF silver.count_bronze_batch_records('B2-CRM') <> 12 THEN
    RAISE EXCEPTION 'B2-CRM Bronze count is not 12';
  END IF;

  IF silver.count_bronze_batch_records('B2-LEND') <> 6 THEN
    RAISE EXCEPTION 'B2-LEND Bronze count is not 6';
  END IF;

  IF silver.count_bronze_batch_records('B2-AMLKYC') <> 1 THEN
    RAISE EXCEPTION 'B2-AMLKYC Bronze count is not 1';
  END IF;

  -- Verifies the expected success or failure state of each incremental batch.
  SELECT load_status
  INTO v_text
  FROM silver.ingestion_batch
  WHERE batch_id = 'B2-CRM';

  IF v_text IS DISTINCT FROM 'SUCCEEDED' THEN
    RAISE EXCEPTION 'B2-CRM should be SUCCEEDED, found %', v_text;
  END IF;

  SELECT load_status
  INTO v_text
  FROM silver.ingestion_batch
  WHERE batch_id = 'B2-LEND';

  IF v_text IS DISTINCT FROM 'SUCCEEDED' THEN
    RAISE EXCEPTION 'B2-LEND should be SUCCEEDED, found %', v_text;
  END IF;

  SELECT load_status
  INTO v_text
  FROM silver.ingestion_batch
  WHERE batch_id = 'B2-AMLKYC';

  IF v_text IS DISTINCT FROM 'FAILED' THEN
    RAISE EXCEPTION 'B2-AMLKYC should be FAILED, found %', v_text;
  END IF;

  -- Verifies that only successful batches advanced their source watermark.
  SELECT watermark_end
  INTO v_text
  FROM silver.vw_latest_successful_watermark
  WHERE source_system_id = 'CRM';

  IF v_text IS DISTINCT FROM '2026-09-15' THEN
    RAISE EXCEPTION 'CRM committed watermark should be 2026-09-15, found %', v_text;
  END IF;

  SELECT watermark_end
  INTO v_text
  FROM silver.vw_latest_successful_watermark
  WHERE source_system_id = 'LEND';

  IF v_text IS DISTINCT FROM '2026-09-15' THEN
    RAISE EXCEPTION 'LEND committed watermark should be 2026-09-15, found %', v_text;
  END IF;

  SELECT watermark_end
  INTO v_text
  FROM silver.vw_latest_successful_watermark
  WHERE source_system_id = 'AMLKYC';

  IF v_text IS DISTINCT FROM '2026-09-01' THEN
    RAISE EXCEPTION 'AMLKYC watermark should remain 2026-09-01, found %', v_text;
  END IF;

  -- Verifies raw CDC retention and publication of valid events only.
  SELECT count(*)::integer
  INTO v_count
  FROM bronze.cdc_change_event;

  IF v_count <> 19 THEN
    RAISE EXCEPTION 'Expected 19 retained Bronze CDC events, found %', v_count;
  END IF;

  SELECT count(*)::integer
  INTO v_count
  FROM silver.cdc_change_event;

  IF v_count <> 18 THEN
    RAISE EXCEPTION 'Expected 18 valid Silver CDC events, found %', v_count;
  END IF;

  -- Verifies retained delete/error evidence and failure resolution after retry.
  IF NOT EXISTS (
    SELECT 1
    FROM bronze.raw_crm_customer
    WHERE source_customer_reference = 'CRM-007'
      AND operation_type = 'D'
  ) THEN
    RAISE EXCEPTION 'CRM-007 deletion marker was not retained in Bronze';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM bronze.cdc_change_event
    WHERE change_event_id = 'CDC-019'
      AND operation_type = ''
  ) THEN
    RAISE EXCEPTION 'Invalid CDC-019 raw event was not retained in Bronze';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM silver.data_quality_issue
    WHERE batch_id = 'B2-AMLKYC'
      AND rule_name = 'incremental_batch_validation'
      AND issue_status = 'OPEN'
  ) THEN
    RAISE EXCEPTION 'Expected an open blocking issue for B2-AMLKYC';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM silver.data_quality_issue
    WHERE batch_id = 'B2-CRM'
      AND rule_name = 'forced_failure_demo'
      AND issue_status = 'RESOLVED'
  ) THEN
    RAISE EXCEPTION 'B2-CRM forced-failure issue was not resolved by retry';
  END IF;

  RAISE NOTICE 'All Member 1 acceptance tests passed';
END
$member1_tests$;

-- Displays batch, watermark, CDC and load-quality evidence.
SELECT
  batch_id,
  source_system_id,
  load_type,
  load_status,
  records_received,
  records_processed,
  watermark_start,
  watermark_end
FROM silver.ingestion_batch
ORDER BY source_system_id, started_at, batch_id;

SELECT *
FROM silver.vw_latest_successful_watermark
ORDER BY source_system_id;

SELECT
  batch_id,
  source_system_id,
  source_entity_name,
  operation_type,
  count(*) AS event_count,
  min(event_sequence) AS first_sequence,
  max(event_sequence) AS last_sequence
FROM silver.cdc_change_event
GROUP BY
  batch_id,
  source_system_id,
  source_entity_name,
  operation_type
ORDER BY batch_id, source_entity_name, operation_type;

SELECT
  batch_id,
  rule_name,
  severity,
  issue_status,
  issue_description
FROM silver.data_quality_issue
WHERE issue_type = 'LOAD_VALIDATION'
ORDER BY batch_id, detected_at;

-- <<< END SOURCE FILE: sql/hongfei/07_validation_tests.sql

-- >>> BEGIN SOURCE FILE: sql/mina/05_validation_tests.sql

-- Module 2: CUSTOMER IDENTITY MATCHING
-- Step 5: Simple validation checks

-- Test 1: Silver keeps all successful source versions
SELECT
    'Test 1 - source versions' AS test_name,
    COUNT(*) AS actual_rows,
    28 AS expected_rows
FROM silver.source_customer_record;

-- Test 2: Only current non-deleted source records are used for matching
SELECT
    'Test 2 - current source records' AS test_name,
    COUNT(*) AS actual_rows,
    25 AS expected_rows
FROM silver.source_customer_record
WHERE is_current_version = TRUE;

-- Test 3: Number of accepted enterprise customers
SELECT
    'Test 3 - enterprise customers' AS test_name,
    COUNT(DISTINCT customer_id) AS actual_rows,
    13 AS expected_rows
FROM silver.customer_source_match
WHERE is_current_match = TRUE
  AND match_status = 'ACCEPTED';

-- Test 4: Alice should have three source records sharing one customer ID
SELECT
    'Test 4 - Alice' AS test_name,
    COUNT(*) AS source_records,
    COUNT(DISTINCT m.customer_id) AS customer_ids
FROM silver.customer_source_match m
JOIN silver.source_customer_record scr
  ON m.source_customer_record_id = scr.source_customer_record_id
WHERE m.is_current_match = TRUE
  AND (
         (scr.source_system_id = 'CRM'
          AND scr.source_customer_reference = 'CRM-001')
      OR (scr.source_system_id = 'LEND'
          AND scr.source_customer_reference = 'LEND-001')
      OR (scr.source_system_id = 'AMLKYC'
          AND scr.source_customer_reference = 'KYC-001')
  );

-- Test 5: Daniel's Lending record should require manual review.
SELECT
    'Test 5 - Daniel' AS test_name,
    m.match_status,
    m.manual_review_flag,
    m.customer_id
FROM silver.customer_source_match m
JOIN silver.source_customer_record scr
  ON m.source_customer_record_id = scr.source_customer_record_id
WHERE m.is_current_match = TRUE
  AND scr.source_system_id = 'LEND'
  AND scr.source_customer_reference = 'LEND-002';

-- Test 6: Ethan should use CRM version 2 after the email update
SELECT
    'Test 6 - Ethan current version' AS test_name,
    scr.source_system_id,
    scr.source_customer_reference,
    scr.source_record_version,
    m.customer_id
FROM silver.source_customer_record scr
JOIN silver.customer_source_match m
  ON scr.source_customer_record_id = m.source_customer_record_id
WHERE scr.is_current_version = TRUE
  AND m.is_current_match = TRUE
  AND (
         (scr.source_system_id = 'CRM'
          AND scr.source_customer_reference = 'CRM-006')
      OR (scr.source_system_id = 'AMLKYC'
          AND scr.source_customer_reference = 'KYC-006')
  )
ORDER BY scr.source_system_id;

-- Test 7: Ava's deleted CRM record should not have a current match
SELECT
    'Test 7 - Ava deleted' AS test_name,
    COUNT(*) AS current_matches,
    0 AS expected_matches
FROM silver.customer_source_match m
JOIN silver.source_customer_record scr
  ON m.source_customer_record_id = scr.source_customer_record_id
WHERE m.is_current_match = TRUE
  AND scr.source_system_id = 'CRM'
  AND scr.source_customer_reference = 'CRM-007';

-- Final output
SELECT
    scr.source_system_id,
    scr.source_customer_reference,
    scr.source_full_name,
    m.customer_id,
    m.match_status,
    m.match_confidence_score,
    m.match_rule
FROM silver.source_customer_record scr
JOIN silver.customer_source_match m
  ON scr.source_customer_record_id = m.source_customer_record_id
WHERE scr.is_current_version = TRUE
  AND m.is_current_match = TRUE
ORDER BY
    COALESCE(m.customer_id, 'ZZZ'),
    scr.source_system_id,
    scr.source_customer_reference;

-- <<< END SOURCE FILE: sql/mina/05_validation_tests.sql

-- >>> BEGIN SOURCE FILE: sql/kaijie/03_validation_tests.sql

-- Run after CALL silver.apply_member3_survivorship().
-- These structural checks work on B1 or B2. Empty data is a FAIL.
WITH checks AS (
 SELECT '01 populated master and provenance' AS test_name,
   EXISTS(SELECT 1 FROM silver.customer_attribute_source) AS ok
 UNION ALL
 SELECT '02 current provenance uses current accepted matching and successful batch',
   NOT EXISTS (
     SELECT 1 FROM silver.customer_attribute_source p
     JOIN silver.customer_source_match m USING(match_id)
     JOIN silver.source_customer_record s USING(source_customer_record_id)
     JOIN silver.ingestion_batch b USING(batch_id)
     WHERE p.is_current AND (m.match_status <> 'ACCEPTED' OR NOT m.is_current_match
       OR m.customer_id IS DISTINCT FROM p.customer_id OR NOT s.is_current_version
       OR m.effective_to IS NOT NULL OR s.valid_to IS NOT NULL
       OR b.load_status <> 'SUCCEEDED' OR b.source_system_id <> s.source_system_id))
 UNION ALL
 SELECT '03 one current selection per customer attribute', NOT EXISTS (
   SELECT 1 FROM silver.customer_attribute_source WHERE is_current
   GROUP BY customer_id, attribute_name HAVING count(*) > 1)
 UNION ALL
 SELECT '04 current selected values equal master attributes', NOT EXISTS (
   SELECT 1 FROM silver.customer_attribute_source p
   JOIN silver.customer_master c USING(customer_id)
   WHERE p.is_current AND p.selected_value IS DISTINCT FROM (to_jsonb(c)->>p.attribute_name))
 UNION ALL
 SELECT '05 historical selection matches customer and attribute', NOT EXISTS (
   SELECT 1 FROM silver.customer_history h JOIN silver.customer_attribute_source p USING(attribute_source_id)
   WHERE h.customer_id <> p.customer_id OR h.attribute_name <> p.attribute_name
     OR h.new_value IS DISTINCT FROM p.selected_value)
 UNION ALL
 SELECT '06 no overlapping provenance periods', NOT EXISTS (
   SELECT 1 FROM silver.customer_attribute_source a JOIN silver.customer_attribute_source b
     ON a.customer_id=b.customer_id AND a.attribute_name=b.attribute_name
     AND a.attribute_source_id < b.attribute_source_id
   WHERE tsrange(a.effective_from,a.effective_to,'[)') && tsrange(b.effective_from,b.effective_to,'[)'))
 UNION ALL
 SELECT '07 no overlapping value history periods', NOT EXISTS (
   SELECT 1 FROM silver.customer_history a JOIN silver.customer_history b
     ON a.customer_id=b.customer_id AND a.attribute_name=b.attribute_name
     AND a.customer_history_id < b.customer_history_id
   WHERE tsrange(a.effective_from,a.effective_to,'[)') && tsrange(b.effective_from,b.effective_to,'[)'))
 UNION ALL
 SELECT '08 every v1 selection has source-to-master lineage', NOT EXISTS (
   SELECT 1 FROM silver.customer_attribute_source p WHERE p.survivorship_rule LIKE 'v1:%'
   AND NOT EXISTS (SELECT 1 FROM silver.data_lineage_record l
     WHERE l.transformation_name='member3_attribute_survivorship'
       AND l.target_record_reference=p.customer_id AND l.target_attribute_name=p.attribute_name
       AND (l.target_record_snapshot::jsonb->>'attribute_source_id')=p.attribute_source_id))
 UNION ALL
 SELECT '09 no-source status has no current source selections', NOT EXISTS (
   SELECT 1 FROM silver.customer_master c JOIN silver.customer_attribute_source p USING(customer_id)
   WHERE c.customer_status='NO_CURRENT_SOURCE' AND p.is_current)
)
SELECT test_name, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result FROM checks ORDER BY test_name;

-- Prove exact rerun equality for all four output tables, including timestamps.
-- The trial call is rolled back. Run this whole transaction together.
BEGIN;
CREATE TEMP TABLE member3_before_master ON COMMIT DROP AS TABLE silver.customer_master;
CREATE TEMP TABLE member3_before_source ON COMMIT DROP AS TABLE silver.customer_attribute_source;
CREATE TEMP TABLE member3_before_history ON COMMIT DROP AS TABLE silver.customer_history;
CREATE TEMP TABLE member3_before_lineage ON COMMIT DROP AS TABLE silver.data_lineage_record;
CALL silver.apply_member3_survivorship();
SELECT '10 exact rerun leaves four output tables unchanged' AS test_name,
 CASE WHEN NOT EXISTS (
   (SELECT * FROM silver.customer_master EXCEPT ALL SELECT * FROM member3_before_master)
   UNION ALL (SELECT * FROM member3_before_master EXCEPT ALL SELECT * FROM silver.customer_master)
 ) AND NOT EXISTS (
   (SELECT * FROM silver.customer_attribute_source EXCEPT ALL SELECT * FROM member3_before_source)
   UNION ALL (SELECT * FROM member3_before_source EXCEPT ALL SELECT * FROM silver.customer_attribute_source)
 ) AND NOT EXISTS (
   (SELECT * FROM silver.customer_history EXCEPT ALL SELECT * FROM member3_before_history)
   UNION ALL (SELECT * FROM member3_before_history EXCEPT ALL SELECT * FROM silver.customer_history)
 ) AND NOT EXISTS (
   (SELECT * FROM silver.data_lineage_record EXCEPT ALL SELECT * FROM member3_before_lineage)
   UNION ALL (SELECT * FROM member3_before_lineage EXCEPT ALL SELECT * FROM silver.data_lineage_record)
 ) THEN 'PASS' ELSE 'FAIL' END AS result;
ROLLBACK;

-- Screenshots: current values and the source chosen for each attribute.
SELECT c.customer_id,c.customer_full_name,c.email_address,c.residential_address,c.customer_status,
 p.attribute_name,p.selected_value,s.source_system_id,s.source_customer_reference,
 s.source_record_version,p.survivorship_rule
FROM silver.customer_master c
LEFT JOIN silver.customer_attribute_source p ON p.customer_id=c.customer_id AND p.is_current
LEFT JOIN silver.customer_source_match m USING(match_id)
LEFT JOIN silver.source_customer_record s USING(source_customer_record_id)
ORDER BY c.customer_id,p.attribute_name;

SELECT customer_id,attribute_name,old_value,new_value,effective_from,effective_to,change_reason
FROM silver.customer_history ORDER BY effective_from,customer_id,attribute_name;

-- <<< END SOURCE FILE: sql/kaijie/03_validation_tests.sql

-- >>> BEGIN SOURCE FILE: sql/guanbo/08_validation_tests.sql

-- PostgreSQL 15+
-- Member 5 acceptance tests: assert the business result, then print the report-ready queries.
-- Run files 00-07 in filename order, then call:
--
--   CALL silver.process_kyc_aml_batch('B1-AMLKYC', DATE '2026-09-30');
--   CALL silver.process_kyc_aml_batch('B2-AMLKYC', DATE '2026-09-30');
--   CALL silver.publish_compliance_cases();
--   CALL silver.progress_compliance_cases(DATE '2026-09-30');
--   CALL gold.refresh_compliance_exception_fact(DATE '2026-09-30');
--
-- The reference date is 2026-09-30, after both batches, so VFY-012 (expiry 2026-08-15) is expired.

DO $member5_tests$
DECLARE
  v_count integer;
  v_other_count integer;
  v_text text;
  v_reference_date date := DATE '2026-09-30';
  v_kyc_published integer;
  v_aml_published integer;
  v_b2_aml_published integer;
  v_verification_cases integer;
  v_aml_cases integer;
  v_fact_rows integer;
  v_orphan_rows integer;
  v_duplicate_cases integer;
  v_pending_links integer;
  v_cases_before integer;
  v_cases_after integer;
BEGIN
  -- 1. Both batches published their events, including the batch Member 1 marks FAILED for a blank operation_type.
  SELECT count(*)::integer INTO v_kyc_published
  FROM silver.kyc_verification_record
  WHERE source_system_id = 'AMLKYC';

  IF v_kyc_published <> 9 THEN
    RAISE EXCEPTION 'Expected 9 published KYC verification records, found %', v_kyc_published;
  END IF;

  SELECT count(*)::integer INTO v_aml_published
  FROM silver.aml_screening_result
  WHERE source_system_id = 'AMLKYC';

  IF v_aml_published <> 10 THEN
    RAISE EXCEPTION 'Expected 10 published AML screening results, found %', v_aml_published;
  END IF;


  SELECT count(*)::integer INTO v_b2_aml_published
  FROM silver.aml_screening_result screening
  JOIN silver.data_lineage_record lineage
    ON lineage.target_record_reference = screening.aml_screening_id
  WHERE lineage.batch_id = 'B2-AMLKYC';

  IF v_b2_aml_published <> 1 THEN
    RAISE EXCEPTION
      'Expected the failed B2-AMLKYC batch to contribute 1 screening event, found %',
      v_b2_aml_published;
  END IF;

  -- 2. Every event still carries a subject reference.
  SELECT count(*)::integer INTO v_count
  FROM silver.kyc_verification_record
  WHERE customer_id IS NULL AND source_customer_record_id IS NULL;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Blocking KYC subject rule did not withhold % records', v_count;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM silver.aml_screening_result
  WHERE customer_id IS NULL AND source_customer_record_id IS NULL;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Blocking AML subject rule did not withhold % records', v_count;
  END IF;

  -- 3. No blocking finding is registered against a published event.
  SELECT count(*)::integer INTO v_count
  FROM silver.data_quality_issue
  WHERE validation_run_id LIKE 'KYC-AML-M5-%'
    AND severity = 'BLOCKING';

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Found % blocking issues on published events', v_count;
  END IF;

  -- 4. The reportable findings the supplied data must produce.
  SELECT count(*)::integer INTO v_count
  FROM silver.data_quality_issue
  WHERE validation_run_id LIKE 'KYC-AML-M5-%'
    AND rule_name = 'KYC_VERIFICATION_INCOMPLETE';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Expected 1 KYC gap finding (VFY-004), found %', v_count;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM silver.data_quality_issue
  WHERE validation_run_id LIKE 'KYC-AML-M5-%'
    AND rule_name = 'KYC_VERIFICATION_EXPIRED';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Expected 1 expired verification finding (VFY-012), found %', v_count;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM silver.data_quality_issue
  WHERE validation_run_id LIKE 'KYC-AML-M5-%'
    AND rule_name = 'AML_REVIEW_REQUIRED';

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'Expected 1 AML screening alert finding (SCR-005-2), found %', v_count;
  END IF;

  -- 5. Case types are limited to the values the report requires.
  SELECT count(*)::integer INTO v_count
  FROM silver.special_verification_case
  WHERE case_type IN ('KYC_GAP', 'IDENTITY_MISMATCH', 'STATUS_DISCREPANCY');

  SELECT count(*)::integer INTO v_other_count
  FROM silver.special_verification_case;

  IF v_count <> v_other_count THEN
    RAISE EXCEPTION
      'Found % verification cases outside the report case types, expected 0',
      v_other_count - v_count;
  END IF;

  SELECT count(*)::integer INTO v_verification_cases FROM silver.special_verification_case;
  SELECT count(*)::integer INTO v_aml_cases FROM silver.aml_case;

  -- Only the gap and status-discrepancy rules open a case. The LOW unresolved-identity notice
  -- stays a quality record.
  IF v_verification_cases <> 2 THEN
    RAISE EXCEPTION 'Expected 2 verification cases, found %', v_verification_cases;
  END IF;

  IF v_aml_cases <> 1 THEN
    RAISE EXCEPTION 'Expected 1 AML case, found %', v_aml_cases;
  END IF;

  -- 6. Every open finding whose rule maps to a case type has a case.
  SELECT count(*)::integer INTO v_pending_links
  FROM silver.data_quality_issue issue
  WHERE issue.validation_run_id LIKE 'KYC-AML-M5-%'
    AND issue.issue_status = 'OPEN'
    AND issue.entity_name = 'KYC_VERIFICATION_RECORD'
    AND silver.compliance_rule_case_type(issue.rule_name) IS NOT NULL
    AND issue.verification_case_id IS NULL;

  IF v_pending_links <> 0 THEN
    RAISE EXCEPTION
      '% reportable open KYC findings have no verification case',
      v_pending_links;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM silver.data_quality_issue issue
  WHERE issue.validation_run_id LIKE 'KYC-AML-M5-%'
    AND issue.issue_status = 'OPEN'
    AND silver.compliance_rule_case_type(issue.rule_name) IS NULL
    AND issue.verification_case_id IS NOT NULL;

  IF v_count <> 0 THEN
    RAISE EXCEPTION
      '% non-reportable findings were linked to a verification case',
      v_count;
  END IF;

  -- The case must point at the finding's own event, not another one.
  SELECT count(*)::integer INTO v_count
  FROM silver.data_quality_issue issue
  JOIN silver.special_verification_case investigation
    ON investigation.verification_case_id = issue.verification_case_id
  JOIN silver.kyc_verification_record verification
    ON verification.kyc_verification_id = investigation.kyc_verification_id
  WHERE issue.validation_run_id LIKE 'KYC-AML-M5-%'
    AND issue.entity_name = 'KYC_VERIFICATION_RECORD'
    AND verification.source_kyc_reference <> issue.record_reference;

  IF v_count <> 0 THEN
    RAISE EXCEPTION
      '% verification cases are linked to a different event than their finding',
      v_count;
  END IF;

  -- 7. Case status and closing timestamp agree.
  SELECT count(*)::integer INTO v_count
  FROM silver.special_verification_case
  WHERE (case_status IN ('RESOLVED', 'CLOSED') AND resolved_at IS NULL)
     OR (case_status IN ('OPEN', 'IN_REVIEW') AND resolved_at IS NOT NULL);

  IF v_count <> 0 THEN
    RAISE EXCEPTION '% verification cases have an inconsistent status and resolution', v_count;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM silver.aml_case
  WHERE (case_status = 'CLOSED' AND closed_at IS NULL)
     OR (case_status <> 'CLOSED' AND closed_at IS NOT NULL);

  IF v_count <> 0 THEN
    RAISE EXCEPTION '% AML cases have an inconsistent status and closing date', v_count;
  END IF;

  -- 8. The accumulating fact holds one row per source case.
  SELECT count(*)::integer INTO v_fact_rows FROM gold.fact_compliance_exception;

  IF v_fact_rows <> v_verification_cases + v_aml_cases THEN
    RAISE EXCEPTION
      'Exception fact holds % rows for % originating cases',
      v_fact_rows,
      v_verification_cases + v_aml_cases;
  END IF;

  SELECT count(*)::integer INTO v_duplicate_cases
  FROM (
    SELECT verification_case_id
    FROM gold.fact_compliance_exception
    WHERE verification_case_id IS NOT NULL
    GROUP BY verification_case_id
    HAVING count(*) > 1
    UNION ALL
    SELECT aml_case_id
    FROM gold.fact_compliance_exception
    WHERE aml_case_id IS NOT NULL
    GROUP BY aml_case_id
    HAVING count(*) > 1
  ) duplicated;

  IF v_duplicate_cases <> 0 THEN
    RAISE EXCEPTION '% originating cases appear more than once in the fact', v_duplicate_cases;
  END IF;

  -- 9. Each fact row holds exactly one case reference, agreeing with its source type.
  SELECT count(*)::integer INTO v_orphan_rows
  FROM gold.fact_compliance_exception
  WHERE (verification_case_id IS NULL AND aml_case_id IS NULL)
     OR (verification_case_id IS NOT NULL AND aml_case_id IS NOT NULL);

  IF v_orphan_rows <> 0 THEN
    RAISE EXCEPTION '% exception fact rows do not carry exactly one case', v_orphan_rows;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM gold.fact_compliance_exception
  WHERE (exception_source_type = 'VERIFICATION' AND verification_case_id IS NULL)
     OR (exception_source_type = 'AML' AND aml_case_id IS NULL);

  IF v_count <> 0 THEN
    RAISE EXCEPTION '% exception fact rows disagree with exception_source_type', v_count;
  END IF;

  -- 10. Age agrees with the dates behind it and never exceeds the reporting date.
  SELECT count(*)::integer INTO v_count
  FROM gold.fact_compliance_exception
  WHERE days_open <> GREATEST(
    LEAST(COALESCE(resolved_date, as_of_date), as_of_date) - opened_date,
    0
  );

  IF v_count <> 0 THEN
    RAISE EXCEPTION '% exception fact rows have an incorrect days_open', v_count;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM gold.fact_compliance_exception
  WHERE days_open < 0;

  IF v_count <> 0 THEN
    RAISE EXCEPTION '% exception fact rows have a negative days_open', v_count;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM gold.fact_compliance_exception
  WHERE days_open > as_of_date - opened_date;

  IF v_count <> 0 THEN
    RAISE EXCEPTION
      '% exception fact rows are older than the reporting date',
      v_count;
  END IF;

  -- 11. Exceptions with an unresolved identity appear in the report rather than being dropped.
  -- The assertion is that the report loses no rows: as many rows as the fact holds. That holds
  -- whether identity is resolved or not, in isolation or with the other modules loaded.
  SELECT count(*)::integer INTO v_count
  FROM gold.vw_kyc_aml_exception_report;

  IF v_count <> v_fact_rows THEN
    RAISE EXCEPTION
      'The exception report holds % rows for % exception facts, so rows were dropped',
      v_count,
      v_fact_rows;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM gold.vw_kyc_aml_exception_report
  WHERE customer_name IS NULL;

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'The exception report dropped % rows with an unresolved identity', v_count;
  END IF;

  -- 12. Rules that must not fire on the supplied data.
  SELECT count(*)::integer INTO v_count
  FROM silver.data_quality_issue
  WHERE validation_run_id LIKE 'KYC-AML-M5-%'
    AND rule_name IN (
      'KYC_IDENTITY_LINK_MISMATCH',
      'AML_IDENTITY_LINK_MISMATCH',
      'AML_CLEAR_SCREENING_SCORE_INCONSISTENT',
      'AML_CLEAR_SCREENING_WITH_REVIEW',
      'KYC_VERIFICATION_TYPE_INVALID',
      'KYC_VERIFICATION_STATUS_INVALID',
      'AML_SCREENING_TYPE_INVALID',
      'AML_SCREENING_RESULT_INVALID',
      'AML_MATCH_SCORE_OUT_OF_RANGE'
    );

  IF v_count <> 0 THEN
    RAISE EXCEPTION 'Supplied data unexpectedly raised % inconsistent-data findings', v_count;
  END IF;

  -- 13. KYC status follows the report rule: a customer with an open exception is never VERIFIED.
  SELECT count(*)::integer INTO v_count
  FROM silver.customer_kyc_status(v_reference_date)
  WHERE kyc_status = 'VERIFIED'
    AND open_exception_count > 0;

  IF v_count <> 0 THEN
    RAISE EXCEPTION '% customers are reported VERIFIED while an exception is open', v_count;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM silver.customer_kyc_status(v_reference_date)
  WHERE kyc_status NOT IN ('VERIFIED', 'INCOMPLETE', 'REVIEW_REQUIRED', 'UNKNOWN');

  IF v_count <> 0 THEN
    RAISE EXCEPTION '% customers have a KYC status outside the report values', v_count;
  END IF;

  -- 14. Reruns add no duplicate data.
  SELECT count(*)::integer INTO v_cases_before FROM silver.special_verification_case;

  CALL silver.publish_compliance_cases();
  CALL silver.publish_compliance_cases();

  SELECT count(*)::integer INTO v_cases_after FROM silver.special_verification_case;

  IF v_cases_after <> v_cases_before THEN
    RAISE EXCEPTION
      'Republishing cases created % additional verification cases',
      v_cases_after - v_cases_before;
  END IF;

  SELECT count(*)::integer INTO v_cases_before FROM silver.data_quality_issue
  WHERE validation_run_id LIKE 'KYC-AML-M5-%';

  CALL silver.process_kyc_aml_batch('B1-AMLKYC', v_reference_date);

  SELECT count(*)::integer INTO v_cases_after FROM silver.data_quality_issue
  WHERE validation_run_id LIKE 'KYC-AML-M5-%';

  IF v_cases_after <> v_cases_before THEN
    RAISE EXCEPTION
      'Reprocessing batch B1-AMLKYC changed the issue count from % to %',
      v_cases_before,
      v_cases_after;
  END IF;

  SELECT count(*)::integer INTO v_count
  FROM silver.kyc_verification_record
  WHERE source_system_id = 'AMLKYC';

  IF v_count <> 9 THEN
    RAISE EXCEPTION 'Reprocessing duplicated KYC events; found %', v_count;
  END IF;

  -- 15. Refreshing an open case updates its row rather than adding one.
  CALL gold.refresh_compliance_exception_fact(v_reference_date);

  SELECT count(*)::integer INTO v_count FROM gold.fact_compliance_exception;

  IF v_count <> v_fact_rows THEN
    RAISE EXCEPTION
      'Refreshing the fact changed its row count from % to %',
      v_fact_rows,
      v_count;
  END IF;

  RAISE NOTICE 'All Member 5 acceptance tests passed';
END
$member5_tests$;

-- Report output: these queries produce the figures used in the report.

-- The KYC/AML exception report.
SELECT
  exception_source_type,
  exception_type,
  exception_status,
  severity,
  opened_date,
  resolved_date,
  as_of_date,
  days_open,
  customer_id,
  customer_name,
  case_reason
FROM gold.vw_kyc_aml_exception_report
ORDER BY exception_source_type, exception_type, opened_date;

-- The exception summary.
SELECT *
FROM gold.vw_compliance_exception_summary
ORDER BY open_exception_count DESC, longest_days_open DESC;

-- Customer KYC status under the report rule.
SELECT
  customer_id,
  customer_full_name,
  verification_count,
  reusable_verification_count,
  aml_alert_count,
  open_exception_count,
  kyc_status
FROM silver.customer_kyc_status(DATE '2026-09-30')
ORDER BY kyc_status, customer_id;

-- Validation findings, including rules that correctly did not fire.
SELECT
  rule_name,
  entity_name,
  severity,
  count(*) AS finding_count,
  count(*) FILTER (WHERE issue_status = 'OPEN') AS open_count
FROM silver.data_quality_issue
WHERE validation_run_id LIKE 'KYC-AML-M5-%'
GROUP BY rule_name, entity_name, severity
ORDER BY rule_name;

-- Cases and their clearing evidence.
SELECT
  investigation.verification_case_id AS case_id,
  'VERIFICATION' AS case_source,
  investigation.case_type,
  investigation.case_status,
  investigation.severity,
  investigation.opened_at::date AS opened_date,
  investigation.resolved_at::date AS resolved_date,
  investigation.kyc_verification_id AS source_event
FROM silver.special_verification_case investigation
UNION ALL
SELECT
  investigation.aml_case_id,
  'AML',
  investigation.case_type,
  investigation.case_status,
  investigation.risk_level,
  investigation.opened_at::date,
  investigation.closed_at::date,
  investigation.aml_screening_id
FROM silver.aml_case investigation
ORDER BY case_source, case_type, case_id;

-- Traceability from the retained raw record to the reported exception.
SELECT
  bronze_record_reference,
  batch_id,
  published_event_reference,
  target_entity_name,
  case_reference,
  case_type,
  exception_fact_id
FROM silver.vw_kyc_aml_exception_lineage
ORDER BY batch_id, bronze_record_reference;

-- <<< END SOURCE FILE: sql/guanbo/08_validation_tests.sql

-- >>> BEGIN SOURCE FILE: sql/dan/tests/check_member4.sql

-- Member4 end-to-end checks. Read-only: safe to run on the shared database after the full run.
-- Checks the latest published snapshot date. Every row should show PASS.
WITH d AS (
  SELECT max(snapshot_date) AS snapshot_date FROM gold.fact_customer_snapshot
),
-- Snapshot rows for the checked date.
s AS (
  SELECT f.* FROM gold.fact_customer_snapshot f JOIN d USING (snapshot_date)
),
-- Silver totals per customer, summed separately for accounts and loans.
acc AS (
  SELECT customer_id, sum(current_balance) AS balance
  FROM silver.banking_account a JOIN d ON a.as_of_date = d.snapshot_date
  GROUP BY customer_id
),
lns AS (
  SELECT customer_id, sum(outstanding_balance) AS outstanding
  FROM silver.loan l JOIN d ON l.as_of_date = d.snapshot_date
  GROUP BY customer_id
),
checks AS (
  -- 1. A snapshot was published.
  SELECT 1 AS check_no, 'Snapshot published' AS check_name,
         (SELECT count(*) FROM s) > 0 AS passed,
         (SELECT count(*) FROM s) || ' customers' AS detail
  UNION ALL
  -- 2. One row per customer per date.
  SELECT 2, 'One row per customer per date',
         NOT EXISTS (SELECT customer_id FROM s GROUP BY customer_id HAVING count(*) > 1),
         'duplicates: ' || (SELECT count(*) FROM (SELECT customer_id FROM s GROUP BY customer_id HAVING count(*) > 1) x)
  UNION ALL
  -- 3. Account balances match Silver (no double counting).
  SELECT 3, 'Account balance matches Silver',
         NOT EXISTS (SELECT 1 FROM s LEFT JOIN acc USING (customer_id)
                     WHERE s.total_account_balance <> COALESCE(acc.balance, 0)),
         'total ' || (SELECT sum(total_account_balance) FROM s)
  UNION ALL
  -- 4. Loan balances match Silver (no double counting).
  SELECT 4, 'Outstanding loans match Silver',
         NOT EXISTS (SELECT 1 FROM s LEFT JOIN lns USING (customer_id)
                     WHERE s.total_outstanding_loans <> COALESCE(lns.outstanding, 0)),
         'total ' || (SELECT sum(total_outstanding_loans) FROM s)
  UNION ALL
  -- 5. Debt = outstanding loans + overdraft.
  SELECT 5, 'Debt = loans + overdraft',
         NOT EXISTS (SELECT 1 FROM s WHERE total_debt <> total_outstanding_loans + total_overdraft_balance),
         'total debt ' || (SELECT sum(total_debt) FROM s)
  UNION ALL
  -- 6. Missing values stay NULL and are flagged PARTIAL, never shown as 0.
  SELECT 6, 'Unknown values are NULL and PARTIAL',
         NOT EXISTS (SELECT 1 FROM s
                     WHERE (financial_data_status = 'PARTIAL')
                         = (total_credit_exposure IS NOT NULL AND net_profit IS NOT NULL)),
         'partial: ' || (SELECT count(*) FROM s WHERE financial_data_status = 'PARTIAL')
  UNION ALL
  -- 7. At most one current dimension version per customer.
  SELECT 7, 'One current DIM_CUSTOMER version',
         NOT EXISTS (SELECT customer_id FROM gold.dim_customer WHERE current_flag
                     GROUP BY customer_id HAVING count(*) > 1),
         (SELECT count(*) FROM gold.dim_customer) || ' versions'
  UNION ALL
  -- 8. Each snapshot row uses the dimension version valid on the snapshot date.
  SELECT 8, 'Snapshot uses version valid on date',
         NOT EXISTS (SELECT 1 FROM s JOIN gold.dim_customer dc ON dc.customer_key = s.customer_key
                     WHERE dc.customer_id <> s.customer_id
                        OR dc.effective_from >= s.snapshot_date + 1
                        OR dc.effective_to < s.snapshot_date + 1),
         'checked ' || (SELECT count(*) FROM s)
  UNION ALL
  -- 9. Every customer has a risk assessment.
  SELECT 9, 'Every customer risk-assessed',
         NOT EXISTS (SELECT 1 FROM s WHERE risk_assessment_id IS NULL),
         (SELECT string_agg(risk_rating || '=' || n, ', ' ORDER BY risk_rating)
          FROM (SELECT risk_rating, count(*) n FROM s GROUP BY risk_rating) x)
  UNION ALL
  -- 10. Data issues were logged and none are left open.
  SELECT 10, 'No open data quality issues',
         NOT EXISTS (SELECT 1 FROM silver.data_quality_issue q, d
                     WHERE q.validation_run_id = 'FIN-' || d.snapshot_date AND q.issue_status = 'OPEN'),
         (SELECT count(*) FROM silver.data_quality_issue q, d
          WHERE q.validation_run_id = 'FIN-' || d.snapshot_date) || ' issues logged'
  UNION ALL
  -- 11. Report views agree with the snapshot table.
  SELECT 11, 'Report views match snapshot',
         (SELECT total_debt FROM gold.v_portfolio_health JOIN d USING (snapshot_date))
           = (SELECT sum(total_debt) FROM s)
         AND (SELECT sum(customer_count) FROM gold.v_portfolio_risk_distribution JOIN d USING (snapshot_date))
           = (SELECT count(*) FROM s),
         'checked health + distribution'
)
SELECT (SELECT snapshot_date FROM d) AS snapshot_date, check_no, check_name,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS result, detail
FROM checks
ORDER BY check_no;

-- <<< END SOURCE FILE: sql/dan/tests/check_member4.sql

-- >>> BEGIN SOURCE FILE: sql/sunny/05_validation_demo.sql

-- Member 6 demonstration. Run after 01, 02 and 04.
-- Run the entire block in ONE CloudBeaver SQL-editor session; ROLLBACK leaves
-- the shared database unchanged. The test deliberately inserts one bad raw row.

BEGIN;

INSERT INTO bronze.raw_crm_customer (
  bronze_record_reference, source_system_id, batch_id,
  source_customer_reference, source_record_version, operation_type,
  source_full_name, record_status, source_last_updated_at, ingested_at
)
VALUES (
  'BR-M6-TEST-001', 'CRM', 'B1-CRM',
  '', 99, 'I', 'Quality Test', 'ACTIVE',
  clock_timestamp(), clock_timestamp()
)
ON CONFLICT (bronze_record_reference) DO NOTHING;

-- This finding is intentionally generated by the row above.
SELECT rule_name, entity_name, record_reference, severity
FROM silver.vw_member6_quality_findings
WHERE record_reference = 'BR-M6-TEST-001';

SELECT silver.member6_sync_quality_issues('M6-TEST-ROLLBACK')
  AS issues_added;

-- The second call must insert zero additional issues for the same run.
SELECT silver.member6_sync_quality_issues('M6-TEST-ROLLBACK')
  AS issues_added_on_rerun;

SELECT q.data_quality_issue_id, q.rule_name, q.issue_status,
       a.audit_id, a.action_type, a.actor_identifier
FROM silver.data_quality_issue q
JOIN silver.access_audit_log a
  ON a.record_reference = q.data_quality_issue_id
WHERE q.validation_run_id = 'M6-TEST-ROLLBACK'
  AND q.record_reference = 'BR-M6-TEST-001'
ORDER BY a.event_timestamp;

DO $member6_test$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM silver.vw_member6_quality_findings
    WHERE rule_name = 'M6_CUSTOMER_REFERENCE_BLANK'
      AND record_reference = 'BR-M6-TEST-001'
  ) THEN
    RAISE EXCEPTION 'Member 6 blank-reference rule did not detect the test row';
  END IF;

  IF (SELECT count(*) FROM silver.data_quality_issue
      WHERE validation_run_id = 'M6-TEST-ROLLBACK'
        AND record_reference = 'BR-M6-TEST-001') <> 1 THEN
    RAISE EXCEPTION 'Member 6 quality issue was not recorded once';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM silver.data_quality_issue q
    JOIN silver.access_audit_log a
      ON a.record_reference = q.data_quality_issue_id
    WHERE q.validation_run_id = 'M6-TEST-ROLLBACK'
      AND q.record_reference = 'BR-M6-TEST-001'
      AND a.action_type = 'INSERT'
  ) THEN
    RAISE EXCEPTION 'Member 6 issue INSERT was not audited';
  END IF;

  RAISE NOTICE 'Member 6 transactional test passed';
END;
$member6_test$;

ROLLBACK;

-- Read-only evidence from Member 1's intentional CDC failure, if available.
SELECT rule_name, record_reference, severity
FROM silver.vw_member6_quality_findings
WHERE rule_name = 'M6_CDC_INVALID_OPERATION'
ORDER BY record_reference;

SELECT batch_id, rule_name, issue_status
FROM silver.data_quality_issue
WHERE rule_name = 'incremental_batch_validation'
ORDER BY batch_id;

-- Run only after the administrator applies 03_security_roles.sql.
-- An unexpected TRUE in a denied cell means another membership or PUBLIC
-- privilege needs review; a role-level REVOKE alone cannot remove it.
-- SELECT
--   has_table_privilege('m6_analyst',
--     'gold.fact_customer_snapshot', 'SELECT') AS analyst_can_read_gold,
--   has_table_privilege('m6_analyst',
--     'bronze.raw_kyc_verification', 'SELECT') AS analyst_can_read_raw_kyc,
--   has_table_privilege('m6_auditor',
--     'silver.access_audit_log', 'SELECT') AS auditor_can_read_log,
--   has_table_privilege('m6_auditor',
--     'silver.access_audit_log', 'UPDATE') AS auditor_can_change_log;

-- <<< END SOURCE FILE: sql/sunny/05_validation_demo.sql

-- >>> BEGIN GENERATED SECTION: Final deployment summary

SELECT table_schema, count(*) AS table_count
FROM information_schema.tables
WHERE table_schema IN ('source_systems', 'bronze', 'silver', 'gold')
GROUP BY table_schema
ORDER BY table_schema;

SELECT batch_id, source_system_id, load_status
FROM silver.ingestion_batch
ORDER BY batch_id;

-- <<< END GENERATED SECTION: Final deployment summary
