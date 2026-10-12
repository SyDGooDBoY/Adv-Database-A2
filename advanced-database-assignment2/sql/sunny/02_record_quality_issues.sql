-- Member 6: persist newly detected structural failures in the shared issue table.
-- Run after 01_quality_findings.sql. One run ID gives idempotent reruns.

CREATE OR REPLACE FUNCTION silver.member6_sync_quality_issues(
  p_validation_run_id text
)
RETURNS integer
LANGUAGE plpgsql
AS $member6_sync$
DECLARE
  v_inserted integer;
BEGIN
  IF p_validation_run_id IS NULL
     OR btrim(p_validation_run_id) = ''
     OR length(p_validation_run_id) > 100 THEN
    RAISE EXCEPTION 'Provide a nonblank validation run ID of at most 100 characters';
  END IF;

  INSERT INTO silver.data_quality_issue (
    data_quality_issue_id, batch_id, source_system_id,
    verification_case_id, validation_run_id, data_layer, entity_name,
    record_reference, record_version_reference, attribute_name,
    rule_name, rule_version, issue_type, issue_description,
    severity, detected_at, resolved_at, issue_status
  )
  SELECT
    'M6-' || substr(md5(concat_ws('|',
      p_validation_run_id, f.rule_name, f.entity_name,
      f.record_reference, f.record_version_reference
    )), 1, 32),
    CASE WHEN EXISTS (
      SELECT 1 FROM silver.ingestion_batch b WHERE b.batch_id = f.batch_id
    ) THEN f.batch_id ELSE NULL END,
    CASE WHEN EXISTS (
      SELECT 1 FROM silver.source_system s
      WHERE s.source_system_id = f.source_system_id
    ) THEN f.source_system_id ELSE NULL END,
    NULL,
    p_validation_run_id,
    f.data_layer,
    f.entity_name,
    f.record_reference,
    f.record_version_reference,
    f.attribute_name,
    f.rule_name,
    '1.0',
    f.issue_type,
    left(f.issue_description, 1000),
    f.severity,
    clock_timestamp(),
    NULL,
    'OPEN'
  FROM silver.vw_member6_quality_findings f
  WHERE f.rule_name NOT IN (
    -- Member 1 already records load-validation failures by batch.
    'M6_CDC_INVALID_OPERATION',
    'M6_CDC_BATCH_SOURCE_MISMATCH',
    -- Reportable KYC gaps require Member 5's verification-case FK first.
    'M6_KYC_MISSING_DOCUMENT',
    'M6_KYC_EXPIRED_STATUS'
  )
  ON CONFLICT (data_quality_issue_id) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  RETURN v_inserted;
END;
$member6_sync$;

COMMENT ON FUNCTION silver.member6_sync_quality_issues(text) IS
  'Stores non-CDC structural findings once per validation run; does not alter source or Bronze rows. Recheck before manually resolving an issue.';

-- Example after all relevant tables contain data:
-- SELECT silver.member6_sync_quality_issues('M6-2026-10-12-01');
-- SELECT * FROM silver.data_quality_issue
-- WHERE validation_run_id = 'M6-2026-10-12-01';
