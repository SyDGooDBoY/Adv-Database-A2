-- PostgreSQL 15+
-- Member 5: enforce the KYC/AML case-state and status rules from the report's
-- business rules. Added in a guard so the module can be rerun safely.
--
-- Every violation is raised as an exception rather than silently skipped. The
-- seed data in 01_seed_kyc_aml_bronze.sql is aligned with these rules, so a
-- failure here means real non-conforming data was loaded.

DO $compliance_rules$
DECLARE
  v_constraint record;
BEGIN
  FOR v_constraint IN
    SELECT *
    FROM (VALUES
      (
        'ck_kyc_verification_record_subject',
        'silver.kyc_verification_record',
        'customer_id IS NOT NULL OR source_customer_record_id IS NOT NULL',
        'A KYC verification event requires a customer or a source customer record.'
      ),
      (
        'ck_kyc_verification_record_verified_expiry',
        'silver.kyc_verification_record',
        'verification_status <> ''VERIFIED'' OR expiry_date IS NULL OR expiry_date >= verification_date::date',
        'A successful KYC check cannot expire before it was performed.'
      ),
      (
        'ck_kyc_verification_record_reviewer',
        'silver.kyc_verification_record',
        'verification_status <> ''MISSING_DOCUMENT'' OR reviewed_by IS NULL',
        'A gap event records the check that failed; reviewed_by belongs to a completed review.'
      ),
      (
        'ck_special_verification_case_subject',
        'silver.special_verification_case',
        'customer_id IS NOT NULL OR source_customer_record_id IS NOT NULL OR match_id IS NOT NULL OR kyc_verification_id IS NOT NULL',
        'A case requires at least one subject or trigger reference, excluding the assignee.'
      ),
      (
        'ck_special_verification_case_type',
        'silver.special_verification_case',
        'case_type IN (''KYC_GAP'', ''IDENTITY_MISMATCH'', ''STATUS_DISCREPANCY'')',
        'Reportable KYC findings use the case types required by the report.'
      ),
      (
        'ck_special_verification_case_status',
        'silver.special_verification_case',
        'case_status IN (''OPEN'', ''IN_REVIEW'', ''RESOLVED'', ''CLOSED'')',
        'Case status is limited to the prototype investigation lifecycle.'
      ),
      (
        'ck_special_verification_case_resolution',
        'silver.special_verification_case',
        '(case_status IN (''OPEN'', ''IN_REVIEW'') AND resolved_at IS NULL AND resolution_outcome IS NULL) OR (case_status IN (''RESOLVED'', ''CLOSED'') AND resolved_at IS NOT NULL)',
        'RESOLVED requires resolved_at; an active case must not carry a resolution.'
      ),
      (
        'ck_special_verification_case_dates',
        'silver.special_verification_case',
        'resolved_at IS NULL OR resolved_at >= opened_at',
        'A case cannot be resolved before it was opened.'
      ),
      (
        'ck_special_verification_case_severity',
        'silver.special_verification_case',
        'severity IN (''LOW'', ''MEDIUM'', ''HIGH'', ''CRITICAL'')',
        'Case severity uses the prototype severity scale.'
      ),
      (
        'ck_aml_screening_result_subject',
        'silver.aml_screening_result',
        'customer_id IS NOT NULL OR source_customer_record_id IS NOT NULL',
        'A screening event requires a customer or a source customer record.'
      ),
      (
        'ck_aml_screening_result_score',
        'silver.aml_screening_result',
        'match_score IS NULL OR (match_score >= 0 AND match_score <= 1)',
        'A match score is a probability between 0 and 1.'
      ),
      (
        'ck_aml_screening_result_review_flag',
        'silver.aml_screening_result',
        'screening_result IN (''CLEAR'', ''FALSE_POSITIVE'') OR review_required_flag',
        'An alert or potential match cannot be published without review.'
      ),
      (
        'ck_aml_case_subject_or_trigger',
        'silver.aml_case',
        'customer_id IS NOT NULL OR source_customer_record_id IS NOT NULL OR aml_screening_id IS NOT NULL OR length(btrim(trigger_reference)) > 0',
        'An AML investigation requires a customer, a source record, a screening reference or another documented trigger.'
      ),
      (
        'ck_aml_case_status',
        'silver.aml_case',
        'case_status IN (''OPEN'', ''IN_REVIEW'', ''CLOSED'')',
        'AML case status is limited to the prototype investigation lifecycle.'
      ),
      (
        'ck_aml_case_lifecycle',
        'silver.aml_case',
        '(case_status = ''CLOSED'' AND closed_at IS NOT NULL) OR (case_status <> ''CLOSED'' AND closed_at IS NULL)',
        'Closing dates must agree with the corresponding case status.'
      ),
      (
        'ck_aml_case_dates',
        'silver.aml_case',
        'closed_at IS NULL OR closed_at >= opened_at',
        'An AML case cannot be closed before it was opened.'
      ),
      (
        'ck_aml_case_risk_level',
        'silver.aml_case',
        'risk_level IN (''LOW'', ''MEDIUM'', ''HIGH'', ''CRITICAL'')',
        'Case risk level uses the prototype risk scale.'
      ),
      (
        'ck_fact_compliance_exception_single_case',
        'gold.fact_compliance_exception',
        '(verification_case_id IS NOT NULL AND aml_case_id IS NULL AND exception_source_type = ''VERIFICATION'') OR (verification_case_id IS NULL AND aml_case_id IS NOT NULL AND exception_source_type = ''AML'')',
        'Exactly one originating case is required and it must agree with exception_source_type.'
      ),
      (
        'ck_fact_compliance_exception_days_open',
        'gold.fact_compliance_exception',
        'days_open >= 0',
        'Days open is a non-negative calendar-day count.'
      ),
      (
        'ck_fact_compliance_exception_dates',
        'gold.fact_compliance_exception',
        'resolved_date IS NULL OR resolved_date >= opened_date',
        'An exception cannot be resolved before it was opened.'
      )
    ) AS rule (constraint_name, table_name, predicate, description)
  LOOP
    IF EXISTS (
      SELECT 1
      FROM pg_constraint
      WHERE conname = v_constraint.constraint_name
        AND conrelid = v_constraint.table_name::regclass
    ) THEN
      RAISE NOTICE 'Constraint % already present; validated only',
        v_constraint.constraint_name;
    ELSE
      EXECUTE format(
        'ALTER TABLE %s ADD CONSTRAINT %I CHECK (%s)',
        v_constraint.table_name,
        v_constraint.constraint_name,
        v_constraint.predicate
      );
      RAISE NOTICE 'Added %: %',
        v_constraint.constraint_name,
        v_constraint.description;
    END IF;
  END LOOP;
END
$compliance_rules$;

-- Supporting indexes for the validation and case-reuse lookups.
CREATE INDEX IF NOT EXISTS ix_kyc_verification_record_customer
  ON silver.kyc_verification_record (customer_id, verification_date DESC);

CREATE INDEX IF NOT EXISTS ix_kyc_verification_record_source_customer
  ON silver.kyc_verification_record (source_customer_record_id);

CREATE INDEX IF NOT EXISTS ix_aml_screening_result_customer
  ON silver.aml_screening_result (customer_id, screening_date DESC);

CREATE INDEX IF NOT EXISTS ix_aml_screening_result_source_customer
  ON silver.aml_screening_result (source_customer_record_id);

CREATE INDEX IF NOT EXISTS ix_special_verification_case_open
  ON silver.special_verification_case (customer_id, case_type)
  WHERE case_status IN ('OPEN', 'IN_REVIEW');

CREATE INDEX IF NOT EXISTS ix_aml_case_open
  ON silver.aml_case (customer_id, case_type)
  WHERE case_status IN ('OPEN', 'IN_REVIEW');

CREATE INDEX IF NOT EXISTS ix_data_quality_issue_case
  ON silver.data_quality_issue (verification_case_id)
  WHERE verification_case_id IS NOT NULL;
