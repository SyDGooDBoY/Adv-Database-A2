-- PostgreSQL 15+
-- Member 5: create the minimum customer identity that this module's events reference.
-- silver.customer_master and silver.source_customer_record belong to Member 2's identity
-- resolution. Only missing identities are added, so resolved results are never changed.

CREATE OR REPLACE PROCEDURE silver.load_kyc_aml_customer_identity()
LANGUAGE plpgsql
AS $load_identity$
DECLARE
  v_reference_count integer;
  v_created_customers integer;
  v_created_source_records integer;
  v_linked_records integer;
BEGIN
  DROP TABLE IF EXISTS tmp_kyc_aml_reference;
  CREATE TEMP TABLE tmp_kyc_aml_reference (
    source_customer_reference varchar(100) PRIMARY KEY,
    earliest_event_at timestamp NOT NULL
  )
  ON COMMIT DROP;

  INSERT INTO tmp_kyc_aml_reference (source_customer_reference, earliest_event_at)
  SELECT
    source_reference.source_customer_reference,
    min(source_reference.first_seen_at)
  FROM (
    SELECT
      btrim(raw.source_customer_reference) AS source_customer_reference,
      min(raw.verification_date) AS first_seen_at
    FROM bronze.raw_kyc_verification raw
    WHERE COALESCE(btrim(raw.source_customer_reference), '') <> ''
    GROUP BY btrim(raw.source_customer_reference)
    UNION ALL
    SELECT
      btrim(raw.source_customer_reference) AS source_customer_reference,
      min(raw.screening_date) AS first_seen_at
    FROM bronze.raw_aml_screening raw
    WHERE COALESCE(btrim(raw.source_customer_reference), '') <> ''
    GROUP BY btrim(raw.source_customer_reference)
  ) source_reference
  GROUP BY source_reference.source_customer_reference;

  SELECT count(*)::integer
  INTO v_reference_count
  FROM tmp_kyc_aml_reference;

  -- One retained Silver record per source customer identity.
  DROP TABLE IF EXISTS tmp_kyc_aml_source_record;
  CREATE TEMP TABLE tmp_kyc_aml_source_record
  ON COMMIT DROP
  AS
  SELECT
    source_reference.source_customer_reference,
    'SCR-' || upper(substr(md5('AMLKYC:' || source_reference.source_customer_reference), 1, 16))
      AS source_customer_record_id
  FROM tmp_kyc_aml_reference source_reference;

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
    staged.source_customer_record_id,
    'AMLKYC',
    COALESCE(raw.batch_id, 'B1-AMLKYC'),
    staged.source_customer_reference,
    COALESCE(raw.source_record_version, 1),
    COALESCE(raw.bronze_record_reference, 'BR-AMLKYC-CUSTOMER-' || staged.source_customer_reference),
    raw.source_full_name,
    raw.source_date_of_birth,
    raw.source_email_address,
    raw.source_phone_number,
    raw.source_address,
    raw.source_last_updated_at,
    COALESCE(source_reference.earliest_event_at, timestamp '2026-09-01 07:00:00'),
    NULL,
    true,
    md5(
      concat_ws(
        '|',
        'AMLKYC',
        staged.source_customer_reference,
        COALESCE(raw.source_full_name, ''),
        COALESCE(raw.source_email_address, ''),
        COALESCE(raw.source_phone_number, '')
      )
    )
  FROM tmp_kyc_aml_source_record staged
  JOIN tmp_kyc_aml_reference source_reference
    ON source_reference.source_customer_reference = staged.source_customer_reference
  LEFT JOIN LATERAL (
    SELECT
      retained.batch_id,
      retained.source_record_version,
      retained.bronze_record_reference,
      retained.source_full_name,
      retained.source_date_of_birth,
      retained.source_email_address,
      retained.source_phone_number,
      retained.source_address,
      retained.source_last_updated_at
    FROM bronze.raw_aml_kyc_customer retained
    WHERE retained.source_customer_reference = staged.source_customer_reference
    ORDER BY
      retained.source_record_version DESC,
      retained.source_last_updated_at DESC NULLS LAST,
      retained.bronze_record_reference DESC
    LIMIT 1
  ) raw ON true
  WHERE NOT EXISTS (
    SELECT 1
    FROM silver.source_customer_record existing
    WHERE existing.source_system_id = 'AMLKYC'
      AND existing.source_customer_reference = staged.source_customer_reference
  );

  GET DIAGNOSTICS v_created_source_records = ROW_COUNT;

  -- A golden customer for any source record that has no identity mapping yet.
  DROP TABLE IF EXISTS tmp_kyc_aml_customer;
  CREATE TEMP TABLE tmp_kyc_aml_customer
  ON COMMIT DROP
  AS
  SELECT DISTINCT
    source_record.source_customer_reference,
    source_record.source_customer_record_id,
    'CUST-' || upper(substr(md5('AMLKYC:' || source_record.source_customer_reference), 1, 16))
      AS customer_id
  FROM silver.source_customer_record source_record
  WHERE source_record.source_system_id = 'AMLKYC'
    AND NOT EXISTS (
      SELECT 1
      FROM silver.customer_source_match existing_match
      WHERE existing_match.source_customer_record_id = source_record.source_customer_record_id
        AND existing_match.match_status = 'ACCEPTED'
        AND existing_match.is_current_match
    );

  INSERT INTO silver.customer_master (
    customer_id,
    customer_full_name,
    date_of_birth,
    email_address,
    phone_number,
    residential_address,
    suburb_city,
    state_region,
    postcode,
    country_code,
    customer_status,
    customer_since_date,
    created_at,
    last_updated_at
  )
  SELECT
    staged.customer_id,
    COALESCE(source_record.source_full_name, 'Unresolved customer ' || staged.source_customer_reference),
    source_record.source_date_of_birth,
    source_record.source_email_address,
    source_record.source_phone_number,
    source_record.source_address,
    NULL,
    NULL,
    NULL,
    NULL,
    'ACTIVE',
    source_record.valid_from::date,
    source_record.valid_from,
    COALESCE(source_record.source_last_updated_at, source_record.valid_from)
  FROM tmp_kyc_aml_customer staged
  JOIN silver.source_customer_record source_record
    ON source_record.source_customer_record_id = staged.source_customer_record_id
  WHERE NOT EXISTS (
    SELECT 1
    FROM silver.customer_master existing_customer
    WHERE existing_customer.customer_id = staged.customer_id
  );

  GET DIAGNOSTICS v_created_customers = ROW_COUNT;

  -- The match between the source record and that golden customer, with status ACCEPTED
  -- because both sides were created here. Cross-source matches remain Member 2's decision.
  INSERT INTO silver.customer_source_match (
    match_id,
    source_customer_record_id,
    customer_id,
    reviewed_by_user_id,
    match_status,
    match_confidence_score,
    match_rule,
    manual_review_flag,
    effective_from,
    effective_to,
    is_current_match,
    matched_at
  )
  SELECT
    'MATCH-' || upper(substr(md5(staged.source_customer_record_id), 1, 16)),
    staged.source_customer_record_id,
    staged.customer_id,
    NULL,
    'ACCEPTED',
    0.5000,
    'AMLKYC_SINGLE_SOURCE_IDENTITY',
    false,
    source_record.valid_from,
    NULL,
    true,
    source_record.valid_from
  FROM tmp_kyc_aml_customer staged
  JOIN silver.source_customer_record source_record
    ON source_record.source_customer_record_id = staged.source_customer_record_id
  WHERE NOT EXISTS (
    SELECT 1
    FROM silver.customer_source_match existing_match
    WHERE existing_match.source_customer_record_id = staged.source_customer_record_id
      AND existing_match.is_current_match
  );

  GET DIAGNOSTICS v_linked_records = ROW_COUNT;

  RAISE NOTICE
    'KYC/AML identity load: % source references, % new source records, % new customers, % new match decisions',
    v_reference_count,
    v_created_source_records,
    v_created_customers,
    v_linked_records;
END;
$load_identity$;

COMMENT ON PROCEDURE silver.load_kyc_aml_customer_identity() IS
  'Creates the minimal customer identity required by this module''s KYC and AML events without altering any identity already resolved by Member 2.';
