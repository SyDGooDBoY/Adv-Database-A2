-- Processes the remaining incremental batches and displays their outcomes.

-- Runs the Lending batch and the deliberately invalid AML/KYC batch.
CALL silver.process_incremental_batch('B2-LEND', FALSE);
CALL silver.process_incremental_batch('B2-AMLKYC', FALSE);

-- Displays the final control state and watermark outcome for both batches.
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

-- Displays the blocking quality issue created for the failed AML/KYC batch.
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
