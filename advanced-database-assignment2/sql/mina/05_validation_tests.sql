-- PostgreSQL 15+
-- Member 2: Customer Identity Matching
-- Step 5 - Acceptance tests.
--
-- Run after Member 1 scripts 01-06 and Member 2 scripts 01-04.
-- expected_identity_map.csv is used only as the intended test fixture;
-- it is never read by the matching algorithm.

WITH current_records AS (
    SELECT *
    FROM silver.source_customer_record
    WHERE is_current_version = TRUE
),
current_matches AS (
    SELECT
        scr.source_customer_record_id,
        scr.source_system_id,
        scr.source_customer_reference,
        scr.source_record_version,
        scr.is_current_version,
        m.customer_id,
        m.match_status,
        m.match_confidence_score,
        m.match_rule,
        m.manual_review_flag,
        m.is_current_match
    FROM silver.source_customer_record scr
    LEFT JOIN silver.customer_source_match m
      ON m.source_customer_record_id = scr.source_customer_record_id
     AND m.is_current_match = TRUE
),
tests AS (

    SELECT
        1 AS test_order,
        'Silver retains 28 successful customer source versions after B2 CRM' AS test_name,
        CASE WHEN COUNT(*) = 28 THEN 'PASS' ELSE 'FAIL' END AS result,
        'actual=' || COUNT(*)::text || ', expected=28' AS details
    FROM silver.source_customer_record

    UNION ALL

    SELECT
        2,
        'Exactly 25 customer source records are current after update/delete/insert',
        CASE WHEN COUNT(*) = 25 THEN 'PASS' ELSE 'FAIL' END,
        'actual=' || COUNT(*)::text || ', expected=25'
    FROM current_records

    UNION ALL

    SELECT
        3,
        'At most one current version exists for each source customer identity',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text || ' violating identities'
    FROM (
        SELECT
            source_system_id,
            source_customer_reference
        FROM current_records
        GROUP BY
            source_system_id,
            source_customer_reference
        HAVING COUNT(*) > 1
    ) v

    UNION ALL

    SELECT
        4,
        'Every current source record has one current matching decision',
        CASE
            WHEN COUNT(*) FILTER (WHERE match_status IS NULL) = 0
             AND COUNT(*) = 25
            THEN 'PASS' ELSE 'FAIL'
        END,
        'current records=' || COUNT(*)::text
        || ', without decision='
        || COUNT(*) FILTER (WHERE match_status IS NULL)::text
    FROM current_matches
    WHERE is_current_version = TRUE

    UNION ALL

    SELECT
        5,
        'Every ACCEPTED current decision has a customer_id',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text || ' violating rows'
    FROM current_matches
    WHERE is_current_match = TRUE
      AND match_status = 'ACCEPTED'
      AND customer_id IS NULL

    UNION ALL

    SELECT
        6,
        'Every PENDING_REVIEW decision is flagged and has no confirmed customer_id',
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END,
        COUNT(*)::text || ' violating rows'
    FROM current_matches
    WHERE is_current_match = TRUE
      AND match_status = 'PENDING_REVIEW'
      AND (
          COALESCE(manual_review_flag, FALSE) = FALSE
          OR customer_id IS NOT NULL
      )

    UNION ALL

    SELECT
        7,
        'Current accepted records resolve to 13 enterprise customers',
        CASE WHEN COUNT(DISTINCT customer_id) = 13 THEN 'PASS' ELSE 'FAIL' END,
        'actual=' || COUNT(DISTINCT customer_id)::text || ', expected=13'
    FROM current_matches
    WHERE is_current_match = TRUE
      AND match_status = 'ACCEPTED'

    UNION ALL

    SELECT
        10,
        'P001 Alice: CRM-001, LEND-001 and KYC-001 resolve to one customer',
        CASE
            WHEN COUNT(*) = 3
             AND COUNT(DISTINCT customer_id) = 1
             AND COUNT(*) FILTER (WHERE match_status = 'ACCEPTED') = 3
            THEN 'PASS' ELSE 'FAIL'
        END,
        'expected 3 accepted records sharing one customer_id'
    FROM current_matches
    WHERE (source_system_id = 'CRM'    AND source_customer_reference = 'CRM-001')
       OR (source_system_id = 'LEND'   AND source_customer_reference = 'LEND-001')
       OR (source_system_id = 'AMLKYC' AND source_customer_reference = 'KYC-001')

    UNION ALL

    SELECT
        11,
        'P002 Daniel: LEND-002 is held for manual review because DOB conflicts',
        CASE
            WHEN COUNT(*) = 1
             AND BOOL_AND(match_status = 'PENDING_REVIEW')
             AND BOOL_AND(manual_review_flag = TRUE)
             AND BOOL_AND(customer_id IS NULL)
            THEN 'PASS' ELSE 'FAIL'
        END,
        'expected LEND-002 = PENDING_REVIEW'
    FROM current_matches
    WHERE source_system_id = 'LEND'
      AND source_customer_reference = 'LEND-002'
      AND is_current_version = TRUE

    UNION ALL

    SELECT
        12,
        'P003 Maya: CRM-003 and KYC-003 resolve to one customer despite address difference',
        CASE
            WHEN COUNT(*) = 2
             AND COUNT(DISTINCT customer_id) = 1
             AND COUNT(*) FILTER (WHERE match_status = 'ACCEPTED') = 2
            THEN 'PASS' ELSE 'FAIL'
        END,
        'expected 2 accepted records sharing one customer_id'
    FROM current_matches
    WHERE (source_system_id = 'CRM'    AND source_customer_reference = 'CRM-003')
       OR (source_system_id = 'AMLKYC' AND source_customer_reference = 'KYC-003')

    UNION ALL

    SELECT
        13,
        'P006 Ethan: CRM V2 and KYC-006 keep one identity after CRM email update',
        CASE
            WHEN COUNT(*) = 2
             AND COUNT(DISTINCT customer_id) = 1
             AND MAX(
                 CASE
                     WHEN source_system_id = 'CRM'
                      AND source_customer_reference = 'CRM-006'
                     THEN source_record_version
                 END
             ) = 2
             AND COUNT(*) FILTER (WHERE match_status = 'ACCEPTED') = 2
            THEN 'PASS' ELSE 'FAIL'
        END,
        'expected current CRM-006 version 2 + KYC-006 sharing one customer_id'
    FROM current_matches
    WHERE is_current_version = TRUE
      AND (
             (source_system_id = 'CRM'
              AND source_customer_reference = 'CRM-006')
          OR (source_system_id = 'AMLKYC'
              AND source_customer_reference = 'KYC-006')
      )

    UNION ALL

    SELECT
        14,
        'P007 Ava: CRM deletion leaves no current source record or current match',
        CASE
            WHEN (
                SELECT COUNT(*)
                FROM current_records
                WHERE source_system_id = 'CRM'
                  AND source_customer_reference = 'CRM-007'
            ) = 0
             AND (
                SELECT COUNT(*)
                FROM silver.customer_source_match m
                JOIN silver.source_customer_record scr
                  ON scr.source_customer_record_id = m.source_customer_record_id
                WHERE scr.source_system_id = 'CRM'
                  AND scr.source_customer_reference = 'CRM-007'
                  AND m.is_current_match = TRUE
            ) = 0
            THEN 'PASS' ELSE 'FAIL'
        END,
        'expected no current CRM-007 identity after delete'
    FROM (VALUES (1)) AS one_row(x)

    UNION ALL

    SELECT
        15,
        'P010 Grace: CRM-010, LEND-010 and KYC-010 resolve to one customer',
        CASE
            WHEN COUNT(*) = 3
             AND COUNT(DISTINCT customer_id) = 1
             AND COUNT(*) FILTER (WHERE match_status = 'ACCEPTED') = 3
            THEN 'PASS' ELSE 'FAIL'
        END,
        'expected 3 accepted records sharing one customer_id'
    FROM current_matches
    WHERE (source_system_id = 'CRM'    AND source_customer_reference = 'CRM-010')
       OR (source_system_id = 'LEND'   AND source_customer_reference = 'LEND-010')
       OR (source_system_id = 'AMLKYC' AND source_customer_reference = 'KYC-010')

    UNION ALL

    SELECT
        16,
        'P011 Mia: late CRM insert becomes a current accepted standalone customer',
        CASE
            WHEN COUNT(*) = 1
             AND BOOL_AND(source_record_version = 1)
             AND BOOL_AND(match_status = 'ACCEPTED')
             AND BOOL_AND(customer_id IS NOT NULL)
            THEN 'PASS' ELSE 'FAIL'
        END,
        'expected current CRM-011 accepted after B2'
    FROM current_matches
    WHERE source_system_id = 'CRM'
      AND source_customer_reference = 'CRM-011'
      AND is_current_version = TRUE
)

SELECT
    test_order,
    test_name,
    result,
    details
FROM tests
ORDER BY test_order;


-- Report-ready evidence: current source -> enterprise customer mapping.
SELECT
    scr.source_system_id,
    scr.source_customer_reference,
    scr.source_record_version,
    scr.source_full_name,
    m.customer_id,
    m.match_status,
    m.match_confidence_score,
    m.match_rule,
    m.manual_review_flag
FROM silver.source_customer_record scr
JOIN silver.customer_source_match m
  ON m.source_customer_record_id = scr.source_customer_record_id
WHERE scr.is_current_version = TRUE
  AND m.is_current_match = TRUE
ORDER BY
    COALESCE(m.customer_id, 'ZZZ'),
    scr.source_system_id,
    scr.source_customer_reference;


-- Report-ready evidence: number of source records consolidated per customer.
SELECT
    m.customer_id,
    COUNT(*) AS current_source_records,
    STRING_AGG(
        scr.source_system_id || ':' || scr.source_customer_reference,
        ', '
        ORDER BY scr.source_system_id, scr.source_customer_reference
    ) AS source_identities
FROM silver.customer_source_match m
JOIN silver.source_customer_record scr
  ON scr.source_customer_record_id = m.source_customer_record_id
WHERE scr.is_current_version = TRUE
  AND m.is_current_match = TRUE
  AND m.match_status = 'ACCEPTED'
GROUP BY m.customer_id
ORDER BY current_source_records DESC, m.customer_id;
