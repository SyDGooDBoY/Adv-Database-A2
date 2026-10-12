-- Member 6: read-only data-quality monitoring for PostgreSQL 15+.
-- Run after 00_shared_setup/00-49; Bronze and Silver may still be empty.
-- Each row is one rule failure for one record version. No source row is changed.

CREATE OR REPLACE VIEW silver.vw_member6_quality_findings AS
WITH raw_customers AS (
  SELECT 'RAW_CRM_CUSTOMER'::text AS entity_name,
         'CRM'::text AS expected_source,
         bronze_record_reference, source_system_id, batch_id,
         source_customer_reference, source_record_version
  FROM bronze.raw_crm_customer
  UNION ALL
  SELECT 'RAW_LENDING_CUSTOMER', 'LEND',
         bronze_record_reference, source_system_id, batch_id,
         source_customer_reference, source_record_version
  FROM bronze.raw_lending_customer
  UNION ALL
  SELECT 'RAW_AML_KYC_CUSTOMER', 'AMLKYC',
         bronze_record_reference, source_system_id, batch_id,
         source_customer_reference, source_record_version
  FROM bronze.raw_aml_kyc_customer
)
SELECT
  'BRONZE'::text AS data_layer,
  'CDC_CHANGE_EVENT'::text AS entity_name,
  c.change_event_id::text AS record_reference,
  c.source_version_reference::text AS record_version_reference,
  c.batch_id::text AS batch_id,
  c.source_system_id::text AS source_system_id,
  'operation_type'::text AS attribute_name,
  'M6_CDC_INVALID_OPERATION'::text AS rule_name,
  'LOAD_VALIDATION'::text AS issue_type,
  ('Expected I, U or D; received ' || quote_literal(c.operation_type))::text
    AS issue_description,
  'BLOCKING'::text AS severity
FROM bronze.cdc_change_event c
WHERE c.operation_type NOT IN ('I', 'U', 'D')

UNION ALL
SELECT 'BRONZE', 'CDC_CHANGE_EVENT', c.change_event_id::text,
       c.source_version_reference::text, c.batch_id::text,
       c.source_system_id::text, 'source_system_id',
       'M6_CDC_BATCH_SOURCE_MISMATCH', 'SOURCE_CONSISTENCY',
       CASE WHEN b.batch_id IS NULL
         THEN 'CDC event references a batch absent from Bronze'
         ELSE 'CDC source differs from the batch source'
       END,
       'BLOCKING'
FROM bronze.cdc_change_event c
LEFT JOIN bronze.ingestion_batch b ON b.batch_id = c.batch_id
WHERE b.batch_id IS NULL
   OR c.source_system_id IS DISTINCT FROM b.source_system_id

UNION ALL
SELECT 'BRONZE', r.entity_name, r.bronze_record_reference::text,
       r.source_record_version::text, r.batch_id::text,
       r.source_system_id::text, 'source_customer_reference',
       'M6_CUSTOMER_REFERENCE_BLANK', 'MISSING_VALUE',
       'Source customer reference is blank or whitespace', 'BLOCKING'
FROM raw_customers r
WHERE btrim(r.source_customer_reference) = ''

UNION ALL
SELECT 'BRONZE', r.entity_name, r.bronze_record_reference::text,
       r.source_record_version::text, r.batch_id::text,
       r.source_system_id::text, 'source_system_id',
       'M6_RAW_SOURCE_IN_WRONG_TABLE', 'SOURCE_CONSISTENCY',
       'Expected ' || r.expected_source || ' in this source-specific raw table',
       'BLOCKING'
FROM raw_customers r
WHERE r.source_system_id <> r.expected_source

UNION ALL
SELECT 'BRONZE', r.entity_name, r.bronze_record_reference::text,
       r.source_record_version::text, r.batch_id::text,
       r.source_system_id::text, 'batch_id',
       'M6_RAW_BATCH_SOURCE_MISMATCH', 'SOURCE_CONSISTENCY',
       CASE WHEN b.batch_id IS NULL
         THEN 'Raw customer record references a batch absent from Bronze'
         ELSE 'Raw customer source differs from the batch source'
       END,
       'BLOCKING'
FROM raw_customers r
LEFT JOIN bronze.ingestion_batch b ON b.batch_id = r.batch_id
WHERE b.batch_id IS NULL
   OR r.source_system_id IS DISTINCT FROM b.source_system_id

UNION ALL
SELECT 'BRONZE', 'RAW_KYC_VERIFICATION', k.bronze_record_reference::text,
       k.source_kyc_reference::text, k.batch_id::text,
       k.source_system_id::text, 'verification_status',
       'M6_KYC_MISSING_DOCUMENT', 'KYC_GAP',
       'Source KYC verification is missing a required document; Member 5 must link a verification case',
       'REPORTABLE'
FROM bronze.raw_kyc_verification k
WHERE k.verification_status = 'MISSING_DOCUMENT'

UNION ALL
SELECT 'BRONZE', 'RAW_KYC_VERIFICATION', k.bronze_record_reference::text,
       k.source_kyc_reference::text, k.batch_id::text,
       k.source_system_id::text, 'verification_status',
       'M6_KYC_EXPIRED_STATUS', 'KYC_GAP',
       'Source KYC verification is marked expired; Member 5 must link a verification case',
       'REPORTABLE'
FROM bronze.raw_kyc_verification k
WHERE k.verification_status = 'EXPIRED'

UNION ALL
SELECT 'SILVER', 'SOURCE_CUSTOMER_RECORD', s.source_customer_record_id::text,
       s.source_record_version::text, s.batch_id::text,
       s.source_system_id::text, 'is_current_version',
       'M6_DUPLICATE_CURRENT_SOURCE_VERSION', 'DUPLICATE_CURRENT',
       'More than one current version exists for the same source identity',
       'BLOCKING'
FROM silver.source_customer_record s
WHERE s.is_current_version
  AND EXISTS (
    SELECT 1 FROM silver.source_customer_record x
    WHERE x.source_system_id = s.source_system_id
      AND x.source_customer_reference = s.source_customer_reference
      AND x.is_current_version
      AND x.source_customer_record_id <> s.source_customer_record_id
  )

UNION ALL
SELECT 'SILVER', 'CUSTOMER_SOURCE_MATCH', m.match_id::text,
       s.source_record_version::text, s.batch_id::text,
       s.source_system_id::text, 'customer_id',
       'M6_ACCEPTED_MATCH_NO_CUSTOMER', 'IDENTITY_INTEGRITY',
       'An ACCEPTED match has no confirmed customer ID', 'BLOCKING'
FROM silver.customer_source_match m
JOIN silver.source_customer_record s
  ON s.source_customer_record_id = m.source_customer_record_id
WHERE m.match_status = 'ACCEPTED' AND m.customer_id IS NULL

UNION ALL
SELECT 'SILVER', 'CUSTOMER_SOURCE_MATCH', m.match_id::text,
       s.source_record_version::text, s.batch_id::text,
       s.source_system_id::text, 'is_current_match',
       'M6_DUPLICATE_CURRENT_ACCEPTED_MATCH', 'IDENTITY_INTEGRITY',
       'A source identity has more than one current ACCEPTED match',
       'BLOCKING'
FROM silver.customer_source_match m
JOIN silver.source_customer_record s
  ON s.source_customer_record_id = m.source_customer_record_id
WHERE m.is_current_match AND m.match_status = 'ACCEPTED'
  AND EXISTS (
    SELECT 1
    FROM silver.customer_source_match m2
    JOIN silver.source_customer_record s2
      ON s2.source_customer_record_id = m2.source_customer_record_id
    WHERE s2.source_system_id = s.source_system_id
      AND s2.source_customer_reference = s.source_customer_reference
      AND m2.is_current_match AND m2.match_status = 'ACCEPTED'
      AND m2.match_id <> m.match_id
  )

UNION ALL
SELECT 'SILVER', 'CUSTOMER_ATTRIBUTE_SOURCE', a.attribute_source_id::text,
       a.effective_from::text, NULL::text, NULL::text, 'is_current',
       'M6_DUPLICATE_CURRENT_ATTRIBUTE_SOURCE', 'DUPLICATE_CURRENT',
       'A customer attribute has more than one current selected source',
       'BLOCKING'
FROM silver.customer_attribute_source a
WHERE a.is_current
  AND EXISTS (
    SELECT 1 FROM silver.customer_attribute_source a2
    WHERE a2.customer_id = a.customer_id
      AND a2.attribute_name = a.attribute_name
      AND a2.is_current
      AND a2.attribute_source_id <> a.attribute_source_id
  )

UNION ALL
SELECT 'GOLD', 'DIM_CUSTOMER', d.customer_key::text,
       d.effective_from::text, NULL::text, NULL::text, 'current_flag',
       'M6_DUPLICATE_CURRENT_CUSTOMER_DIM', 'DUPLICATE_CURRENT',
       'A customer has more than one current dimension row', 'BLOCKING'
FROM gold.dim_customer d
WHERE d.current_flag
  AND EXISTS (
    SELECT 1 FROM gold.dim_customer d2
    WHERE d2.customer_id = d.customer_id AND d2.current_flag
      AND d2.customer_key <> d.customer_key
  )

UNION ALL
SELECT 'GOLD', 'FACT_CUSTOMER_SNAPSHOT', f.customer_snapshot_id::text,
       f.snapshot_date::text, NULL::text, NULL::text, 'customer_key',
       'M6_FACT_DIM_CUSTOMER_MISMATCH', 'REPORTING_INTEGRITY',
       'Snapshot customer ID differs from its customer dimension ID',
       'BLOCKING'
FROM gold.fact_customer_snapshot f
JOIN gold.dim_customer d ON d.customer_key = f.customer_key
WHERE f.customer_id <> d.customer_id

UNION ALL
SELECT 'GOLD', 'FACT_COMPLIANCE_EXCEPTION', e.exception_fact_id::text,
       e.as_of_date::text, NULL::text, NULL::text,
       'verification_case_id/aml_case_id',
       'M6_EXCEPTION_CASE_LINK_INVALID', 'REPORTING_INTEGRITY',
       'Exactly one verification or AML case must be linked', 'BLOCKING'
FROM gold.fact_compliance_exception e
WHERE (e.verification_case_id IS NULL) = (e.aml_case_id IS NULL);

COMMENT ON VIEW silver.vw_member6_quality_findings IS
  'Member 6 read-only structural and KYC-gap findings. Member 1 owns CDC load failures; Member 5 owns reportable KYC/AML cases.';

-- Expected after Member 1 demo: CDC-019 appears as M6_CDC_INVALID_OPERATION.
SELECT rule_name, data_layer, entity_name, record_reference, severity
FROM silver.vw_member6_quality_findings
ORDER BY rule_name, record_reference;
