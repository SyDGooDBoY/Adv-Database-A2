-- Creates the reusable incremental CDC process, including validation, failure logging and watermark control.

-- Counts all raw business records retained in Bronze for one batch.
CREATE OR REPLACE FUNCTION silver.count_bronze_batch_records(
  p_batch_id varchar
)
RETURNS integer
LANGUAGE sql
STABLE
AS $count_records$
  SELECT count(*)::integer
  FROM (
    SELECT 1 FROM bronze.raw_crm_customer WHERE batch_id = p_batch_id
    UNION ALL
    SELECT 1 FROM bronze.raw_lending_customer WHERE batch_id = p_batch_id
    UNION ALL
    SELECT 1 FROM bronze.raw_aml_kyc_customer WHERE batch_id = p_batch_id
    UNION ALL
    SELECT 1 FROM bronze.raw_banking_account_snapshot WHERE batch_id = p_batch_id
    UNION ALL
    SELECT 1 FROM bronze.raw_loan_snapshot WHERE batch_id = p_batch_id
    UNION ALL
    SELECT 1 FROM bronze.raw_account_transaction WHERE batch_id = p_batch_id
    UNION ALL
    SELECT 1 FROM bronze.raw_kyc_verification WHERE batch_id = p_batch_id
    UNION ALL
    SELECT 1 FROM bronze.raw_aml_screening WHERE batch_id = p_batch_id
  ) batch_rows;
$count_records$;

-- Marks a batch as failed without advancing its watermark and records a blocking quality issue.
CREATE OR REPLACE FUNCTION silver.record_load_failure(
  p_batch_id varchar,
  p_source_system_id varchar,
  p_rule_name varchar,
  p_error_message text
)
RETURNS void
LANGUAGE plpgsql
AS $record_failure$
DECLARE
  v_issue_id varchar(50);
  v_version_reference varchar(150);
BEGIN
  UPDATE silver.ingestion_batch
  SET
    completed_at = clock_timestamp(),
    load_status = 'FAILED',
    records_processed = 0,
    watermark_end = NULL
  WHERE batch_id = p_batch_id;

  SELECT COALESCE(watermark_end, 'UNKNOWN')
  INTO v_version_reference
  FROM source_systems.ingestion_batch
  WHERE batch_id = p_batch_id;

  v_issue_id := 'DQ-LOAD-' || substr(
    md5(p_batch_id || ':' || p_rule_name),
    1,
    32
  );

  INSERT INTO silver.data_quality_issue (
    data_quality_issue_id,
    batch_id,
    source_system_id,
    verification_case_id,
    validation_run_id,
    data_layer,
    entity_name,
    record_reference,
    record_version_reference,
    attribute_name,
    rule_name,
    rule_version,
    issue_type,
    issue_description,
    severity,
    detected_at,
    resolved_at,
    issue_status
  )
  VALUES (
    v_issue_id,
    p_batch_id,
    p_source_system_id,
    NULL,
    'LOAD-' || p_batch_id,
    'BRONZE',
    'CDC_CHANGE_EVENT',
    p_batch_id,
    v_version_reference,
    NULL,
    p_rule_name,
    '1.0',
    'LOAD_VALIDATION',
    left(p_error_message, 1000),
    'BLOCKING',
    clock_timestamp(),
    NULL,
    'OPEN'
  )
  ON CONFLICT (data_quality_issue_id) DO UPDATE SET
    issue_description = EXCLUDED.issue_description,
    severity = EXCLUDED.severity,
    detected_at = EXCLUDED.detected_at,
    resolved_at = NULL,
    issue_status = 'OPEN';
END;
$record_failure$;

-- Stages, validates and publishes one simulated CDC batch with safe retry behaviour.
CREATE OR REPLACE PROCEDURE silver.process_incremental_batch(
  p_batch_id varchar,
  p_force_failure boolean DEFAULT FALSE
)
LANGUAGE plpgsql
AS $process_batch$
DECLARE
  v_spec source_systems.ingestion_batch%ROWTYPE;
  v_existing_status varchar(30);
  v_previous_watermark varchar(150);
  v_raw_count integer;
  v_event_count integer;
  v_invalid_operation_count integer;
  v_source_mismatch_count integer;
  v_missing_reference_count integer;
  v_bad_sequence_count integer;
  v_error_message text;
BEGIN
  -- Loads the source batch specification and skips batches already committed successfully.
  SELECT *
  INTO v_spec
  FROM source_systems.ingestion_batch
  WHERE batch_id = p_batch_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Unknown source batch: %', p_batch_id;
  END IF;

  IF v_spec.load_type <> 'SIMULATED_CDC' THEN
    RAISE EXCEPTION
      'Batch % has load_type %, expected SIMULATED_CDC',
      p_batch_id,
      v_spec.load_type;
  END IF;

  SELECT load_status
  INTO v_existing_status
  FROM silver.ingestion_batch
  WHERE batch_id = p_batch_id;

  IF v_existing_status = 'SUCCEEDED' THEN
    RAISE NOTICE 'Batch % already succeeded; no data or watermark changed', p_batch_id;
    RETURN;
  END IF;

  -- Reads the last committed watermark and initialises the Silver control row as RUNNING.
  SELECT watermark_end
  INTO v_previous_watermark
  FROM silver.vw_latest_successful_watermark
  WHERE source_system_id = v_spec.source_system_id;

  INSERT INTO bronze.source_system
  SELECT *
  FROM source_systems.source_system
  WHERE source_system_id = v_spec.source_system_id
  ON CONFLICT (source_system_id) DO NOTHING;

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
  FROM source_systems.source_system
  WHERE source_system_id = v_spec.source_system_id
  ON CONFLICT (source_system_id) DO UPDATE SET
    system_name = EXCLUDED.system_name,
    system_type = EXCLUDED.system_type,
    system_description = EXCLUDED.system_description,
    system_owner = EXCLUDED.system_owner,
    active_flag = EXCLUDED.active_flag;

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
  VALUES (
    p_batch_id,
    v_spec.source_system_id,
    v_spec.load_type,
    clock_timestamp(),
    NULL,
    'RUNNING',
    v_spec.records_received,
    0,
    v_previous_watermark,
    NULL
  )
  ON CONFLICT (batch_id) DO UPDATE SET
    started_at = EXCLUDED.started_at,
    completed_at = NULL,
    load_status = 'RUNNING',
    records_received = EXCLUDED.records_received,
    records_processed = 0,
    watermark_start = EXCLUDED.watermark_start,
    watermark_end = NULL;

  -- Retains the batch controls, raw records and CDC events in Bronze before validation.
  INSERT INTO bronze.ingestion_batch
  SELECT *
  FROM source_systems.ingestion_batch
  WHERE batch_id = p_batch_id
  ON CONFLICT (batch_id) DO NOTHING;

  INSERT INTO bronze.raw_crm_customer
  SELECT * FROM source_systems.raw_crm_customer WHERE batch_id = p_batch_id
  ON CONFLICT (bronze_record_reference) DO NOTHING;

  INSERT INTO bronze.raw_lending_customer
  SELECT * FROM source_systems.raw_lending_customer WHERE batch_id = p_batch_id
  ON CONFLICT (bronze_record_reference) DO NOTHING;

  INSERT INTO bronze.raw_aml_kyc_customer
  SELECT * FROM source_systems.raw_aml_kyc_customer WHERE batch_id = p_batch_id
  ON CONFLICT (bronze_record_reference) DO NOTHING;

  INSERT INTO bronze.raw_banking_account_snapshot
  SELECT * FROM source_systems.raw_banking_account_snapshot WHERE batch_id = p_batch_id
  ON CONFLICT (bronze_record_reference) DO NOTHING;

  INSERT INTO bronze.raw_loan_snapshot
  SELECT * FROM source_systems.raw_loan_snapshot WHERE batch_id = p_batch_id
  ON CONFLICT (bronze_record_reference) DO NOTHING;

  INSERT INTO bronze.raw_account_transaction
  SELECT * FROM source_systems.raw_account_transaction WHERE batch_id = p_batch_id
  ON CONFLICT (bronze_record_reference) DO NOTHING;

  INSERT INTO bronze.raw_kyc_verification
  SELECT * FROM source_systems.raw_kyc_verification WHERE batch_id = p_batch_id
  ON CONFLICT (bronze_record_reference) DO NOTHING;

  INSERT INTO bronze.raw_aml_screening
  SELECT * FROM source_systems.raw_aml_screening WHERE batch_id = p_batch_id
  ON CONFLICT (bronze_record_reference) DO NOTHING;

  INSERT INTO bronze.cdc_change_event
  SELECT *
  FROM source_systems.cdc_change_event
  WHERE batch_id = p_batch_id
  ON CONFLICT (change_event_id) DO NOTHING;

  -- Provides a controlled failure after staging to demonstrate Bronze retention and retry.
  IF p_force_failure THEN
    PERFORM silver.record_load_failure(
      p_batch_id,
      v_spec.source_system_id,
      'forced_failure_demo',
      'Intentional failure used to prove that Bronze is retained, the watermark does not advance and the batch can be retried.'
    );
    RAISE NOTICE 'Batch % intentionally failed after Bronze staging', p_batch_id;
    RETURN;
  END IF;

  BEGIN
    -- Validates row counts, operation codes, source ownership, payload references and event sequences.
    v_raw_count := silver.count_bronze_batch_records(p_batch_id);

    SELECT count(*)::integer
    INTO v_event_count
    FROM bronze.cdc_change_event
    WHERE batch_id = p_batch_id;

    SELECT count(*)::integer
    INTO v_invalid_operation_count
    FROM bronze.cdc_change_event
    WHERE batch_id = p_batch_id
      AND COALESCE(operation_type, '') NOT IN ('I', 'U', 'D');

    SELECT count(*)::integer
    INTO v_source_mismatch_count
    FROM (
      SELECT source_system_id
      FROM bronze.cdc_change_event
      WHERE batch_id = p_batch_id
      UNION ALL
      SELECT source_system_id FROM bronze.raw_crm_customer WHERE batch_id = p_batch_id
      UNION ALL
      SELECT source_system_id FROM bronze.raw_lending_customer WHERE batch_id = p_batch_id
      UNION ALL
      SELECT source_system_id FROM bronze.raw_aml_kyc_customer WHERE batch_id = p_batch_id
      UNION ALL
      SELECT source_system_id FROM bronze.raw_banking_account_snapshot WHERE batch_id = p_batch_id
      UNION ALL
      SELECT source_system_id FROM bronze.raw_loan_snapshot WHERE batch_id = p_batch_id
      UNION ALL
      SELECT source_system_id FROM bronze.raw_account_transaction WHERE batch_id = p_batch_id
      UNION ALL
      SELECT source_system_id FROM bronze.raw_kyc_verification WHERE batch_id = p_batch_id
      UNION ALL
      SELECT source_system_id FROM bronze.raw_aml_screening WHERE batch_id = p_batch_id
    ) batch_sources
    WHERE source_system_id IS DISTINCT FROM v_spec.source_system_id;

    SELECT count(*)::integer
    INTO v_missing_reference_count
    FROM bronze.cdc_change_event event_row
    WHERE event_row.batch_id = p_batch_id
      AND NOT EXISTS (
        SELECT 1
        FROM (
          SELECT bronze_record_reference FROM bronze.raw_crm_customer WHERE batch_id = p_batch_id
          UNION ALL
          SELECT bronze_record_reference FROM bronze.raw_lending_customer WHERE batch_id = p_batch_id
          UNION ALL
          SELECT bronze_record_reference FROM bronze.raw_aml_kyc_customer WHERE batch_id = p_batch_id
          UNION ALL
          SELECT bronze_record_reference FROM bronze.raw_banking_account_snapshot WHERE batch_id = p_batch_id
          UNION ALL
          SELECT bronze_record_reference FROM bronze.raw_loan_snapshot WHERE batch_id = p_batch_id
          UNION ALL
          SELECT bronze_record_reference FROM bronze.raw_account_transaction WHERE batch_id = p_batch_id
          UNION ALL
          SELECT bronze_record_reference FROM bronze.raw_kyc_verification WHERE batch_id = p_batch_id
          UNION ALL
          SELECT bronze_record_reference FROM bronze.raw_aml_screening WHERE batch_id = p_batch_id
        ) raw_reference
        WHERE raw_reference.bronze_record_reference =
          event_row.change_payload::jsonb ->> 'bronze_record_reference'
      );

    WITH batch_sequence AS (
      SELECT
        source_system_id,
        source_entity_name,
        min(event_sequence) AS min_sequence,
        max(event_sequence) AS max_sequence,
        count(*) AS event_count,
        count(DISTINCT event_sequence) AS distinct_count
      FROM bronze.cdc_change_event
      WHERE batch_id = p_batch_id
      GROUP BY source_system_id, source_entity_name
    ),
    sequence_with_prior AS (
      SELECT
        batch_sequence.*,
        COALESCE((
          SELECT max(previous_event.event_sequence)
          FROM silver.cdc_change_event previous_event
          WHERE previous_event.source_system_id = batch_sequence.source_system_id
            AND previous_event.source_entity_name = batch_sequence.source_entity_name
        ), 0) AS prior_max_sequence
      FROM batch_sequence
    )
    SELECT count(*)::integer
    INTO v_bad_sequence_count
    FROM sequence_with_prior
    WHERE distinct_count <> event_count
       OR max_sequence - min_sequence + 1 <> event_count
       OR min_sequence <> prior_max_sequence + 1;

    -- Combines all validation failures into one batch-level error message.
    v_error_message := NULL;

    IF v_spec.watermark_start IS DISTINCT FROM v_previous_watermark THEN
      v_error_message := concat_ws(
        '; ',
        v_error_message,
        format(
          'watermark_start %s does not match last successful watermark %s',
          COALESCE(v_spec.watermark_start, 'NULL'),
          COALESCE(v_previous_watermark, 'NULL')
        )
      );
    END IF;

    IF v_spec.watermark_end IS NULL THEN
      v_error_message := concat_ws('; ', v_error_message, 'watermark_end is missing');
    END IF;

    IF v_raw_count <> v_spec.records_received THEN
      v_error_message := concat_ws(
        '; ',
        v_error_message,
        format('expected %s raw rows but found %s', v_spec.records_received, v_raw_count)
      );
    END IF;

    IF v_event_count <> v_spec.records_received THEN
      v_error_message := concat_ws(
        '; ',
        v_error_message,
        format('expected %s CDC events but found %s', v_spec.records_received, v_event_count)
      );
    END IF;

    IF v_invalid_operation_count > 0 THEN
      v_error_message := concat_ws(
        '; ',
        v_error_message,
        format('%s CDC events have an invalid operation_type', v_invalid_operation_count)
      );
    END IF;

    IF v_source_mismatch_count > 0 THEN
      v_error_message := concat_ws(
        '; ',
        v_error_message,
        format('%s staged rows do not match the batch source system', v_source_mismatch_count)
      );
    END IF;

    IF v_missing_reference_count > 0 THEN
      v_error_message := concat_ws(
        '; ',
        v_error_message,
        format('%s CDC payload references cannot be found in Bronze', v_missing_reference_count)
      );
    END IF;

    IF v_bad_sequence_count > 0 THEN
      v_error_message := concat_ws(
        '; ',
        v_error_message,
        format('%s source/entity streams have invalid event sequencing', v_bad_sequence_count)
      );
    END IF;

    IF v_error_message IS NOT NULL THEN
      PERFORM silver.record_load_failure(
        p_batch_id,
        v_spec.source_system_id,
        'incremental_batch_validation',
        v_error_message
      );
      RAISE NOTICE 'Batch % failed validation: %', p_batch_id, v_error_message;
      RETURN;
    END IF;

    -- Publishes valid CDC events, commits the watermark and resolves earlier retryable issues.
    INSERT INTO silver.cdc_change_event (
      change_event_id,
      source_system_id,
      batch_id,
      source_entity_name,
      source_record_reference,
      source_version_reference,
      operation_type,
      event_sequence,
      source_change_time,
      captured_at,
      change_payload
    )
    SELECT
      change_event_id,
      source_system_id,
      batch_id,
      source_entity_name,
      source_record_reference,
      source_version_reference,
      operation_type,
      event_sequence,
      source_change_time,
      captured_at,
      change_payload
    FROM bronze.cdc_change_event
    WHERE batch_id = p_batch_id
    ORDER BY source_entity_name, event_sequence
    ON CONFLICT (change_event_id) DO NOTHING;

    UPDATE silver.ingestion_batch
    SET
      completed_at = clock_timestamp(),
      load_status = 'SUCCEEDED',
      records_processed = v_raw_count,
      watermark_end = v_spec.watermark_end
    WHERE batch_id = p_batch_id;

    UPDATE silver.data_quality_issue
    SET
      resolved_at = clock_timestamp(),
      issue_status = 'RESOLVED'
    WHERE batch_id = p_batch_id
      AND issue_type = 'LOAD_VALIDATION'
      AND issue_status = 'OPEN';

    RAISE NOTICE
      'Batch % succeeded: % records processed, watermark advanced to %',
      p_batch_id,
      v_raw_count,
      v_spec.watermark_end;
  EXCEPTION
    WHEN OTHERS THEN
      -- Converts unexpected runtime errors into the same failed-batch control state.
      GET STACKED DIAGNOSTICS v_error_message = MESSAGE_TEXT;
      PERFORM silver.record_load_failure(
        p_batch_id,
        v_spec.source_system_id,
        'incremental_runtime_error',
        v_error_message
      );
      RAISE NOTICE 'Batch % failed with runtime error: %', p_batch_id, v_error_message;
  END;
END;
$process_batch$;

COMMENT ON PROCEDURE silver.process_incremental_batch(varchar, boolean) IS
  'Stages one simulated CDC batch in Bronze, validates it, publishes valid events to Silver and advances the watermark only after success.';
