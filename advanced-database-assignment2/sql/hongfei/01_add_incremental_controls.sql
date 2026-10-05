-- PostgreSQL 15+
-- Member 1: enforce load-control states and expose the latest committed
-- watermark for each source system.

DO $controls$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ck_ingestion_batch_load_type'
      AND conrelid = 'silver.ingestion_batch'::regclass
  ) THEN
    ALTER TABLE silver.ingestion_batch
      ADD CONSTRAINT ck_ingestion_batch_load_type
      CHECK (load_type IN ('INITIAL', 'SIMULATED_CDC'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ck_ingestion_batch_status'
      AND conrelid = 'silver.ingestion_batch'::regclass
  ) THEN
    ALTER TABLE silver.ingestion_batch
      ADD CONSTRAINT ck_ingestion_batch_status
      CHECK (load_status IN ('RUNNING', 'SUCCEEDED', 'FAILED'));
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ck_ingestion_batch_counts'
      AND conrelid = 'silver.ingestion_batch'::regclass
  ) THEN
    ALTER TABLE silver.ingestion_batch
      ADD CONSTRAINT ck_ingestion_batch_counts
      CHECK (
        records_received >= 0
        AND records_processed >= 0
        AND records_processed <= records_received
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ck_ingestion_batch_lifecycle'
      AND conrelid = 'silver.ingestion_batch'::regclass
  ) THEN
    ALTER TABLE silver.ingestion_batch
      ADD CONSTRAINT ck_ingestion_batch_lifecycle
      CHECK (
        (load_status = 'RUNNING'
          AND completed_at IS NULL
          AND watermark_end IS NULL)
        OR
        (load_status = 'SUCCEEDED'
          AND completed_at IS NOT NULL
          AND watermark_end IS NOT NULL)
        OR
        (load_status = 'FAILED'
          AND completed_at IS NOT NULL
          AND watermark_end IS NULL)
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'ck_cdc_operation_type'
      AND conrelid = 'silver.cdc_change_event'::regclass
  ) THEN
    ALTER TABLE silver.cdc_change_event
      ADD CONSTRAINT ck_cdc_operation_type
      CHECK (operation_type IN ('I', 'U', 'D'));
  END IF;
END
$controls$;

CREATE INDEX IF NOT EXISTS ix_ingestion_batch_source_status_completed
  ON silver.ingestion_batch
  (source_system_id, load_status, completed_at DESC);

CREATE INDEX IF NOT EXISTS ix_bronze_cdc_batch
  ON bronze.cdc_change_event (batch_id);

CREATE OR REPLACE VIEW silver.vw_latest_successful_watermark AS
SELECT DISTINCT ON (source_system_id)
  source_system_id,
  batch_id,
  watermark_end,
  completed_at
FROM silver.ingestion_batch
WHERE load_status = 'SUCCEEDED'
ORDER BY source_system_id, completed_at DESC, batch_id DESC;

COMMENT ON VIEW silver.vw_latest_successful_watermark IS
  'Latest committed watermark per source; failed and running batches are excluded.';

