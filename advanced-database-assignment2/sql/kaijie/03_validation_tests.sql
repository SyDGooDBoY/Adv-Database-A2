-- Run after CALL silver.apply_member3_survivorship().
-- These structural checks work on B1 or B2. Empty data is a FAIL.
WITH checks AS (
 SELECT '01 populated master and provenance' AS test_name,
   EXISTS(SELECT 1 FROM silver.customer_attribute_source) AS ok
 UNION ALL
 SELECT '02 current provenance uses current accepted matching and successful batch',
   NOT EXISTS (
     SELECT 1 FROM silver.customer_attribute_source p
     JOIN silver.customer_source_match m USING(match_id)
     JOIN silver.source_customer_record s USING(source_customer_record_id)
     JOIN silver.ingestion_batch b USING(batch_id)
     WHERE p.is_current AND (m.match_status <> 'ACCEPTED' OR NOT m.is_current_match
       OR m.customer_id IS DISTINCT FROM p.customer_id OR NOT s.is_current_version
       OR m.effective_to IS NOT NULL OR s.valid_to IS NOT NULL
       OR b.load_status <> 'SUCCEEDED' OR b.source_system_id <> s.source_system_id))
 UNION ALL
 SELECT '03 one current selection per customer attribute', NOT EXISTS (
   SELECT 1 FROM silver.customer_attribute_source WHERE is_current
   GROUP BY customer_id, attribute_name HAVING count(*) > 1)
 UNION ALL
 SELECT '04 current selected values equal master attributes', NOT EXISTS (
   SELECT 1 FROM silver.customer_attribute_source p
   JOIN silver.customer_master c USING(customer_id)
   WHERE p.is_current AND p.selected_value IS DISTINCT FROM (to_jsonb(c)->>p.attribute_name))
 UNION ALL
 SELECT '05 historical selection matches customer and attribute', NOT EXISTS (
   SELECT 1 FROM silver.customer_history h JOIN silver.customer_attribute_source p USING(attribute_source_id)
   WHERE h.customer_id <> p.customer_id OR h.attribute_name <> p.attribute_name
     OR h.new_value IS DISTINCT FROM p.selected_value)
 UNION ALL
 SELECT '06 no overlapping provenance periods', NOT EXISTS (
   SELECT 1 FROM silver.customer_attribute_source a JOIN silver.customer_attribute_source b
     ON a.customer_id=b.customer_id AND a.attribute_name=b.attribute_name
     AND a.attribute_source_id < b.attribute_source_id
   WHERE tsrange(a.effective_from,a.effective_to,'[)') && tsrange(b.effective_from,b.effective_to,'[)'))
 UNION ALL
 SELECT '07 no overlapping value history periods', NOT EXISTS (
   SELECT 1 FROM silver.customer_history a JOIN silver.customer_history b
     ON a.customer_id=b.customer_id AND a.attribute_name=b.attribute_name
     AND a.customer_history_id < b.customer_history_id
   WHERE tsrange(a.effective_from,a.effective_to,'[)') && tsrange(b.effective_from,b.effective_to,'[)'))
 UNION ALL
 SELECT '08 every v1 selection has source-to-master lineage', NOT EXISTS (
   SELECT 1 FROM silver.customer_attribute_source p WHERE p.survivorship_rule LIKE 'v1:%'
   AND NOT EXISTS (SELECT 1 FROM silver.data_lineage_record l
     WHERE l.transformation_name='member3_attribute_survivorship'
       AND l.target_record_reference=p.customer_id AND l.target_attribute_name=p.attribute_name
       AND (l.target_record_snapshot::jsonb->>'attribute_source_id')=p.attribute_source_id))
 UNION ALL
 SELECT '09 no-source status has no current source selections', NOT EXISTS (
   SELECT 1 FROM silver.customer_master c JOIN silver.customer_attribute_source p USING(customer_id)
   WHERE c.customer_status='NO_CURRENT_SOURCE' AND p.is_current)
)
SELECT test_name, CASE WHEN ok THEN 'PASS' ELSE 'FAIL' END AS result FROM checks ORDER BY test_name;

-- Prove exact rerun equality for all four output tables, including timestamps.
-- The trial call is rolled back. Run this whole transaction together.
BEGIN;
CREATE TEMP TABLE member3_before_master ON COMMIT DROP AS TABLE silver.customer_master;
CREATE TEMP TABLE member3_before_source ON COMMIT DROP AS TABLE silver.customer_attribute_source;
CREATE TEMP TABLE member3_before_history ON COMMIT DROP AS TABLE silver.customer_history;
CREATE TEMP TABLE member3_before_lineage ON COMMIT DROP AS TABLE silver.data_lineage_record;
CALL silver.apply_member3_survivorship();
SELECT '10 exact rerun leaves four output tables unchanged' AS test_name,
 CASE WHEN NOT EXISTS (
   (SELECT * FROM silver.customer_master EXCEPT ALL SELECT * FROM member3_before_master)
   UNION ALL (SELECT * FROM member3_before_master EXCEPT ALL SELECT * FROM silver.customer_master)
 ) AND NOT EXISTS (
   (SELECT * FROM silver.customer_attribute_source EXCEPT ALL SELECT * FROM member3_before_source)
   UNION ALL (SELECT * FROM member3_before_source EXCEPT ALL SELECT * FROM silver.customer_attribute_source)
 ) AND NOT EXISTS (
   (SELECT * FROM silver.customer_history EXCEPT ALL SELECT * FROM member3_before_history)
   UNION ALL (SELECT * FROM member3_before_history EXCEPT ALL SELECT * FROM silver.customer_history)
 ) AND NOT EXISTS (
   (SELECT * FROM silver.data_lineage_record EXCEPT ALL SELECT * FROM member3_before_lineage)
   UNION ALL (SELECT * FROM member3_before_lineage EXCEPT ALL SELECT * FROM silver.data_lineage_record)
 ) THEN 'PASS' ELSE 'FAIL' END AS result;
ROLLBACK;

-- Screenshots: current values and the source chosen for each attribute.
SELECT c.customer_id,c.customer_full_name,c.email_address,c.residential_address,c.customer_status,
 p.attribute_name,p.selected_value,s.source_system_id,s.source_customer_reference,
 s.source_record_version,p.survivorship_rule
FROM silver.customer_master c
LEFT JOIN silver.customer_attribute_source p ON p.customer_id=c.customer_id AND p.is_current
LEFT JOIN silver.customer_source_match m USING(match_id)
LEFT JOIN silver.source_customer_record s USING(source_customer_record_id)
ORDER BY c.customer_id,p.attribute_name;

SELECT customer_id,attribute_name,old_value,new_value,effective_from,effective_to,change_reason
FROM silver.customer_history ORDER BY effective_from,customer_id,attribute_name;
