-- Install the procedure, then CALL it separately (see README).
-- Processing-time history: never backdate a decision to the source timestamp.
CREATE OR REPLACE PROCEDURE silver.apply_member3_survivorship()
LANGUAGE plpgsql AS $procedure$
DECLARE
  c record; a record; winner record; previous record;
  old_value text; new_value text; chosen_id varchar(50);
  has_winner boolean; has_previous boolean; selection_changed boolean;
  run_at timestamp; run_id text; event_id text; next_status text;
BEGIN
  -- Serialise with source/matching writers for a consistent input snapshot.
  LOCK TABLE silver.customer_master, silver.source_customer_record,
    silver.customer_source_match, silver.ingestion_batch,
    silver.customer_attribute_source, silver.customer_history,
    silver.data_lineage_record IN SHARE ROW EXCLUSIVE MODE;

  IF EXISTS (
    SELECT 1 FROM silver.customer_source_match m
    JOIN silver.source_customer_record s USING(source_customer_record_id)
    WHERE m.is_current_match AND m.match_status = 'ACCEPTED'
    GROUP BY s.source_system_id, s.source_customer_reference HAVING count(*) > 1
  ) THEN RAISE EXCEPTION 'More than one current accepted match per source identity'; END IF;
  IF EXISTS (
    SELECT 1 FROM silver.customer_source_match m
    JOIN silver.source_customer_record s USING(source_customer_record_id)
    JOIN silver.ingestion_batch b ON b.batch_id = s.batch_id
    WHERE m.is_current_match AND m.match_status = 'ACCEPTED'
      AND (m.customer_id IS NULL OR m.effective_to IS NOT NULL
        OR NOT s.is_current_version OR s.valid_to IS NOT NULL
        OR b.load_status <> 'SUCCEEDED' OR b.source_system_id <> s.source_system_id)
  ) THEN RAISE EXCEPTION 'Accepted matching input is inconsistent; rerun/fix Member 2 first'; END IF;

  run_at := greatest(clock_timestamp()::timestamp,
    coalesce((SELECT max(effective_from) + interval '1 microsecond'
              FROM silver.customer_attribute_source), '-infinity'::timestamp),
    coalesce((SELECT max(effective_from) + interval '1 microsecond'
              FROM silver.customer_history), '-infinity'::timestamp));
  run_id := 'M3-' || md5(run_at::text);

  FOR c IN
    SELECT cm.* FROM silver.customer_master cm
    WHERE cm.customer_status = 'PENDING_SURVIVORSHIP'
      OR EXISTS (SELECT 1 FROM silver.customer_source_match m
        WHERE m.customer_id = cm.customer_id AND m.is_current_match AND m.match_status = 'ACCEPTED')
      OR EXISTS (SELECT 1 FROM silver.customer_attribute_source p
        WHERE p.customer_id = cm.customer_id AND p.survivorship_rule LIKE 'v1:%')
    ORDER BY cm.customer_id
  LOOP
    FOR a IN SELECT * FROM (VALUES
      ('customer_full_name'), ('date_of_birth'), ('email_address'),
      ('phone_number'), ('residential_address')) attrs(attribute_name)
    LOOP
      SELECT * INTO winner FROM silver.v_member3_attribute_candidates
        WHERE customer_id = c.customer_id AND attribute_name = a.attribute_name AND candidate_rank = 1;
      has_winner := FOUND;
      SELECT * INTO previous FROM silver.customer_attribute_source
        WHERE customer_id = c.customer_id AND attribute_name = a.attribute_name AND is_current;
      has_previous := FOUND;
      old_value := to_jsonb(c) ->> a.attribute_name;

      IF NOT has_winner THEN
        -- Retain the last known master value, but do NOT claim its old source
        -- is still current. Its historical selection and lineage remain.
        IF has_previous THEN
          UPDATE silver.customer_attribute_source SET effective_to = run_at, is_current = FALSE
            WHERE attribute_source_id = previous.attribute_source_id;
          UPDATE silver.customer_master SET last_updated_at = run_at WHERE customer_id = c.customer_id;
          event_id := 'LIN-' || md5(run_id || previous.attribute_source_id || '|withdraw');
          INSERT INTO silver.data_lineage_record (
            lineage_id, transformation_run_id, source_layer, source_entity_name,
            source_record_reference, source_version_reference, source_attribute_name,
            source_record_snapshot, target_layer, target_entity_name,
            target_record_reference, target_version_reference, target_attribute_name,
            target_record_snapshot, transformation_name, transformation_version, transformation_timestamp
          ) VALUES (
            event_id, run_id, 'silver', 'customer_attribute_source', previous.attribute_source_id,
            previous.effective_from::text, a.attribute_name, to_jsonb(previous)::text,
            'silver', 'customer_master', c.customer_id, run_id, a.attribute_name,
            jsonb_build_object('retained_value', old_value, 'current_source', NULL,
              'reason', 'No eligible nonblank source; last known value retained')::text,
            'member3_withdraw_current_source', 'v1', run_at
          );
        END IF;
        CONTINUE;
      END IF;

      new_value := winner.selected_value;
      selection_changed := NOT has_previous;
      IF has_previous THEN
        selection_changed := previous.match_id IS DISTINCT FROM winner.match_id
          OR previous.selected_value IS DISTINCT FROM new_value
          OR previous.survivorship_rule IS DISTINCT FROM winner.survivorship_rule;
      END IF;
      IF NOT selection_changed AND old_value IS NOT DISTINCT FROM new_value THEN CONTINUE; END IF;

      IF selection_changed THEN
        IF has_previous THEN
          UPDATE silver.customer_attribute_source SET effective_to = run_at, is_current = FALSE
            WHERE attribute_source_id = previous.attribute_source_id;
        END IF;
        chosen_id := 'AS-' || md5(run_id || '|' || c.customer_id || '|' || a.attribute_name);
        INSERT INTO silver.customer_attribute_source VALUES (
          chosen_id, c.customer_id, winner.match_id, a.attribute_name, new_value,
          winner.survivorship_rule, run_at, NULL, TRUE
        );
      ELSE chosen_id := previous.attribute_source_id;
      END IF;

      IF old_value IS DISTINCT FROM new_value THEN
        -- Half-open periods [from,to) describe when new_value was the master value.
        UPDATE silver.customer_history SET effective_to = run_at
          WHERE customer_id = c.customer_id AND attribute_name = a.attribute_name AND effective_to IS NULL;
        INSERT INTO silver.customer_history VALUES (
          'HIST-' || md5(run_id || '|' || c.customer_id || '|' || a.attribute_name),
          c.customer_id, chosen_id, a.attribute_name, old_value, new_value,
          run_at, NULL,
          CASE WHEN c.customer_status = 'PENDING_SURVIVORSHIP' AND NOT has_previous
            THEN 'INITIAL_SELECTION: ' ELSE 'VALUE_CHANGE: ' END || winner.survivorship_rule
        );
        IF a.attribute_name = 'date_of_birth' THEN
          UPDATE silver.customer_master SET date_of_birth = new_value::date, last_updated_at = run_at
            WHERE customer_id = c.customer_id;
        ELSE
          EXECUTE format('UPDATE silver.customer_master SET %I = $1, last_updated_at = $2 WHERE customer_id = $3', a.attribute_name)
            USING new_value, run_at, c.customer_id;
        END IF;
      ELSE
        UPDATE silver.customer_master SET last_updated_at = run_at WHERE customer_id = c.customer_id;
      END IF;

      INSERT INTO silver.data_lineage_record (
        lineage_id, batch_id, source_system_id, transformation_run_id,
        source_layer, source_entity_name, source_record_reference, source_version_reference,
        source_attribute_name, source_record_snapshot, target_layer, target_entity_name,
        target_record_reference, target_version_reference, target_attribute_name,
        target_record_snapshot, transformation_name, transformation_version, transformation_timestamp
      ) VALUES (
        'LIN-' || md5(run_id || '|' || c.customer_id || '|' || a.attribute_name),
        winner.batch_id, winner.source_system_id, run_id, 'silver', 'source_customer_record',
        winner.source_customer_record_id, winner.source_record_version::text,
        winner.source_attribute_name,
        jsonb_build_object('raw_value', winner.raw_value, 'match_id', winner.match_id,
          'bronze_record_reference', winner.bronze_record_reference,
          'source_last_updated_at', winner.source_last_updated_at)::text,
        'silver', 'customer_master', c.customer_id, run_id, a.attribute_name,
        jsonb_build_object('selected_value', new_value, 'previous_value', old_value,
          'attribute_source_id', chosen_id, 'rule', winner.survivorship_rule)::text,
        'member3_attribute_survivorship', 'v1', run_at
      );
    END LOOP;

    -- This is integration status, not a KYC verdict or bank account status.
    next_status := CASE
      WHEN NOT EXISTS (SELECT 1 FROM silver.customer_source_match m
        WHERE m.customer_id = c.customer_id AND m.match_status = 'ACCEPTED' AND m.is_current_match)
        THEN 'NO_CURRENT_SOURCE'
      WHEN EXISTS (SELECT 1 FROM silver.v_member3_attribute_candidates v
        WHERE v.customer_id = c.customer_id AND v.attribute_name = 'customer_full_name') THEN 'ACTIVE'
      ELSE 'PENDING_SURVIVORSHIP' END;
    IF c.customer_status IS DISTINCT FROM next_status THEN
      INSERT INTO silver.customer_history VALUES (
        'HIST-' || md5(run_id || '|' || c.customer_id || '|customer_status'),
        c.customer_id, NULL, 'customer_status', c.customer_status, next_status, run_at, NULL,
        'DERIVED_STATUS: v1 current accepted sources and available name; not a compliance verdict'
      );
      UPDATE silver.customer_history SET effective_to = run_at
        WHERE customer_id = c.customer_id AND attribute_name = 'customer_status'
          AND effective_to IS NULL AND effective_from < run_at;
      INSERT INTO silver.data_lineage_record (
        lineage_id, transformation_run_id, source_layer, source_entity_name,
        source_record_reference, source_version_reference, source_record_snapshot,
        target_layer, target_entity_name, target_record_reference, target_version_reference,
        target_attribute_name, target_record_snapshot, transformation_name,
        transformation_version, transformation_timestamp
      ) VALUES (
        'LIN-' || md5(run_id || '|' || c.customer_id || '|customer_status'), run_id,
        'silver', 'customer_master', c.customer_id, c.last_updated_at::text,
        jsonb_build_object('previous_master', to_jsonb(c), 'decision_context',
          (SELECT coalesce(jsonb_agg(to_jsonb(m)), '[]'::jsonb) FROM silver.customer_source_match m
            WHERE m.customer_id = c.customer_id), 'has_nonblank_name',
          EXISTS (SELECT 1 FROM silver.v_member3_attribute_candidates v
            WHERE v.customer_id = c.customer_id AND v.attribute_name = 'customer_full_name'))::text,
        'silver', 'customer_master', c.customer_id, run_id, 'customer_status',
        jsonb_build_object('old_value', c.customer_status, 'new_value', next_status)::text,
        'member3_derived_integration_status', 'v1', run_at
      );
      UPDATE silver.customer_master SET customer_status = next_status, last_updated_at = run_at
        WHERE customer_id = c.customer_id;
    END IF;
  END LOOP;
END;
$procedure$;

-- Execute separately after installing this file:
-- CALL silver.apply_member3_survivorship();
