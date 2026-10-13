-- Loads initial B1 data into Bronze and publishes successful load controls to Silver.

BEGIN;

-- Retains source metadata and initial batch definitions in Bronze.
INSERT INTO bronze.source_system
SELECT *
FROM source_systems.source_system
ON CONFLICT (source_system_id) DO NOTHING;

INSERT INTO bronze.ingestion_batch
SELECT *
FROM source_systems.ingestion_batch
WHERE load_type = 'INITIAL'
ON CONFLICT (batch_id) DO NOTHING;

-- Copies all initial raw business records into the append-only Bronze tables.
INSERT INTO bronze.raw_crm_customer
SELECT r.*
FROM source_systems.raw_crm_customer r
JOIN source_systems.ingestion_batch b USING (batch_id)
WHERE b.load_type = 'INITIAL'
ON CONFLICT (bronze_record_reference) DO NOTHING;

INSERT INTO bronze.raw_lending_customer
SELECT r.*
FROM source_systems.raw_lending_customer r
JOIN source_systems.ingestion_batch b USING (batch_id)
WHERE b.load_type = 'INITIAL'
ON CONFLICT (bronze_record_reference) DO NOTHING;

INSERT INTO bronze.raw_aml_kyc_customer
SELECT r.*
FROM source_systems.raw_aml_kyc_customer r
JOIN source_systems.ingestion_batch b USING (batch_id)
WHERE b.load_type = 'INITIAL'
ON CONFLICT (bronze_record_reference) DO NOTHING;

INSERT INTO bronze.raw_banking_account_snapshot
SELECT r.*
FROM source_systems.raw_banking_account_snapshot r
JOIN source_systems.ingestion_batch b USING (batch_id)
WHERE b.load_type = 'INITIAL'
ON CONFLICT (bronze_record_reference) DO NOTHING;

INSERT INTO bronze.raw_loan_snapshot
SELECT r.*
FROM source_systems.raw_loan_snapshot r
JOIN source_systems.ingestion_batch b USING (batch_id)
WHERE b.load_type = 'INITIAL'
ON CONFLICT (bronze_record_reference) DO NOTHING;

INSERT INTO bronze.raw_account_transaction
SELECT r.*
FROM source_systems.raw_account_transaction r
JOIN source_systems.ingestion_batch b USING (batch_id)
WHERE b.load_type = 'INITIAL'
ON CONFLICT (bronze_record_reference) DO NOTHING;

INSERT INTO bronze.raw_kyc_verification
SELECT r.*
FROM source_systems.raw_kyc_verification r
JOIN source_systems.ingestion_batch b USING (batch_id)
WHERE b.load_type = 'INITIAL'
ON CONFLICT (bronze_record_reference) DO NOTHING;

INSERT INTO bronze.raw_aml_screening
SELECT r.*
FROM source_systems.raw_aml_screening r
JOIN source_systems.ingestion_batch b USING (batch_id)
WHERE b.load_type = 'INITIAL'
ON CONFLICT (bronze_record_reference) DO NOTHING;

-- Confirms each initial batch contains the number of raw records declared by its control row.
DO $validate_initial$
DECLARE
  v_batch source_systems.ingestion_batch%ROWTYPE;
  v_loaded integer;
BEGIN
  FOR v_batch IN
    SELECT *
    FROM source_systems.ingestion_batch
    WHERE load_type = 'INITIAL'
    ORDER BY batch_id
  LOOP
    SELECT count(*)
    INTO v_loaded
    FROM (
      SELECT 1 FROM bronze.raw_crm_customer WHERE batch_id = v_batch.batch_id
      UNION ALL
      SELECT 1 FROM bronze.raw_lending_customer WHERE batch_id = v_batch.batch_id
      UNION ALL
      SELECT 1 FROM bronze.raw_aml_kyc_customer WHERE batch_id = v_batch.batch_id
      UNION ALL
      SELECT 1 FROM bronze.raw_banking_account_snapshot WHERE batch_id = v_batch.batch_id
      UNION ALL
      SELECT 1 FROM bronze.raw_loan_snapshot WHERE batch_id = v_batch.batch_id
      UNION ALL
      SELECT 1 FROM bronze.raw_account_transaction WHERE batch_id = v_batch.batch_id
      UNION ALL
      SELECT 1 FROM bronze.raw_kyc_verification WHERE batch_id = v_batch.batch_id
      UNION ALL
      SELECT 1 FROM bronze.raw_aml_screening WHERE batch_id = v_batch.batch_id
    ) loaded_rows;

    IF v_loaded <> v_batch.records_received THEN
      RAISE EXCEPTION
        'Initial batch % expected % records but Bronze contains %',
        v_batch.batch_id,
        v_batch.records_received,
        v_loaded;
    END IF;
  END LOOP;
END
$validate_initial$;

-- Publishes the authoritative source-system catalogue to Silver.
INSERT INTO silver.source_system (
  source_system_id,
  system_name,
  system_type,
  system_description,
  system_owner,
  active_flag
)
SELECT
  source_system_id,
  system_name,
  system_type,
  system_description,
  system_owner,
  active_flag
FROM bronze.source_system
ON CONFLICT (source_system_id) DO UPDATE SET
  system_name = EXCLUDED.system_name,
  system_type = EXCLUDED.system_type,
  system_description = EXCLUDED.system_description,
  system_owner = EXCLUDED.system_owner,
  active_flag = EXCLUDED.active_flag;

-- Marks validated initial batches as successfully processed in Silver.
INSERT INTO silver.ingestion_batch (
  batch_id,
  source_system_id,
  load_type,
  started_at,
  completed_at,
  load_status,
  records_received,
  records_processed,
  watermark_start,
  watermark_end
)
SELECT
  batch_id,
  source_system_id,
  load_type,
  started_at,
  completed_at,
  'SUCCEEDED',
  records_received,
  records_received,
  watermark_start,
  watermark_end
FROM bronze.ingestion_batch
WHERE load_type = 'INITIAL'
ON CONFLICT (batch_id) DO NOTHING;

COMMIT;

-- Displays the published initial-batch status and watermarks.
SELECT
  batch_id,
  source_system_id,
  load_status,
  records_received,
  records_processed,
  watermark_end
FROM silver.ingestion_batch
WHERE load_type = 'INITIAL'
ORDER BY source_system_id;
