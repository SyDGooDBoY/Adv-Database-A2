-- Module 2: Customer indentity matching
-- Step 5: Validate the key requirements and supplied test scenarios

WITH current_matches AS (
    SELECT
        scr.source_system_id,
        scr.source_customer_reference,
        scr.source_record_version,
        scr.is_current_version,
        m.customer_id,
        m.match_status,
        m.manual_review_flag,
        m.is_current_match
    FROM silver.source_customer_record scr
    LEFT JOIN silver.customer_source_match m
      ON m.source_customer_record_id = scr.source_customer_record_id
     AND m.is_current_match = TRUE
),
tests AS (

    -- 1. Member 1 + Step 1 should retain all successful customer versions.
    SELECT
        1 AS test_order,
        '28 successful Silver source versions retained' AS test_name,
        CASE WHEN COUNT(*) = 28 THEN 'PASS' ELSE 'FAIL' END AS result,
        'actual=' || COUNT(*) AS details
    FROM silver.source_customer_record

    UNION ALL

    -- 2. Update/delete processing should leave exactly 25 current records.
    SELECT
        2,
        '25 source customer records are current',
        CASE WHEN COUNT(*) = 25 THEN 'PASS' ELSE 'FAIL' END,
        'actual=' || COUNT(*)
    FROM silver.source_customer_record
    WHERE is_current_version = TRUE

    UNION ALL

    -- 3. Every current source record must receive a current decision.
    SELECT
        3,
        'Every current source record has a current match decision',
        CASE WHEN COUNT(*) FILTER (WHERE match_status IS NULL) = 0
             THEN 'PASS' ELSE 'FAIL' END,
        'missing=' || COUNT(*) FILTER (WHERE match_status IS NULL)
    FROM current_matches
    WHERE is_current_version = TRUE

    UNION ALL

    -- 4. Accepted records must point to an enterprise customer.
    SELECT
        4,
        'Every ACCEPTED decision has a customer_id',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        'violations=' || COUNT(*)
    FROM current_matches
    WHERE is_current_match = TRUE
      AND match_status = 'ACCEPTED'
      AND customer_id IS NULL

    UNION ALL

    -- 5. Dataset expectation: 13 resolved enterprise customers.
    SELECT
        5,
        'Accepted records resolve to 13 enterprise customers',
        CASE WHEN COUNT(DISTINCT customer_id) = 13 THEN 'PASS' ELSE 'FAIL' END,
        'actual=' || COUNT(DISTINCT customer_id)
    FROM current_matches
    WHERE is_current_match = TRUE
      AND match_status = 'ACCEPTED'

    UNION ALL

    -- 6. Alice should consolidate CRM + Lending + AML/KYC into one customer.
    SELECT
        6,
        'Alice: three source records -> one customer',
        CASE WHEN COUNT(*) = 3
               AND COUNT(DISTINCT customer_id) = 1
               AND BOOL_AND(match_status = 'ACCEPTED')
             THEN 'PASS' ELSE 'FAIL' END,
        'records=' || COUNT(*) ||
        ', customers=' || COUNT(DISTINCT customer_id)
    FROM current_matches
    WHERE (source_system_id = 'CRM'    AND source_customer_reference = 'CRM-001')
       OR (source_system_id = 'LEND'   AND source_customer_reference = 'LEND-001')
       OR (source_system_id = 'AMLKYC' AND source_customer_reference = 'KYC-001')

    UNION ALL

    -- 7. Daniel's Lending record must remain unresolved because the DOB conflicts.
    SELECT
        7,
        'Daniel: Lending record -> manual review',
        CASE WHEN COUNT(*) = 1
               AND BOOL_AND(match_status = 'PENDING_REVIEW')
               AND BOOL_AND(manual_review_flag = TRUE)
               AND BOOL_AND(customer_id IS NULL)
             THEN 'PASS' ELSE 'FAIL' END,
        'expected LEND-002 = PENDING_REVIEW'
    FROM current_matches
    WHERE source_system_id = 'LEND'
      AND source_customer_reference = 'LEND-002'
      AND is_current_version = TRUE

    UNION ALL

    -- 8. Ethan's CRM email update must keep the CRM/KYC identity connected.
    SELECT
        8,
        'Ethan: CRM V2 + KYC remain one customer',
        CASE WHEN COUNT(*) = 2
               AND COUNT(DISTINCT customer_id) = 1
               AND MAX(CASE
                         WHEN source_system_id = 'CRM'
                         THEN source_record_version
                       END) = 2
             THEN 'PASS' ELSE 'FAIL' END,
        'expected CRM-006 V2 and KYC-006 to share one customer'
    FROM current_matches
    WHERE is_current_version = TRUE
      AND (
          (source_system_id = 'CRM'    AND source_customer_reference = 'CRM-006')
          OR
          (source_system_id = 'AMLKYC' AND source_customer_reference = 'KYC-006')
      )

    UNION ALL

    -- 9. Ava's CRM delete must leave no current source record / match.
    SELECT
        9,
        'Ava: deleted CRM identity is not current',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        'current rows=' || COUNT(*)
    FROM current_matches
    WHERE source_system_id = 'CRM'
      AND source_customer_reference = 'CRM-007'
      AND (is_current_version = TRUE OR is_current_match = TRUE)
)
SELECT *
FROM tests
ORDER BY test_order;


-- Report/demo query: current source identity -> final matching decision.
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
  ON m.source_customer_record_id = scr.source_customer_record_id
WHERE scr.is_current_version = TRUE
  AND m.is_current_match = TRUE
ORDER BY COALESCE(m.customer_id, 'ZZZ'),
         scr.source_system_id,
         scr.source_customer_reference;