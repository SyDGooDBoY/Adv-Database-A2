-- PostgreSQL 15+
-- Member 1 demonstration: force B2-CRM to fail after Bronze staging, prove
-- that its watermark did not advance, then safely retry the same batch.

CALL silver.process_incremental_batch('B2-CRM', TRUE);

-- Expected after forced failure:
--   load_status = FAILED
--   watermark_end IS NULL
--   Bronze rows remain available
SELECT
  batch_id,
  source_system_id,
  load_status,
  records_received,
  records_processed,
  watermark_start,
  watermark_end
FROM silver.ingestion_batch
WHERE batch_id = 'B2-CRM';

SELECT
  silver.count_bronze_batch_records('B2-CRM') AS retained_bronze_rows,
  (SELECT count(*) FROM bronze.cdc_change_event WHERE batch_id = 'B2-CRM')
    AS retained_cdc_events,
  (SELECT watermark_end
   FROM silver.vw_latest_successful_watermark
   WHERE source_system_id = 'CRM') AS committed_watermark_after_failure;

-- Retry succeeds using the already-staged Bronze rows.
CALL silver.process_incremental_batch('B2-CRM', FALSE);

-- A third call proves idempotency: the procedure detects SUCCEEDED and skips.
CALL silver.process_incremental_batch('B2-CRM', FALSE);

SELECT
  batch_id,
  source_system_id,
  load_status,
  records_received,
  records_processed,
  watermark_start,
  watermark_end
FROM silver.ingestion_batch
WHERE batch_id = 'B2-CRM';

SELECT
  count(*) AS silver_crm_cdc_events
FROM silver.cdc_change_event
WHERE batch_id = 'B2-CRM';

