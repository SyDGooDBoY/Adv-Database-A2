-- Demonstrates B2-CRM failure, retained Bronze data, retry and idempotency.

CALL silver.process_incremental_batch('B2-CRM', TRUE);

-- Shows the failed batch state, retained data and unchanged committed watermark.
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

-- Retries the staged batch.
CALL silver.process_incremental_batch('B2-CRM', FALSE);

-- Repeats the call to verify idempotency.
CALL silver.process_incremental_batch('B2-CRM', FALSE);

-- Displays the successful final batch state and published CRM CDC events.
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
