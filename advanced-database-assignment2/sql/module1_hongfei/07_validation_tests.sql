-- Validates the Member 1 pipeline after scripts 01-06 have run.

DO $member1_tests$
DECLARE
  v_count integer;
  v_text text;
BEGIN
  -- Verifies all initial batches and their retained Bronze record counts.
  SELECT count(*)::integer
  INTO v_count
  FROM silver.ingestion_batch
  WHERE load_type = 'INITIAL'
    AND load_status = 'SUCCEEDED'
    AND records_received = records_processed;

  IF v_count <> 3 THEN
    RAISE EXCEPTION 'Expected three successful initial batches, found %', v_count;
  END IF;

  IF silver.count_bronze_batch_records('B1-CRM') <> 34 THEN
    RAISE EXCEPTION 'B1-CRM Bronze count is not 34';
  END IF;

  IF silver.count_bronze_batch_records('B1-LEND') <> 12 THEN
    RAISE EXCEPTION 'B1-LEND Bronze count is not 12';
  END IF;

  IF silver.count_bronze_batch_records('B1-AMLKYC') <> 27 THEN
    RAISE EXCEPTION 'B1-AMLKYC Bronze count is not 27';
  END IF;

  IF silver.count_bronze_batch_records('B2-CRM') <> 12 THEN
    RAISE EXCEPTION 'B2-CRM Bronze count is not 12';
  END IF;

  IF silver.count_bronze_batch_records('B2-LEND') <> 6 THEN
    RAISE EXCEPTION 'B2-LEND Bronze count is not 6';
  END IF;

  IF silver.count_bronze_batch_records('B2-AMLKYC') <> 1 THEN
    RAISE EXCEPTION 'B2-AMLKYC Bronze count is not 1';
  END IF;

  -- Verifies the expected success or failure state of each incremental batch.
  SELECT load_status
  INTO v_text
  FROM silver.ingestion_batch
  WHERE batch_id = 'B2-CRM';

  IF v_text IS DISTINCT FROM 'SUCCEEDED' THEN
    RAISE EXCEPTION 'B2-CRM should be SUCCEEDED, found %', v_text;
  END IF;

  SELECT load_status
  INTO v_text
  FROM silver.ingestion_batch
  WHERE batch_id = 'B2-LEND';

  IF v_text IS DISTINCT FROM 'SUCCEEDED' THEN
    RAISE EXCEPTION 'B2-LEND should be SUCCEEDED, found %', v_text;
  END IF;

  SELECT load_status
  INTO v_text
  FROM silver.ingestion_batch
  WHERE batch_id = 'B2-AMLKYC';

  IF v_text IS DISTINCT FROM 'FAILED' THEN
    RAISE EXCEPTION 'B2-AMLKYC should be FAILED, found %', v_text;
  END IF;

  -- Verifies that only successful batches advanced their source watermark.
  SELECT watermark_end
  INTO v_text
  FROM silver.vw_latest_successful_watermark
  WHERE source_system_id = 'CRM';

  IF v_text IS DISTINCT FROM '2026-09-15' THEN
    RAISE EXCEPTION 'CRM committed watermark should be 2026-09-15, found %', v_text;
  END IF;

  SELECT watermark_end
  INTO v_text
  FROM silver.vw_latest_successful_watermark
  WHERE source_system_id = 'LEND';

  IF v_text IS DISTINCT FROM '2026-09-15' THEN
    RAISE EXCEPTION 'LEND committed watermark should be 2026-09-15, found %', v_text;
  END IF;

  SELECT watermark_end
  INTO v_text
  FROM silver.vw_latest_successful_watermark
  WHERE source_system_id = 'AMLKYC';

  IF v_text IS DISTINCT FROM '2026-09-01' THEN
    RAISE EXCEPTION 'AMLKYC watermark should remain 2026-09-01, found %', v_text;
  END IF;

  -- Verifies raw CDC retention and publication of valid events only.
  SELECT count(*)::integer
  INTO v_count
  FROM bronze.cdc_change_event;

  IF v_count <> 19 THEN
    RAISE EXCEPTION 'Expected 19 retained Bronze CDC events, found %', v_count;
  END IF;

  SELECT count(*)::integer
  INTO v_count
  FROM silver.cdc_change_event;

  IF v_count <> 18 THEN
    RAISE EXCEPTION 'Expected 18 valid Silver CDC events, found %', v_count;
  END IF;

  -- Verifies retained delete/error evidence and failure resolution after retry.
  IF NOT EXISTS (
    SELECT 1
    FROM bronze.raw_crm_customer
    WHERE source_customer_reference = 'CRM-007'
      AND operation_type = 'D'
  ) THEN
    RAISE EXCEPTION 'CRM-007 deletion marker was not retained in Bronze';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM bronze.cdc_change_event
    WHERE change_event_id = 'CDC-019'
      AND operation_type = ''
  ) THEN
    RAISE EXCEPTION 'Invalid CDC-019 raw event was not retained in Bronze';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM silver.data_quality_issue
    WHERE batch_id = 'B2-AMLKYC'
      AND rule_name = 'incremental_batch_validation'
      AND issue_status = 'OPEN'
  ) THEN
    RAISE EXCEPTION 'Expected an open blocking issue for B2-AMLKYC';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM silver.data_quality_issue
    WHERE batch_id = 'B2-CRM'
      AND rule_name = 'forced_failure_demo'
      AND issue_status = 'RESOLVED'
  ) THEN
    RAISE EXCEPTION 'B2-CRM forced-failure issue was not resolved by retry';
  END IF;

  RAISE NOTICE 'All Member 1 acceptance tests passed';
END
$member1_tests$;

-- Displays batch, watermark, CDC and load-quality evidence.
SELECT
  batch_id,
  source_system_id,
  load_type,
  load_status,
  records_received,
  records_processed,
  watermark_start,
  watermark_end
FROM silver.ingestion_batch
ORDER BY source_system_id, started_at, batch_id;

SELECT *
FROM silver.vw_latest_successful_watermark
ORDER BY source_system_id;

SELECT
  batch_id,
  source_system_id,
  source_entity_name,
  operation_type,
  count(*) AS event_count,
  min(event_sequence) AS first_sequence,
  max(event_sequence) AS last_sequence
FROM silver.cdc_change_event
GROUP BY
  batch_id,
  source_system_id,
  source_entity_name,
  operation_type
ORDER BY batch_id, source_entity_name, operation_type;

SELECT
  batch_id,
  rule_name,
  severity,
  issue_status,
  issue_description
FROM silver.data_quality_issue
WHERE issue_type = 'LOAD_VALIDATION'
ORDER BY batch_id, detected_at;
