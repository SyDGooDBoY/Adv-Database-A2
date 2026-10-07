-- PostgreSQL 15+. Install after shared setup and Member 2 scripts 01-04.
-- Prototype policy v1: source preference is NOT evidence of KYC verification.
BEGIN;
CREATE OR REPLACE VIEW silver.v_member3_attribute_candidates AS
WITH eligible AS (
  SELECT m.customer_id, m.match_id, s.*
  FROM silver.customer_source_match m
  JOIN silver.source_customer_record s USING (source_customer_record_id)
  JOIN silver.ingestion_batch b ON b.batch_id = s.batch_id
    AND b.source_system_id = s.source_system_id
  WHERE m.match_status = 'ACCEPTED' AND m.is_current_match
    AND m.effective_to IS NULL AND m.customer_id IS NOT NULL
    AND s.is_current_version AND s.valid_to IS NULL
    AND b.load_status = 'SUCCEEDED'
), values_by_attribute AS (
  SELECT e.*, a.attribute_name, a.source_attribute_name,
    a.raw_value, NULLIF(btrim(a.raw_value), '') AS selected_value,
    a.attribute_name IN ('email_address', 'phone_number') AS latest_first
  FROM eligible e
  CROSS JOIN LATERAL (VALUES
    ('customer_full_name', 'source_full_name', e.source_full_name::text),
    ('date_of_birth', 'source_date_of_birth', e.source_date_of_birth::text),
    ('email_address', 'source_email_address', e.source_email_address::text),
    ('phone_number', 'source_phone_number', e.source_phone_number::text),
    ('residential_address', 'source_address', e.source_address::text)
  ) a(attribute_name, source_attribute_name, raw_value)
), priorities AS (
  SELECT v.*,
    CASE WHEN latest_first THEN
      CASE source_system_id WHEN 'CRM' THEN 1 WHEN 'AMLKYC' THEN 2 WHEN 'LEND' THEN 3 ELSE 9 END
    ELSE
      CASE source_system_id WHEN 'AMLKYC' THEN 1 WHEN 'CRM' THEN 2 WHEN 'LEND' THEN 3 ELSE 9 END
    END AS source_priority,
    CASE WHEN latest_first
      THEN 'v1: latest nonblank; tie CRM>AMLKYC>LEND; stable source ID'
      ELSE 'v1: nonblank AMLKYC>CRM>LEND; newest within priority; stable source ID'
    END::varchar(200) AS survivorship_rule
  FROM values_by_attribute v WHERE selected_value IS NOT NULL
)
SELECT p.*, row_number() OVER (
  PARTITION BY customer_id, attribute_name
  ORDER BY
    CASE WHEN latest_first THEN source_last_updated_at END DESC NULLS LAST,
    source_priority,
    source_last_updated_at DESC NULLS LAST,
    source_system_id, source_customer_reference, source_record_version DESC,
    source_customer_record_id, match_id
) AS candidate_rank
FROM priorities p;

-- Enforce this invariant rather than relying only on a table comment.
-- Existing duplicate current selections cause installation to fail visibly.
CREATE UNIQUE INDEX IF NOT EXISTS member3_one_current_attribute
  ON silver.customer_attribute_source(customer_id, attribute_name) WHERE is_current;
COMMIT;
