-- Module 2: CUSTOMER IDENTITY MATCHING
-- Step 5: Simple validation checks

-- Test 1: Silver keeps all successful source versions
SELECT
    'Test 1 - source versions' AS test_name,
    COUNT(*) AS actual_rows,
    28 AS expected_rows
FROM silver.source_customer_record;


-- Test 2: Only current non-deleted source records are used for matching
SELECT
    'Test 2 - current source records' AS test_name,
    COUNT(*) AS actual_rows,
    25 AS expected_rows
FROM silver.source_customer_record
WHERE is_current_version = TRUE;


-- Test 3: Number of accepted enterprise customers.
SELECT
    'Test 3 - enterprise customers' AS test_name,
    COUNT(DISTINCT customer_id) AS actual_rows,
    13 AS expected_rows
FROM silver.customer_source_match
WHERE is_current_match = TRUE
  AND match_status = 'ACCEPTED';


-- Test 4: Alice should have three source records sharing one customer ID.
SELECT
    'Test 4 - Alice' AS test_name,
    COUNT(*) AS source_records,
    COUNT(DISTINCT m.customer_id) AS customer_ids
FROM silver.customer_source_match m
JOIN silver.source_customer_record scr
  ON m.source_customer_record_id = scr.source_customer_record_id
WHERE m.is_current_match = TRUE
  AND (
         (scr.source_system_id = 'CRM'
          AND scr.source_customer_reference = 'CRM-001')
      OR (scr.source_system_id = 'LEND'
          AND scr.source_customer_reference = 'LEND-001')
      OR (scr.source_system_id = 'AMLKYC'
          AND scr.source_customer_reference = 'KYC-001')
  );


-- Test 5: Daniel's Lending record should require manual review.
SELECT
    'Test 5 - Daniel' AS test_name,
    m.match_status,
    m.manual_review_flag,
    m.customer_id
FROM silver.customer_source_match m
JOIN silver.source_customer_record scr
  ON m.source_customer_record_id = scr.source_customer_record_id
WHERE m.is_current_match = TRUE
  AND scr.source_system_id = 'LEND'
  AND scr.source_customer_reference = 'LEND-002';


-- Test 6: Ethan should use CRM version 2 after the email update.
SELECT
    'Test 6 - Ethan current version' AS test_name,
    scr.source_system_id,
    scr.source_customer_reference,
    scr.source_record_version,
    m.customer_id
FROM silver.source_customer_record scr
JOIN silver.customer_source_match m
  ON scr.source_customer_record_id = m.source_customer_record_id
WHERE scr.is_current_version = TRUE
  AND m.is_current_match = TRUE
  AND (
         (scr.source_system_id = 'CRM'
          AND scr.source_customer_reference = 'CRM-006')
      OR (scr.source_system_id = 'AMLKYC'
          AND scr.source_customer_reference = 'KYC-006')
  )
ORDER BY scr.source_system_id;


-- Test 7: Ava's deleted CRM record should not have a current match.
SELECT
    'Test 7 - Ava deleted' AS test_name,
    COUNT(*) AS current_matches,
    0 AS expected_matches
FROM silver.customer_source_match m
JOIN silver.source_customer_record scr
  ON m.source_customer_record_id = scr.source_customer_record_id
WHERE m.is_current_match = TRUE
  AND scr.source_system_id = 'CRM'
  AND scr.source_customer_reference = 'CRM-007';


-- Final output for demonstration.
SELECT
    scr.source_system_id,
    scr.source_customer_reference,
    scr.source_full_name,
    m.customer_id,
    m.match_status,
    m.match_confidence_score,
    m.match_rule
FROM silver.source_customer_record scr
JOIN silver.customer_source_match m
  ON scr.source_customer_record_id = m.source_customer_record_id
WHERE scr.is_current_version = TRUE
  AND m.is_current_match = TRUE
ORDER BY
    COALESCE(m.customer_id, 'ZZZ'),
    scr.source_system_id,
    scr.source_customer_reference;