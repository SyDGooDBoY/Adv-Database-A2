-- PostgreSQL 15+
-- Member 1 demonstration: Lending succeeds; AML/KYC is expected to fail
-- because the supplied CDC-019 operation_type is blank.

CALL silver.process_incremental_batch('B2-LEND', FALSE);
CALL silver.process_incremental_batch('B2-AMLKYC', FALSE);

SELECT
  batch_id,
  source_system_id,
  load_status,
  records_received,
  records_processed,
  watermark_start,
  watermark_end
FROM silver.ingestion_batch
WHERE batch_id IN ('B2-LEND', 'B2-AMLKYC')
ORDER BY batch_id;

SELECT
  data_quality_issue_id,
  batch_id,
  rule_name,
  issue_description,
  severity,
  issue_status
FROM silver.data_quality_issue
WHERE batch_id = 'B2-AMLKYC'
  AND issue_type = 'LOAD_VALIDATION'
ORDER BY detected_at DESC;

