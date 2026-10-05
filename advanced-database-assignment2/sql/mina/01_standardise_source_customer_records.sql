-- PostgreSQL 15+
-- Member 2: Customer Identity Matching
-- Step 1 - Standardise successful Bronze customer versions into
-- silver.source_customer_record.
--
-- Member 1 stops after reliable Bronze ingestion / CDC control.
-- This script is therefore the hand-off from Member 1 to Member 2.
--
-- Rerunnable:
--   * existing source versions are updated, not duplicated;
--   * a later version closes the previous version;
--   * a delete version is retained for traceability but is never current;
--   * Bronze rows from FAILED batches are not published to Silver.

BEGIN;

CREATE OR REPLACE VIEW silver.v_member2_bronze_customer_versions AS
SELECT
    c.bronze_record_reference,
    c.source_system_id,
    c.batch_id,
    c.source_customer_reference,
    c.source_record_version,
    c.operation_type,
    c.source_full_name,
    c.source_date_of_birth,
    c.source_email_address,
    c.source_phone_number,
    c.source_address,
    c.record_status,
    c.source_last_updated_at,
    c.ingested_at
FROM bronze.raw_crm_customer c
JOIN silver.ingestion_batch b
  ON b.batch_id = c.batch_id
 AND b.source_system_id = c.source_system_id
 AND b.load_status = 'SUCCEEDED'

UNION ALL

SELECT
    c.bronze_record_reference,
    c.source_system_id,
    c.batch_id,
    c.source_customer_reference,
    c.source_record_version,
    c.operation_type,
    c.source_full_name,
    c.source_date_of_birth,
    c.source_email_address,
    c.source_phone_number,
    c.source_address,
    c.record_status,
    c.source_last_updated_at,
    c.ingested_at
FROM bronze.raw_lending_customer c
JOIN silver.ingestion_batch b
  ON b.batch_id = c.batch_id
 AND b.source_system_id = c.source_system_id
 AND b.load_status = 'SUCCEEDED'

UNION ALL

SELECT
    c.bronze_record_reference,
    c.source_system_id,
    c.batch_id,
    c.source_customer_reference,
    c.source_record_version,
    c.operation_type,
    c.source_full_name,
    c.source_date_of_birth,
    c.source_email_address,
    c.source_phone_number,
    c.source_address,
    c.record_status,
    c.source_last_updated_at,
    c.ingested_at
FROM bronze.raw_aml_kyc_customer c
JOIN silver.ingestion_batch b
  ON b.batch_id = c.batch_id
 AND b.source_system_id = c.source_system_id
 AND b.load_status = 'SUCCEEDED';


WITH prepared AS (
    SELECT
        v.*,
        COALESCE(v.source_last_updated_at, v.ingested_at) AS version_time
    FROM silver.v_member2_bronze_customer_versions v
),
versioned AS (
    SELECT
        p.*,

        LEAD(p.version_time) OVER (
            PARTITION BY
                p.source_system_id,
                p.source_customer_reference
            ORDER BY
                p.source_record_version,
                p.version_time,
                p.bronze_record_reference
        ) AS next_version_time

    FROM prepared p
),
publish_rows AS (
    SELECT
        'SCR-' ||
        v.source_system_id || '-' ||
        v.source_customer_reference || '-V' ||
        v.source_record_version::text
            AS source_customer_record_id,

        v.source_system_id,
        v.batch_id,
        v.source_customer_reference,
        v.source_record_version,
        v.bronze_record_reference,
        v.source_full_name,
        v.source_date_of_birth,
        v.source_email_address,
        v.source_phone_number,
        v.source_address,
        v.source_last_updated_at,

        v.version_time AS valid_from,

        CASE
            WHEN v.operation_type = 'D'
                THEN v.version_time
            ELSE v.next_version_time
        END AS valid_to,

        (
            v.next_version_time IS NULL
            AND v.operation_type <> 'D'
            AND UPPER(COALESCE(v.record_status, '')) <> 'DELETED'
        ) AS is_current_version,

        MD5(
            CONCAT_WS(
                '|',
                COALESCE(v.source_system_id, ''),
                COALESCE(v.source_customer_reference, ''),
                COALESCE(v.source_record_version::text, ''),
                COALESCE(v.operation_type, ''),
                COALESCE(v.source_full_name, ''),
                COALESCE(v.source_date_of_birth::text, ''),
                COALESCE(v.source_email_address, ''),
                COALESCE(v.source_phone_number, ''),
                COALESCE(v.source_address, ''),
                COALESCE(v.record_status, '')
            )
        ) AS record_hash

    FROM versioned v
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
FROM publish_rows

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


-- Inspection
SELECT
    source_system_id,
    source_customer_reference,
    source_record_version,
    batch_id,
    valid_from,
    valid_to,
    is_current_version
FROM silver.source_customer_record
ORDER BY
    source_system_id,
    source_customer_reference,
    source_record_version;
