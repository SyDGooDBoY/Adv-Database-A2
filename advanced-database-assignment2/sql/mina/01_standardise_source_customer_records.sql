-- Module 2: CUSTOMER IDENTITY MATCHING
-- Step 1: Move successful Bronze customer records into Silver

BEGIN;

-- Combine the three Bronze customer tables
-- Only successful ingestion batches are used
CREATE OR REPLACE VIEW silver.v_member2_bronze_customer_versions AS
SELECT c.*
FROM bronze.raw_crm_customer c
JOIN silver.ingestion_batch b
  ON c.batch_id = b.batch_id
 AND c.source_system_id = b.source_system_id
WHERE b.load_status = 'SUCCEEDED'

UNION ALL

SELECT c.*
FROM bronze.raw_lending_customer c
JOIN silver.ingestion_batch b
  ON c.batch_id = b.batch_id
 AND c.source_system_id = b.source_system_id
WHERE b.load_status = 'SUCCEEDED'

UNION ALL

SELECT c.*
FROM bronze.raw_aml_kyc_customer c
JOIN silver.ingestion_batch b
  ON c.batch_id = b.batch_id
 AND c.source_system_id = b.source_system_id
WHERE b.load_status = 'SUCCEEDED';


-- LEAD finds when the next version of the same source customer starts.
WITH customer_versions AS (
    SELECT
        v.*,
        COALESCE(v.source_last_updated_at, v.ingested_at) AS valid_from_time,

        LEAD(COALESCE(v.source_last_updated_at, v.ingested_at)) OVER (
            PARTITION BY v.source_system_id, v.source_customer_reference
            ORDER BY v.source_record_version
        ) AS next_version_time

    FROM silver.v_member2_bronze_customer_versions v
)

INSERT INTO silver.source_customer_record (
    source_customer_record_id,
    source_system_id,
    batch_id,
    source_customer_reference,
    source_record_version,
    bronze_record_reference,
    source_full_name,
    source_date_of_birth,
    source_email_address,
    source_phone_number,
    source_address,
    source_last_updated_at,
    valid_from,
    valid_to,
    is_current_version,
    record_hash
)

SELECT
    -- Stable ID for each source record version.
    'SCR-' || source_system_id || '-' ||
    source_customer_reference || '-V' ||
    source_record_version::text,

    source_system_id,
    batch_id,
    source_customer_reference,
    source_record_version,
    bronze_record_reference,
    source_full_name,
    source_date_of_birth,
    source_email_address,
    source_phone_number,
    source_address,
    source_last_updated_at,
    valid_from_time,

    -- A delete is closed immediately.
    -- Other old versions close when the next version starts.
    CASE
        WHEN operation_type = 'D' THEN valid_from_time
        ELSE next_version_time
    END,

    -- Only the latest non-deleted version is current.
    (
        next_version_time IS NULL
        AND operation_type <> 'D'
        AND UPPER(COALESCE(record_status, '')) <> 'DELETED'
    ),

    -- Hash kept for traceability and change checking.
    MD5(
        CONCAT_WS(
            '|',
            source_system_id,
            source_customer_reference,
            source_record_version::text,
            COALESCE(source_full_name, ''),
            COALESCE(source_date_of_birth::text, ''),
            COALESCE(source_email_address, ''),
            COALESCE(source_phone_number, ''),
            COALESCE(source_address, ''),
            COALESCE(record_status, '')
        )
    )

FROM customer_versions

-- If this source version already exists, update it instead of duplicating it.
ON CONFLICT (source_customer_record_id) DO UPDATE
SET
    batch_id                   = EXCLUDED.batch_id,
    bronze_record_reference    = EXCLUDED.bronze_record_reference,
    source_full_name           = EXCLUDED.source_full_name,
    source_date_of_birth       = EXCLUDED.source_date_of_birth,
    source_email_address       = EXCLUDED.source_email_address,
    source_phone_number        = EXCLUDED.source_phone_number,
    source_address             = EXCLUDED.source_address,
    source_last_updated_at     = EXCLUDED.source_last_updated_at,
    valid_from                 = EXCLUDED.valid_from,
    valid_to                   = EXCLUDED.valid_to,
    is_current_version         = EXCLUDED.is_current_version,
    record_hash                = EXCLUDED.record_hash;

COMMIT;


-- check
SELECT
    source_system_id,
    source_customer_reference,
    source_record_version,
    is_current_version
FROM silver.source_customer_record
ORDER BY source_system_id, source_customer_reference, source_record_version;